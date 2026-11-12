# Portfolio 5 — Distributed / Cloud

**Student:** Etim Christian Ime — 2026/A/MIT/0925 — MIT, Miva Open University — Sept 2026 cohort
**Database:** `pensions` (PostgreSQL 16)

## Files

| File | What it does |
|---|---|
| `01_partitioning.sql` | Rebuilds `contribution` as a partitioned parent (RANGE on `contribution_month`). A DO loop creates one partition per month for **every month in the data** plus next month, plus a `DEFAULT` partition. Migrates existing rows, recreates the report indexes on the parent, prints rows per partition, and shows one pruned one-month `EXPLAIN ANALYZE`. |
| `cloud_design.md` | Managed-database design: multi-AZ primary + synchronous standby + asynchronous read replica + tiered backups. Sync vs async trade-off. Nigerian data-protection notes (NDPA 2023, PenCom). |

## Partitioning strategy

* **Partition key:** `contribution_month` (RANGE by month).
* **Partitions:** one per month covering every month present in the bulk data (the DO loop walks `min(contribution_month)` to `max(contribution_month) + 1 month`) plus a `DEFAULT` partition for any future stragglers.
* **Unique constraints:** the parent's PK is `(contribution_id, contribution_month)` and the unique constraint is `(rsa_account_id, contribution_month)` — **both include the partition key**, which is what PG16 requires for a partitioned parent.
* **No exclusion constraints** on the parent — PG16 does not allow them, so we do not try.

## How to run

Run **after** P1 (schema + seed + bulk data):

```
psql -d pensions -v ON_ERROR_STOP=1 -f 01_partitioning.sql
```

What you should see at the bottom of the run:

* a table of rows-per-partition (top 12 by approx_rows);
* a `NOTICE` line per partition with the exact row count;
* an `EXPLAIN (ANALYZE, BUFFERS)` for a one-month query that only touches the current-month partition (look for `Subplans Removed` / a single `Seq Scan on contribution_YYYYMM`).

## Real output

Paste the actual rows-per-partition table and the pruned EXPLAIN here:

```
[paste real output here]
```

## AI-use note

Drafted by Z.ai GLM-5.2; tested and fixed by Claude; run by the student.
