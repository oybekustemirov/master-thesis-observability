# Next call with Kolbasin — walkthrough script

Prepared after the 2026-09-14 sync. His three asks, and where each is answered:

1. "Present a fully functional interactive HTML UI/Dashboard on localhost, running inside
   Docker containers" → §0 below, `docker/dashboard-compose.yml`.
2. "Explicit technical implementation details, exact experiment setup steps, and configuration
   parameters" → new **§8 "Exact configuration"** inside the dashboard itself, and
   `docs/empirical_comparison_results.md` §6 (full detail, file paths, annotated JSON).
3. Updated dissertation draft → `docs/empirical_comparison_results.md` §6 is the new material.

---

## 0. Before the call — bring the dashboard up

This container has **no dependency on Oracle or Kafka**. It is safe to start even if the
experiment stack is down or still warming up — unlike 2026-09-14, this cannot fail mid-call.

```bash
cd docker
docker compose -f dashboard-compose.yml up -d
```

Verify:

```bash
docker ps --format '{{.Names}}: {{.Status}}'   # obsv-dashboard: Up
curl -sI http://localhost:8082/ | head -1       # HTTP/1.1 200 OK
```

Open `http://localhost:8082/` in the browser you will share. Leave the terminal with `docker ps`
visible in another window or tab — you will switch to it once, deliberately (§1 below).

**If it still won't come up for any reason:** the file also opens directly with no Docker at all:
`C:\Users\O.Ustemirov\IdeaProjects\master-thesis-observability\docs\mechanism-comparison.html`.
Same content, zero infrastructure. Use this as the silent fallback; don't mention it unless needed.

---

## 1. Opening — prove the "running inside Docker" part first, briefly

He asked for it explicitly, so show it before he has to ask:

**SAY:**
> "Before we start — this dashboard is running in Docker now, not just a local file. Let me show you quickly."

Switch to the terminal, run:
```bash
docker ps --filter name=obsv-dashboard
```

**SAY:**
> "One container, nginx, serving the page on port 8082. It has no dependency on the database or Kafka stack, so it can't go down the way our environment did last time."

Switch back to the browser. This exchange takes 15 seconds and closes the loop on his request
before he has to bring it up.

---

## 2. Walk the dashboard — sections 1–7 (unchanged from last time)

If he already saw sections 1–7 on the previous call, move quickly — a recap, not a re-teach.

**SAY (recap, ~30s):**
> "Quick recap: four mechanisms, 175 archived experimental cells. The trigger is fastest but the
> only one where a defect stopped real payments — 40 percent failed in fault F8. CDC is nearly
> free to the database but slowest. The outbox and hybrid lose 69 percent of events when a batch
> job bypasses the application. Three predictions were tested and refuted. That's where we left
> off — today I want to show the exact setup behind those numbers."

Jump straight to §8.

---

## 3. Section 8 — "Exact configuration" (the new material, built from his request)

This is what he asked for on the 14th: "explicit technical implementation details, exact
experiment setup steps, and configuration parameters." Walk it top to bottom.

**Harness parameters:**
**SAY:**
> "Every cell: five repetitions, fifty transactions per second, two minutes steady-state. The
> repetitions are interleaved across modes rather than run back to back, and the mode order
> rotates each repetition — so no mode gets an unfair cold-cache or time-of-day advantage."

**Oracle instance table:**
**SAY:**
> "This is queried live from the running instance, not written from memory. 1.5 gigabytes SGA,
> 512 megabytes PGA, ARCHIVELOG with force logging. One thing I'll flag honestly: the redo log
> groups are only 10 megabytes each — the container image default, not something I tuned. Under
> the trigger's heavy write load that causes frequent log switches. It doesn't invalidate the
> comparison, since every mode runs against the same log configuration, but the absolute redo
> percentages are specific to this size of instance."

**Per-mode activation table:**
**SAY:**
> "This table is what actually runs at startup, automatically, not by hand — a component called
> ModeActivator sets exactly the trigger and logging state each mode needs, every run, so no two
> mechanisms are ever accidentally measured at once."

**Debezium parameters:**
**SAY:**
> "The retention value here — 180 seconds — isn't arbitrary. It's the exact number fault test F5
> targets: we hold a transaction open 240 seconds, 60 past this retention, specifically to
> confirm it gets silently discarded, which it does."

**Fault injection table:**
**SAY:**
> "Each fault is a real, specific action — not a simulation. F8 recompiles the trigger's package
> with a broken function, live, mid-run. F11 runs an actual PL/SQL batch that writes the table
> directly, bypassing the application entirely."

**Approach 1 / Approach 2 detail paragraphs:**
**SAY:**
> "And these two paragraphs are the exact schema and code path for the trigger and the outbox —
> queue names, table names, the write contract. Everything here has a file path in the written
> report if you want to open the source directly."

---

## 4. If he wants to see actual source code

You can show it live without leaving the dashboard idea — open a second tab/terminal:

```bash
cat src/main/resources/db/migration/V5__plsql_event_package.sql   # trigger + package
cat src/main/resources/db/migration/V3__outbox.sql                # outbox table + contract
cat docker/connect/connectors/cdc.json.tmpl                        # Debezium connector
```

**SAY:**
> "Here's the actual file — nothing in the dashboard is a summary of something that doesn't
> exist in the repo."

---

## 5. Section 9 — Q&A (unchanged, still there if he objects)

Same prepared answers as last time — sizes, statistical power, the C2 correction, the synthetic
workload caveat. Open it only if he pushes back on something; don't walk it unprompted this time,
since he already accepted these points on the 14th.

---

## 6. Closing

**SAY:**
> "That's the exact setup behind every number in the table. The full written version — with file
> paths for every single parameter — is in the updated chapter document if you'd like to review
> it offline before the defense."

Hand him (or screen-share) `docs/empirical_comparison_results.md`, scrolled to §6.

---

## Appendix — one-line health check before you join the call

```bash
docker ps --format '{{.Names}}: {{.Status}}' | grep -E 'dashboard|oracle|kafka'
curl -sI http://localhost:8082/ | head -1
```

If `obsv-dashboard` shows `Up` and the `curl` returns `200`, you are ready regardless of what the
rest of the stack (Oracle/Kafka) is doing.
