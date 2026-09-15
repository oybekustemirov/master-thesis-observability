#!/usr/bin/env python3
"""Prints the credit stage events that reached Kafka, as a readable timeline.

A separate file rather than a heredoc inside the demo script: the report needs its own quoting,
and nesting it produced a delimiter collision that silently truncated the script.
"""
import json
import sys


def dur(hours):
    """Hours as "3 kun 4 soat". The first version printed hours divided by 3600 with an "s"
    suffix, so 41 hours of collateral valuation read as "41.0s" - the thesis author read it as
    seconds and said the detail was unintelligible. Duration is the whole point of this report,
    so it is spelled out in the units a bank manager uses."""
    minutes = int(round(hours * 60))
    if minutes < 60:
        return "{} daqiqa".format(minutes)
    days, rem = divmod(minutes, 60 * 24)
    h, m = divmod(rem, 60)
    parts = []
    if days:
        parts.append("{} kun".format(days))
    if h:
        parts.append("{} soat".format(h))
    if m and not days:
        parts.append("{} daqiqa".format(m))
    return " ".join(parts)


def single(event):
    """One transition, printed as the demo drives it. The API returns the same shape the topic
    carries, so the live line and the replayed line are produced by the same code."""
    p = event.get("payload", event)
    queue = p.get("queueSeconds")
    work = p.get("workSeconds") or 0
    shown = "-" if queue is None else dur(queue / 3600)
    print("     {:<18} {:<30} navbat: {:<14} ish: {}".format(
        p.get("toStage", ""), (p.get("stageName") or "")[:28], shown, dur(work / 3600)))


def main():
    # Kafka topic deletion is asynchronous: the create that follows four seconds later can land
    # while the old topic is still being removed, leaving its messages in place. Filtering on the
    # application reference is robust to that and is also honest — a real topic carries every
    # application, and this report is about one of them.
    only = None
    if "--ref" in sys.argv:
        only = sys.argv[sys.argv.index("--ref") + 1]

    if "--single" in sys.argv:
        raw = sys.stdin.read().strip()
        if raw.startswith("{"):
            single(json.loads(raw))
        return
    rows = []
    for line in sys.stdin:
        line = line.strip()
        if not line.startswith("{"):
            continue
        try:
            event = json.loads(line)
        except ValueError:
            continue
        payload = event.get("payload", event)
        if only and payload.get("appRef") != only:
            continue
        rows.append(payload)

    if not rows:
        print("  Topikda hodisa yo'q.")
        return

    # Classified by STAGE TYPE, not by whether someone picked the case up.
    #
    # workSeconds is simply completed-minus-picked-or-entered, so for a stage where nobody acts
    # it is the whole interval — and summing it blindly reported 81.6 % of a mortgage's life as
    # "work", which is the exact opposite of what the data says. Only a HUMAN stage with a
    # pickup contains work; everywhere else the clock is running on somebody who is not the bank.
    buckets = {
        "Bank navbati": 0.0,
        "Bank xodimi ishlayapti": 0.0,
        "Mijozni kutish": 0.0,
        "Tashqi tomon": 0.0,
        "Qo'mita kalendari": 0.0,
        "Avtomatik": 0.0,
    }
    for i, p in enumerate(rows, 1):
        queue = p.get("queueSeconds")
        work = p.get("workSeconds") or 0
        kind = (p.get("stageType") or "AUTOMATED").upper()
        qh, wh = (queue or 0) / 3600, work / 3600

        if kind == "HUMAN":
            buckets["Bank navbati"] += qh
            buckets["Bank xodimi ishlayapti"] += wh
            shown = "{} navbatda + {} ish".format(dur(qh), dur(wh))
        elif kind == "CUSTOMER":
            buckets["Mijozni kutish"] += qh + wh
            shown = "{} mijozda".format(dur(qh + wh))
        elif kind == "EXTERNAL":
            buckets["Tashqi tomon"] += qh + wh
            shown = "{} tashqi tomonda".format(dur(qh + wh))
        elif kind == "COMMITTEE":
            buckets["Qo'mita kalendari"] += qh + wh
            shown = "{} qo'mitani kutish".format(dur(qh + wh))
        else:
            buckets["Avtomatik"] += qh + wh
            shown = "{} avtomatik".format(dur(qh + wh))

        print("  {:>2}. {:<18} {:<30} {}".format(
            i, p.get("toStage", ""), (p.get("stageName") or "")[:28], shown))

    span = sum(buckets.values())
    print()
    print("  Jami {} ta hodisa topikda.".format(len(rows)))
    print("  Ariza boshidan oxirigacha: {}.".format(dur(span)))
    print()
    for name, hours in sorted(buckets.items(), key=lambda kv: -kv[1]):
        if hours <= 0:
            continue
        print("    {:<26} {:>16}   {:>5.1f} %".format(
            name, dur(hours), 100 * hours / span if span else 0))
    print()
    work_share = 100 * buckets["Bank xodimi ishlayapti"] / span if span else 0
    print("  Bank xodimi haqiqatan ishlagan vaqt: {:.1f} %".format(work_share))
    print()
    print("  Har bir hodisa ariza holatining o'zgarishi bilan BITTA tranzaksiyada yozilgan.")
    print("  Bittasi yo'qolsa, ariza bosqichni o'tkazib yuborgandek ko'rinadi va oldingi")
    print("  bosqichning davomiyligi jimgina oshib ketadi.")


if __name__ == "__main__":
    main()
