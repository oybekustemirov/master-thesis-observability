#!/usr/bin/env python3
"""
Computes the reliability and latency metrics of one experiment run.

Reconciliation key: (txn_id, new_status).

That key is the only one available in EVERY mode. Wrapper events carry an event sequence but
no SCN; Debezium change events carry an SCN but no event sequence; AQ messages carry both but
in a different shape. A state transition is uniquely identified by the transaction and the
status it moved to, because an A1 transaction enters each status at most once — so the key is
mode-independent, which is what makes the modes comparable at all.

Ground truth comes from GROUND_TRUTH, written by a trigger inside the same transaction as the
business change and therefore independent of every pipeline under test.
"""
import argparse
import json
import statistics
import sys
from collections import Counter, defaultdict

STATUS_ORDER = {"INITIATED": 1, "VALIDATED": 2, "PROCESSED": 3, "REJECTED": 3}


def extract(msg):
    """Return (txn_id, new_status) from any of the message shapes the modes produce.

    Shapes handled:
      * A1Event envelope (WRAPPER_B1/B2/B3, HYBRID): payload.txnId / payload.status
      * PKG_A1_EVENT JSON (AQ):                      txnId / newStatus
      * Debezium change envelope (CDC):              after.TXN_ID / after.STATUS
      * Debezium with unwrap SMT applied:            TXN_ID / STATUS
    """
    p = msg.get("payload") if isinstance(msg.get("payload"), dict) else None
    if p and "txnId" in p:
        return p.get("txnId"), p.get("status")
    if "txnId" in msg:
        return msg.get("txnId"), msg.get("newStatus") or msg.get("status")
    after = msg.get("after")
    if isinstance(after, dict):
        return after.get("TXN_ID"), after.get("STATUS")
    if "TXN_ID" in msg:
        return msg.get("TXN_ID"), msg.get("STATUS")
    return None, None


def load_ground_truth(path):
    """CSV: txn_id,event_seq,new_status,commit_epoch_ms"""
    gt, ts = {}, {}
    with open(path) as fh:
        for line in fh:
            line = line.strip()
            if not line or line.startswith("TXN_ID"):
                continue
            parts = [p.strip() for p in line.split(",")]
            if len(parts) < 4:
                continue
            try:
                txn, seq, status, epoch = int(parts[0]), int(parts[1]), parts[2], int(parts[3])
            except ValueError:
                continue
            gt[(txn, status)] = seq
            ts[(txn, status)] = epoch
    return gt, ts


def load_sink(path):
    """Tab-separated console-consumer output with metadata prefixes, e.g.

        CreateTime:1788356697001<TAB>Partition:3<TAB>Offset:12<TAB>{json}

    Fields are identified by PREFIX rather than by position, because the console consumer's
    field order depends on which print.* properties are enabled.

    Partition and offset are captured because ORDERING must be judged by Kafka's own delivery
    order within a partition, not by the message timestamp: timestamps have millisecond
    resolution and tie constantly at load, which would manufacture ordering violations that
    consumers never actually observe.
    """
    arrivals = []
    malformed = 0
    with open(path) as fh:
        for line in fh:
            line = line.rstrip("\n")
            if not line:
                continue
            ts = partition = offset = None
            value = None
            for field in line.split("\t"):
                if field.startswith("CreateTime:") or field.startswith("LogAppendTime:"):
                    ts = field.split(":", 1)[1]
                elif field.startswith("Partition:"):
                    partition = field.split(":", 1)[1]
                elif field.startswith("Offset:"):
                    offset = field.split(":", 1)[1]
                elif field.lstrip().startswith("{"):
                    value = field
            if value is None or ts is None:
                malformed += 1
                continue
            try:
                msg = json.loads(value)
                txn, status = extract(msg)
                if txn is None or status is None:
                    malformed += 1
                    continue
                arrivals.append({
                    "txn": int(txn), "status": status, "ts": int(ts),
                    "partition": int(partition) if partition is not None else 0,
                    "offset": int(offset) if offset is not None else 0,
                })
            except (ValueError, TypeError):
                malformed += 1
    return arrivals, malformed


def percentile(values, q):
    if not values:
        return None
    s = sorted(values)
    idx = min(int(round(q * (len(s) - 1))), len(s) - 1)
    return s[idx]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--ground-truth", required=True)
    ap.add_argument("--sink", required=True)
    ap.add_argument("--mode", required=True)
    ap.add_argument("--profile", default="")
    ap.add_argument("--rep", default="1")
    ap.add_argument("--fault", default="none")
    ap.add_argument("--json-out", default="")
    args = ap.parse_args()

    gt, gt_ts = load_ground_truth(args.ground_truth)
    arrivals, malformed = load_sink(args.sink)

    seen = Counter((a["txn"], a["status"]) for a in arrivals)
    delivered = set(seen)

    missing  = set(gt) - delivered          # committed but never emitted -> LOSS
    phantom  = delivered - set(gt)          # emitted but never committed -> PHANTOM
    matched  = set(gt) & delivered

    n_gt = len(gt)

    # OFF and BASELINE_GT emit nothing by design: they are baselines, not pipelines.
    # Scoring them as 100% loss would be arithmetically true and analytically meaningless,
    # and would poison any aggregate table that averaged across modes.
    no_pipeline = args.mode in ("OFF", "BASELINE_GT")

    loss_rate = (len(missing) / n_gt) if n_gt else 0.0
    total_deliveries = sum(seen.values())
    duplicates = total_deliveries - len(delivered)
    dup_rate = (duplicates / len(delivered)) if delivered else 0.0

    # End-to-end latency: first arrival on the bus minus commit time of that transition.
    first_arrival = {}
    for a in arrivals:
        key = (a["txn"], a["status"])
        if key not in first_arrival or a["ts"] < first_arrival[key]:
            first_arrival[key] = a["ts"]
    latencies = [first_arrival[k] - gt_ts[k] for k in matched
                 if k in first_arrival and k in gt_ts]
    # A negative latency means the message was stamped BEFORE the transaction it describes
    # committed. Between processes on one host that cannot happen by clock skew, so a
    # non-trivial count of them means the timestamp is not the arrival time at all. This is not
    # hypothetical: the outbox EventRouter, configured with table.field.event.timestamp, stamps
    # records with the outbox row's CREATED_AT and produced a median latency of -1 ms — a
    # result that looks like an outstandingly fast pipeline rather than like a broken clock.
    negative = sum(1 for x in latencies if x < 0)
    latencies = [x for x in latencies if -60_000 < x < 3_600_000]   # discard clock outliers

    # Ordering violations, judged by Kafka's delivery order within a partition.
    # Keying on aggregate id sends every event of one transaction to the same partition, so
    # a violation here means the pipeline genuinely reordered a transaction's history — which
    # for an A1 workflow would mean a consumer could observe PROCESSED before VALIDATED.
    by_txn = defaultdict(list)
    for a in sorted(arrivals, key=lambda x: (x["partition"], x["offset"])):
        by_txn[a["txn"]].append(a["status"])
    violations = 0
    split_partitions = 0
    for txn, statuses in by_txn.items():
        ranks = [STATUS_ORDER.get(s, 0) for s in statuses]
        if any(b < a for a, b in zip(ranks, ranks[1:])):
            violations += 1
    partitions_per_txn = defaultdict(set)
    for a in arrivals:
        partitions_per_txn[a["txn"]].add(a["partition"])
    split_partitions = sum(1 for p in partitions_per_txn.values() if len(p) > 1)
    ovr = (violations / len(by_txn)) if by_txn else 0.0

    result = {
        "mode": args.mode, "profile": args.profile, "rep": args.rep, "fault": args.fault,
        "ground_truth_transitions": n_gt,
        "delivered_distinct": len(delivered),
        "delivered_total": total_deliveries,
        "matched": len(matched),
        "missing": len(missing),
        "phantom": len(phantom),
        "malformed": malformed,
        "loss_rate": round(loss_rate, 8),
        "loss_rate_ppm": round(loss_rate * 1_000_000, 2),
        "duplicate_rate": round(dup_rate, 8),
        "ordering_violation_rate": round(ovr, 8),
        # Must be zero: a transaction whose events landed on several partitions has no
        # ordering guarantee at all, and would indicate the partition key is wrong.
        "txns_split_across_partitions": split_partitions,
        "latency_ms_p50": percentile(latencies, 0.50),
        "latency_ms_p95": percentile(latencies, 0.95),
        "latency_ms_p99": percentile(latencies, 0.99),
        "latency_ms_max": max(latencies) if latencies else None,
        "latency_ms_mean": round(statistics.fmean(latencies), 1) if latencies else None,
        "latency_samples": len(latencies),
        "latency_negative_samples": negative,
    }

    if no_pipeline:
        # Keep the raw counts (they still show the workload actually ran and the control
        # instrument recorded it) but blank the pipeline metrics.
        for key in ("loss_rate", "loss_rate_ppm", "duplicate_rate",
                    "ordering_violation_rate", "phantom"):
            result[key] = None
        result["pipeline"] = "none (baseline mode)"
    # Rule of Three: with zero observed losses the honest claim is an UPPER BOUND, not zero.
    # Reporting "LR = 0" from a finite sample is unfalsifiable; "LR < 3/n at 95% confidence"
    # is defensible and is what belongs in the results chapter.
    elif len(missing) == 0 and n_gt > 0:
        result["loss_rate_upper_bound_95_ppm"] = round(3.0 / n_gt * 1_000_000, 2)

    print(json.dumps(result, indent=2))
    if args.json_out:
        with open(args.json_out, "w") as fh:
            json.dump(result, fh, indent=2)

    if missing and not no_pipeline:
        sample = sorted(missing)[:10]
        print(f"\nMISSING sample (up to 10): {sample}", file=sys.stderr)
    if phantom and not no_pipeline:
        sample = sorted(phantom)[:10]
        print(f"PHANTOM sample (up to 10): {sample}", file=sys.stderr)
    # Loud, because the failure it detects looks like a good result rather than a bad one.
    if negative and latencies and negative / max(len(latencies), 1) > 0.01:
        pct = 100.0 * negative / len(latencies)
        print(f"\nOGOHLANTIRISH: latensiyalarning {pct:.1f}% i manfiy ({negative} ta). "
              f"Xabar timestamp'i kelish vaqti emas - bu rejimning latensiya raqamlari "
              f"boshqa rejimlar bilan taqqoslanmaydi.", file=sys.stderr)


if __name__ == "__main__":
    main()
