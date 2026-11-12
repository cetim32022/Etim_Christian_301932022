# Portfolio 2 — Query Optimisation

**Student:** Etim Christian Ime — 2026/A/MIT/0925 — MIT, Miva Open University — Sept 2026 cohort
**Database:** `pensions` (PostgreSQL 16)

## Files

| File | What it does |
|---|---|
| `01_queries.sql` | 8 reporting queries for Lagos Heritage Pensions: 4 selective (Q1–Q4) and 4 full-table aggregates (Q5–Q8). |
| `02_explain_analyze.sql` | Drops the 3 P2 selective indexes, runs `EXPLAIN (ANALYZE, BUFFERS)` for Q1–Q4 **before**, recreates the indexes, runs them again **after**, and prints Q5 as a reference Seq Scan. |

## The 8 queries

| # | Type | Description |
|---|---|---|
| Q1 | Selective | RSA holder statement — 24 most recent contributions for one RSA account |
| Q2 | Selective | One employer's monthly contribution totals for the last 12 months |
| Q3 | Selective | One pension fund's latest unit price + 30-day moving average |
| Q4 | Selective | Last 30 days of posted contributions (across all employers) |
| Q5 | Aggregate | Total contributions per employer |
| Q6 | Aggregate | Average RSA balance per fund |
| Q7 | Aggregate | Withdrawal claims grouped by status + claim type |
| Q8 | Aggregate | Monthly contribution totals across the whole fund (last 24 months) |

## Indexes that P2 isolates

* `idx_contribution_rsa_month` on `contribution (rsa_account_id, contribution_month DESC)` — for Q1
* `idx_contribution_employer_month` on `contribution (employer_id, contribution_month DESC)` — for Q2
* `idx_contribution_posted_at` on `contribution (posted_at)` — for Q4

Q3 is selective on `fund_price`, which is already indexed by its composite primary key `(fund_id, price_date)`, so P2 does not add anything there — it is included in the BEFORE/AFTER block for completeness and is expected to be a fast index scan in both phases.

## Honest expectation

* Q1 should switch from a `Seq Scan on contribution` to an `Index Scan` using `idx_contribution_rsa_month`.
* Q2 should switch from a `Seq Scan` to an `Index Scan` using `idx_contribution_employer_month`.
* Q4 should switch from a `Seq Scan` plus sort to an `Index Scan` using `idx_contribution_posted_at` (or a `Bitmap Index Scan` + `Bitmap Heap Scan`).
* **Q5 (and the other full-table aggregates Q6–Q8) stay as `Seq Scan`** even with the new indexes — they touch most of the table, so the planner correctly chooses a sequential scan. P2 does not pretend otherwise; Q5 is printed at the end of `02_explain_analyze.sql` as a reference.

## How to run

```
psql -d pensions -v ON_ERROR_STOP=1 -f 01_queries.sql       > queries.out
psql -d pensions -v ON_ERROR_STOP=1 -f 02_explain_analyze.sql > explain.out
```

## Real output

Paste the `BEFORE` and `AFTER` plan summaries you actually got here:

```
[paste real output here]
```

## AI-use note

Drafted by Z.ai GLM-5.2; tested and fixed by Claude; run by the student.
