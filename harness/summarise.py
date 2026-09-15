#!/usr/bin/env python3
"""
Appends one row to results/summary.csv for a completed run, combining the reliability metrics
from analyze.py with the database counter deltas and the k6 throughput figures.

Writes the header only when the file is empty, so runs can be appended over days without
post-processing.
"""
import csv
import json
import os
import sys

FIELDS = [
    "run_id", "mode", "profile", "rep", "fault",
    "ground_truth_transitions", "delivered_distinct", "delivered_total",
    "missing", "phantom", "malformed",
    "loss_rate_ppm", "loss_rate_upper_bound_95_ppm", "duplicate_rate",
    "ordering_violation_rate",
    "latency_ms_p50", "latency_ms_p95", "latency_ms_p99", "latency_ms_max",
    "http_reqs", "http_req_failed_rate", "http_p95_ms", "http_p99_ms",
    "lifecycles", "achieved_tps",
    "redo_size_delta", "redo_entries_delta", "user_commits_delta",
    "db_block_changes_delta", "cpu_used_delta", "log_file_sync_delta_us",
    "redo_bytes_per_transition",
]


def read_stats(path):
    stats = {}
    if not os.path.exists(path):
        return stats
    with open(path) as fh:
        for line in fh:
            name, _, value = line.strip().rpartition(",")
            if name and value.strip().lstrip("-").isdigit():
                stats[name.strip()] = int(value)
    return stats


def k6_metric(summary, name, path, default=None):
    try:
        node = summary["metrics"][name]
        for key in path:
            node = node[key]
        return node
    except (KeyError, TypeError):
        return default


def main():
    out_dir = sys.argv[1]
    run_id = os.path.basename(out_dir.rstrip("/"))

    with open(os.path.join(out_dir, "metrics.json")) as fh:
        m = json.load(fh)

    before = read_stats(os.path.join(out_dir, "db_stats_before.csv"))
    after = read_stats(os.path.join(out_dir, "db_stats_after.csv"))
    delta = {k: after.get(k, 0) - before.get(k, 0) for k in after}

    summary = {}
    k6_path = os.path.join(out_dir, "k6-summary.json")
    if os.path.exists(k6_path):
        with open(k6_path) as fh:
            summary = json.load(fh)

    transitions = m.get("ground_truth_transitions") or 0
    redo_delta = delta.get("redo size", 0)

    row = {
        "run_id": run_id,
        **{k: m.get(k) for k in (
            "mode", "profile", "rep", "fault", "ground_truth_transitions",
            "delivered_distinct", "delivered_total", "missing", "phantom", "malformed",
            "loss_rate_ppm", "loss_rate_upper_bound_95_ppm", "duplicate_rate",
            "ordering_violation_rate", "latency_ms_p50", "latency_ms_p95",
            "latency_ms_p99", "latency_ms_max")},
        "http_reqs": k6_metric(summary, "http_reqs", ["count"]),
        "http_req_failed_rate": k6_metric(summary, "http_req_failed", ["value"]),
        "http_p95_ms": k6_metric(summary, "http_req_duration", ["p(95)"]),
        "http_p99_ms": k6_metric(summary, "http_req_duration", ["p(99)"]),
        "lifecycles": k6_metric(summary, "a1_lifecycles_completed", ["count"]),
        "achieved_tps": k6_metric(summary, "a1_lifecycles_completed", ["rate"]),
        "redo_size_delta": redo_delta,
        "redo_entries_delta": delta.get("redo entries", 0),
        "user_commits_delta": delta.get("user commits", 0),
        "db_block_changes_delta": delta.get("db block changes", 0),
        "cpu_used_delta": delta.get("CPU used by this session", 0),
        "log_file_sync_delta_us": delta.get("wait_log_file_sync", 0),
        # The headline performance number: redo written per committed state transition.
        # Comparing this against BASELINE_GT isolates the redo amplification each
        # mechanism actually costs.
        "redo_bytes_per_transition": round(redo_delta / transitions, 1) if transitions else None,
    }

    path = "results/summary.csv"
    exists = os.path.exists(path) and os.path.getsize(path) > 0
    with open(path, "a", newline="") as fh:
        writer = csv.DictWriter(fh, fieldnames=FIELDS, extrasaction="ignore")
        if not exists:
            writer.writeheader()
        writer.writerow(row)
    print(f"summary.csv ga qo'shildi: {run_id}", file=sys.stderr)


if __name__ == "__main__":
    main()
