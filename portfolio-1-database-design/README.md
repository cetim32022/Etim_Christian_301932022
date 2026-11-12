# Portfolio 1 — Database Design

**Student:** Etim Christian Ime — 2026/A/MIT/0925 — MIT, Miva Open University — Sept 2026 cohort
**Database:** `pensions` (PostgreSQL 16, Linux, GitHub Codespaces, non-root user, Unix socket)
**Run order:**

```
psql -d pensions -v ON_ERROR_STOP=1 -f 01_schema.sql
psql -d pensions -v ON_ERROR_STOP=1 -f 02_indexes.sql
psql -d pensions -v ON_ERROR_STOP=1 -f 03_seed_data.sql
psql -d pensions -v ON_ERROR_STOP=1 -f 04_bulk_data.sql
psql -d pensions -v ON_ERROR_STOP=1 -f 05_constraint_tests.sql
```

## What this portfolio covers

A normalised relational schema (3NF, 10 tables) for **Lagos Heritage Pensions Ltd**, a fictional Nigerian Pension Fund Administrator operating under the Contributory Pension Scheme. It models employers, employees with Retirement Savings Accounts (RSA), monthly employer and employee contributions, four RSA investment funds (Fund I–IV), daily fund unit prices, pension fund custodians, withdrawal and benefit claims, fund switches and beneficiaries.

Every primary key, foreign key, unique constraint, CHECK and trigger below is in `01_schema.sql` (and `02_indexes.sql` for indexes). RSA `balance` is **not** typed in by the user — it is maintained by a STATEMENT-level transition-table trigger that aggregates `contribution` rows and by a row-level trigger that fires when a `withdrawal_claim` moves to `PAID`.

### Tables

| # | Table | Purpose | Key constraints |
|---|---|---|---|
| 1 | `employer` | Nigerian employers remitting contributions | PK, UNIQUE(`employer_code`), CHECK on `monthly_contribution_day 1..28` |
| 2 | `pension_fund` | RSA Fund I–IV (PenCom fund categories) | PK, UNIQUE(`fund_code`), CHECK on `risk_profile` |
| 3 | `custodian` | Pension Fund Custodians holding the cash | PK, UNIQUE(`license_no`) |
| 4 | `employee` | RSA holders / scheme members | PK, FK to `employer`, UNIQUE(`employer_id, staff_no`), UNIQUE(`nin`), CHECK `monthly_salary > 0`, CHECK `gender IN ('M','F')` |
| 5 | `rsa_account` | The Retirement Savings Account | PK, FKs to `employee/fund/custodian`, UNIQUE(`rsa_number`), CHECK `balance >= 0`, CHECK `status` |
| 6 | `fund_price` | Daily unit price per fund | PK(`fund_id, price_date`), CHECK `unit_price > 0` |
| 7 | `contribution` | **Big table** — monthly contribution lines | PK, FKs, UNIQUE(`rsa_account_id, contribution_month`), CHECKs on amounts, GENERATED `total_amount` column |
| 8 | `withdrawal_claim` | Retirement / early / involuntary / death claims | PK, FK, CHECKs on `claim_type`, `status`, `amount`, partial UNIQUE index on `(rsa_account_id) WHERE status='OPEN'` |
| 9 | `fund_switch` | Member moves balance between funds | PK, FKs, CHECK `from_fund_id <> to_fund_id` |
| 10 | `beneficiary` | Nominees of an RSA holder | PK, FK, CHECK `0 < share_pct <= 100`, trigger keeps total ≤ 100% per RSA |

### Triggers (business rules that cannot be CHECKs)

| Trigger | Function | Why a trigger (not a CHECK) |
|---|---|---|
| `trg_contribution_minimum` | `check_contribution_minimum()` | Statutory 10 % employer / 8 % employee must be compared against `employee.monthly_salary` in another table |
| `trg_withdrawal_balance` | `check_withdrawal_balance()` | Claim `amount` must be ≤ current `rsa_account.balance` in another table |
| `trg_retirement_age` | `check_retirement_age()` | Age-at-claim depends on `CURRENT_DATE` (CHECK cannot use it) |
| `trg_balance_on_contribution_stmt` | `update_balance_on_contribution_stmt()` | Keeps `rsa_account.balance` in sync with the contribution ledger via a transition table — fast enough for the 60 k-row bulk load |
| `trg_balance_on_withdrawal` | `update_balance_on_withdrawal()` | Decrements `rsa_account.balance` when a claim moves to `PAID` |
| `trg_beneficiary_share` | `check_beneficiary_share()` | Sum of `share_pct` per RSA must not exceed 100 % — needs to read sibling rows |

### Partial UNIQUE index

```sql
CREATE UNIQUE INDEX one_open_claim_per_rsa
    ON withdrawal_claim (rsa_account_id)
    WHERE status = 'OPEN';
```

At most one `OPEN` withdrawal claim exists per RSA account at any time. Two `PAID` claims on the same account are allowed (history); a new `OPEN` claim cannot be created until the previous one is approved or rejected.

### Bulk data

`04_bulk_data.sql` produces:

* 1,200 new employees (gender-matched Nigerian first names + surnames, real Nigerian cities/states, salaries between ₦45,000 and ₦1,500,000)
* 1,200 new RSA accounts (one per bulk employee, fund chosen by age)
* **~60,000 `contribution` rows** via `generate_series(-49, 0)` × 1,200 accounts, all dated relative to `CURRENT_DATE` and ending inside the next 14 days as a small set of future-dated rows.

All bulk inserts are pure SQL with `generate_series` on integers and date arithmetic via `make_interval(months => ...)`. No Python loops.

### Constraint tests

`05_constraint_tests.sql` runs 11 tests, each inside `BEGIN ... ROLLBACK`:

1. `employer` PK duplicate → unique_violation
2. `employer.employer_code` UNIQUE → unique_violation
3. `employee.employer_id` FK → foreign_key_violation
4. `employee.monthly_salary > 0` CHECK → check_violation
5. `trg_contribution_minimum` (employer_share below 10 %) → check_violation
6. `trg_withdrawal_balance` (amount > balance) → check_violation
7. `trg_retirement_age` (under-50 retirement claim, no early flag) → check_violation
8. partial UNIQUE `one_open_claim_per_rsa` (two OPEN claims) → unique_violation
9. `beneficiary.share_pct <= 100` CHECK → check_violation
10. `trg_beneficiary_share` (total > 100 %) → check_violation
11. **Control test** — a fully valid contribution inserts exactly 1 row.

Each test prints `PASS` or `FAIL` via `RAISE NOTICE`.

### Real output

After running `05_constraint_tests.sql`, paste the `\echo` block here:

```
[paste real output here]
```

After running `04_bulk_data.sql`, paste the sanity-counts row here:

```
[paste real output here]
```

## AI-use note

Drafted by Z.ai GLM-5.2; tested and fixed by Claude; run by the student.
