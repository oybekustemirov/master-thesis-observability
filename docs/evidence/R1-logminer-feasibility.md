# Risk R1 — Retired: LogMiner-Based CDC Is Feasible on the Free Oracle Container

**Date:** 2026-09-02 · **Verdict: PASS.** Approach 3 (CDC) is viable in the thesis test environment.
**Significance:** R1 was the project's largest technical risk. Had it failed, Chapter 6 could not
have covered CDC and the thesis would have been reduced to a two-pattern comparison.

## Environment under test

| Item | Value |
|---|---|
| Image | `gvenzl/oracle-free:23-slim-faststart` |
| Reported version | **Oracle AI Database 26ai Free Release 23.26.3.0.0** |
| Architecture | Multitenant CDB (`FREE`) with PDBs `FREEPDB1`, `OBSVPDB` |
| Host | WSL2, 28 vCPU, 31 GB RAM, Docker 29.4.1 |
| Debezium compatibility | Debezium 3.5.x supports Oracle through 26ai — no version gap |

## Capabilities verified

| # | Capability | Command | Result |
|---|---|---|---|
| 1 | ARCHIVELOG mode | `SHUTDOWN IMMEDIATE; STARTUP MOUNT; ALTER DATABASE ARCHIVELOG; ALTER DATABASE OPEN;` | **PASS** — `LOG_MODE = ARCHIVELOG` |
| 2 | Force logging (closes the `NOLOGGING` capture gap, assumption A-4) | `ALTER DATABASE FORCE LOGGING;` | **PASS** — `FORCE_LOGGING = YES` |
| 3 | Database-level minimal supplemental logging | `ALTER DATABASE ADD SUPPLEMENTAL LOG DATA;` | **PASS** — `SUPPLEMENTAL_LOG_DATA_MIN = YES` |
| 4 | Table-level `ALL COLUMNS` supplemental logging | `ALTER TABLE obsv.txn_a1 ADD SUPPLEMENTAL LOG DATA (ALL) COLUMNS;` | **PASS** — `DBA_LOG_GROUPS.LOG_GROUP_TYPE = 'ALL COLUMN LOGGING'` |
| 5 | Debezium-equivalent capture user with `LOGMINING` | `CREATE USER c##dbzuser ... CONTAINER=ALL` + 13 grants | **PASS** |
| 6 | **Mining as a non-SYS user** | `DBMS_LOGMNR.ADD_LOGFILE` + `START_LOGMNR` + `SELECT FROM V$LOGMNR_CONTENTS` | **PASS** |
| 7 | **Before-images present in mined output** | inspection of `SQL_REDO` | **PASS** — see below |

## Decisive evidence: A1 state transitions recovered from redo

A single A1 transaction was driven through `INITIATED → VALIDATED → PROCESSED`, the log was
archived, and the SCN range was mined by `c##dbzuser` using exactly the mechanism Debezium uses
(explicit `ADD_LOGFILE`, `DICT_FROM_ONLINE_CATALOG`, `COMMITTED_DATA_ONLY`).

```
       SCN OPERATION SQL_REDO
---------- --------- ---------------------------------------------------------------------------
   2307018 INSERT    insert into "OBSV"."TXN_A1"("TXN_ID","TXN_REF","AMOUNT","STATUS")
                     values ('2','PMT-R1-MINE-001','42500000','INITIATED');
   2307021 UPDATE    update "OBSV"."TXN_A1" set "STATUS" = 'VALIDATED'
                      where "TXN_ID" = '2' and "TXN_REF" = 'PMT-R1-MINE-001'
                        and "AMOUNT" = '42500000' and "STATUS" = 'INITIATED'
                        and ROWID = 'AAAR6BAAcAAAAALAAB';
   2307024 UPDATE    update "OBSV"."TXN_A1" set "STATUS" = 'PROCESSED'
                      where "TXN_ID" = '2' and "TXN_REF" = 'PMT-R1-MINE-001'
                        and "AMOUNT" = '42500000' and "STATUS" = 'VALIDATED'
                        and ROWID = 'AAAR6BAAcAAAAALAAB';
```

All three transitions were captured, in commit order, with complete before-images. The `WHERE`
clause of each `UPDATE` carries every prior column value — this is the direct effect of
`SUPPLEMENTAL LOG DATA (ALL) COLUMNS`, and it is precisely the data Debezium projects into the
`before` block of its change envelope (compare with the sample payload in
`event-generation-approaches.md` §2.3.4). The mechanism is confirmed end to end at the database
layer, independently of the connector.

**Note for the performance chapter:** the redundancy visible in those `WHERE` clauses *is* the
redo amplification cost quantified in §3.3. The evidence for the capability and the evidence for
its cost are the same artefact — a useful observation to make explicitly in Chapter 6.

## Environment-specific findings worth documenting in Chapter 5

Four deviations from the standard Debezium setup instructions were encountered. All are
reproducible, all have documented causes, and all should appear in the implementation chapter —
they are exactly the kind of concrete detail that distinguishes a real implementation from a
paper design.

| # | Symptom | Cause | Resolution |
|---|---|---|---|
| 1 | `ORA-02236: invalid file name` on `CREATE TABLESPACE ... DATAFILE SIZE 100M` | `DB_CREATE_FILE_DEST` is unset in the image, so Oracle-Managed-Files syntax is unavailable | `ALTER SYSTEM SET DB_CREATE_FILE_DEST='/opt/oracle/oradata' SCOPE=BOTH;` |
| 2 | `ORA-65048` / `ORA-00959: tablespace 'LOGMINER_TBS' does not exist`, raised **for PDB `FREEPDB1`** while creating the common user | A common user created with `CONTAINER=ALL` requires its default tablespace to exist in **every** PDB, not only in `CDB$ROOT` | Create `logminer_tbs` in `CDB$ROOT` **and** in each PDB before creating the user. **This also applies to a real bank CDB and is a frequent first-attempt failure.** |
| 3 | `PLS-00201: identifier 'DBMS_FLASHBACK' must be declared` | `DBMS_FLASHBACK` is not among the grants in the standard Debezium instructions | Not required. Use `SELECT CURRENT_SCN FROM V$DATABASE`, which is what Debezium itself uses |
| 4 | `CONTINUOUS_MINE` unusable | The option was deprecated in 12.2 and **removed in 19c** | Add log files explicitly with `DBMS_LOGMNR.ADD_LOGFILE` in an SCN-bounded loop — the approach Debezium implements internally |
| 5 | `common_user_prefix` is empty in this image | Image-specific configuration | The `c##` prefix still works and is retained for portability with production CDBs |

## Consequences for the plan

* **Approach 3 stays in scope**, with LogMiner as the adapter. XStream remains out of scope
  (GoldenGate licence); OpenLogReplicator remains related work unless time permits.
* Fault cases **F4** (archive-log purge) and **F5** (transaction-retention overflow) are
  reproducible in this environment, since archiving and log switching both work under our control.
* The container reaches a usable state in roughly 3–5 minutes from a cold start, which is
  acceptable for a per-run reset in the experiment harness. Snapshotting the initialised container
  as an image will cut repeated setup time and should be built into the harness.

## Reproduction

Scripts: `docker/oracle/init/` (to be committed with the stack). Verified sequence:
container start → `r1_step1.sql` (ARCHIVELOG, FORCE LOGGING, supplemental logging) →
`r1_user3.sql` (tablespaces in all containers, capture user, grants) →
`r1_gen.sql` (A1 transitions, archive current log) →
`r1_mine2.sql` (add logfiles, `START_LOGMNR`, query `V$LOGMNR_CONTENTS`).
