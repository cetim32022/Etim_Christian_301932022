# Portfolio 3 — Transactions and Concurrency

**Student:** Etim Christian Ime — 2026/A/MIT/0925 — MIT, Miva Open University — Sept 2026 cohort
**Database:** `pensions` (PostgreSQL 16)

## Files

| File | What it does |
|---|---|
| `01_transactions.sql` | Three SQL-only transaction demos: (A) a committed contribution posting, (B) a rolled-back posting, (C) a SAVEPOINT recovery inside a batch where one row violates the statutory-minimum trigger and is skipped while the other two commit. |
| `race_demos.py` | Six labelled concurrency demos in Python using `psycopg2` and two real sessions (threads). Creates its own demo rows and deletes them at the end. |

## The chosen race-condition fix (required by the brief)

**Atomic conditional UPDATE**:

```sql
UPDATE rsa_account
   SET balance = balance - :amt
 WHERE rsa_account_id = :id
   AND balance >= :amt;
-- then check the row count returned by psycopg2 / libpq.
```

Scenario: two withdrawal requests hit the same RSA balance at the same time and together would overdraw it. With this pattern, only the thread that finds `balance >= :amt` actually moves the row (rowcount = 1); the other thread finds the predicate false (rowcount = 0) and reports "insufficient funds". PostgreSQL's row-level lock on the `UPDATE` serialises the two writers, so the second one re-evaluates `balance >= :amt` against the new balance and correctly fails the predicate. No `FOR UPDATE`, no advisory locks, no `SKIP LOCKED`.

## The six parts of `race_demos.py`

| Part | What it shows |
|---|---|
| 1 — the bug | Read-modify-write race: both threads `SELECT balance`, both compute `balance - amt`, both `UPDATE rsa_account SET balance = new_value`. The second write loses the first withdrawal, so total balance reduction < sum of the two claimed withdrawals. The PFA is short of real money. |
| 2 — CHECK constraint fix | Atomic decrement `UPDATE rsa_account SET balance = balance - :amt` combined with the schema `CHECK (balance >= 0)`. The second thread's UPDATE attempts to push the balance below 0 and is rejected with SQLSTATE 23514. |
| 3 — atomic conditional UPDATE | The required fix. One thread gets `rowcount = 1`, the other gets `rowcount = 0`. The app maps 0 → "insufficient funds". |
| 4 — SERIALIZABLE | Both threads run in SERIALIZABLE isolation. One commits, the other is aborted with SQLSTATE 40001 (`serialization_failure`) because the two read/write dependencies form a dangerous structure. |
| 5 — READ COMMITTED vs REPEATABLE READ | A long-running transaction reads `balance` twice with another transaction committing in between. Under READ COMMITTED the two reads differ; under REPEATABLE READ the snapshot is frozen at the first statement and the two reads are identical. |
| 6 — deadlock | Two threads acquire locks in opposite orders (A→B vs B→A). One is aborted with SQLSTATE 40P01 (`deadlock_detected`). The fixed-order version (both A→B) commits cleanly. |

## How to run

```
psql -d pensions -v ON_ERROR_STOP=1 -f 01_transactions.sql
python3 race_demos.py    # requires: pip install psycopg2-binary
```

`race_demos.py` opens connections over the Unix socket with `psycopg2.connect(dbname="pensions")`, which matches how `psql -d pensions` works on the same Codespaces box — no password, no TCP.

## Real output

Paste the actual stdout of `race_demos.py` here:

```
[paste real output here]
```

Paste the actual output of `01_transactions.sql` here:

```
[paste real output here]
```

## AI-use note

Drafted by Z.ai GLM-5.2; tested and fixed by Claude; run by the student.
