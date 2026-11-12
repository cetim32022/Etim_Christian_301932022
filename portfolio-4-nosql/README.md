# Portfolio 4 — NoSQL (MongoDB 7+)

**Student:** Etim Christian Ime — 2026/A/MIT/0925 — MIT, Miva Open University — Sept 2026 cohort
**Database:** `pensions` (MongoDB 7+, accessed as `mongosh pensions`)

## Files

| File | What it does |
|---|---|
| `01_setup.js` | Creates `member_documents` (flexible KYC + claim documents per RSA holder) and `portal_activity` (member login / statement-view logs) with `$jsonSchema` validators. |
| `02_data_and_queries.js` | Small seed (8 documents + 12 activity rows) plus 3 aggregation pipelines. |
| `03_bulk_and_index_demo.js` | Inserts 40,000 documents with `insertMany` in batches of 2,000, then runs the same selective query **before** (forced `COLLSCAN` via `hint({$natural:1})`) and **after** creating a compound index, and prints a Stage / Docs / Time summary table. |

## Why MongoDB sits next to PostgreSQL here

The relational schema in P1 is the right place for the money ledger (contributions, claims, balances, statutory minimums). MongoDB sits beside it for two workloads that are genuinely document-shaped:

* **`member_documents`** — KYC paperwork and claim forms whose fields vary by `document_type`. A BVN verification carries a `bvn` string; a claim form carries a `claim_id` and `claim_type`. Modeled with `oneOf` so a document must satisfy exactly one shape.
* **`portal_activity`** — high-volume event log where the field set varies by `activity_type` (`LOGIN` carries `login_method`; `STATEMENT_VIEW` carries `statement_period`). Same `oneOf` approach.

Both collections live in the same `pensions` database so the PFA's operational team has one place to look.

## Validator notes (per the brief)

* `enum` with ONE value is used for `status` ("ACCEPTED" / "SUCCESS") — these are extensible enum slots, not `const`.
* No `if/then/else` inside the schema — `oneOf` discriminates by `document_type` / `activity_type`.
* `additionalProperties: false` is set on every schema, and `_id` plus every allowed field is listed in `properties`.
* `db = db.getSiblingDB("pensions")` is used instead of `use pensions;` so the script can run as `mongosh pensions 01_setup.js` and still target the right database from any default.
* Numbers are wrapped in `Int32()` (for `file_size_bytes`, `duration_ms`) and `Long.fromString(...)` for `claim_id`.

## The 3 aggregation pipelines in `02_data_and_queries.js`

1. **Document counts per RSA, split by document_type** — `$group` on `{rsa_number, document_type}` with `$sum` and `$max(uploaded_at)`.
2. **Last-7-day portal activity per RSA** — `$match` on `occurred_at >= 7 days ago`, then `$group` with two `$sum + $cond` counters for `LOGIN` vs `STATEMENT_VIEW`.
3. **Claim-form uploads cross-referenced with portal logins within ±7 days** — `$match` on `document_type: CLAIM_FORM`, then `$lookup` against `portal_activity` with a `$let`/`$expr` join that pins `rsa_number`, `activity_type=LOGIN`, and an `occurred_at` window around `uploaded_at`.

## The bulk + index demo in `03_bulk_and_index_demo.js`

* 40,000 synthetic `portal_activity` documents, inserted with `insertMany` in batches of 2,000, `ordered: false`.
* Selective query: all `LOGIN` events for one `rsa_number`, sorted by `occurred_at DESC`, `LIMIT 50`.
* **BEFORE** the compound index: the query is run with `.hint({$natural: 1})` to force a `COLLSCAN`.
* **AFTER**: same query without the hint, with a compound index `{ rsa_number:1, activity_type:1, occurred_at:-1 }` named `bulk_rsa_occurred_1`.
* `dropIndex` is wrapped in `try/catch` both before and after.
* A summary table is printed at the end:

```
================ SUMMARY ================
Metric        BEFORE                AFTER
Stage         COLLSCAN              (IXSCAN / FETCH)
Docs examined <large>               <small>
Time (ms)     <large>               <small>
```

## How to run

```
mongosh pensions 01_setup.js
mongosh pensions 02_data_and_queries.js
mongosh pensions 03_bulk_and_index_demo.js
```

## Real output

Paste the actual `SUMMARY` block from `03_bulk_and_index_demo.js` here:

```
[paste real output here]
```

Paste the output of the 3 aggregation pipelines here:

```
[paste real output here]
```

## AI-use note

Drafted by Z.ai GLM-5.2; tested and fixed by Claude; run by the student.
