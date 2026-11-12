"""
race_demos.py
=============
Six labelled concurrency demos against the `pensions` PostgreSQL database.

Run with (from inside the portfolio-3-transactions-concurrency folder):

    python3 race_demos.py

Prerequisites
-------------
- PostgreSQL 16 running on the same host, Unix socket, database `pensions`,
  no password, no TCP (psql -d pensions works on the command line).
- psycopg2 installed:   pip install psycopg2-binary
- P1 schema + seed + bulk data already loaded.

What it does
------------
- Creates its own DEMO rows (two RSA accounts LHP/RSA/DEMO01 and LHP/RSA/DEMO02
  and the supporting employee row) and DELETES them at the end so the
  database is left exactly as it found it.
- Spawns two real psycopg2 sessions in two real Python threads for each demo.
- Prints clearly labelled parts:

    Part 1 - the bug (read balance, then UPDATE; two withdrawals overdraw
             the account via a lost-update)
    Part 2 - CHECK/UNIQUE constraint fix (atomic decrement + CHECK balance>=0
             raises check_violation on the second writer)
    Part 3 - atomic conditional UPDATE (the chosen P3 fix)
             UPDATE rsa_account SET balance = balance - :amt
             WHERE rsa_account_id = :id AND balance >= :amt
             then check the row count.
    Part 4 - SERIALIZABLE isolation (expects SQLSTATE 40001)
    Part 5 - READ COMMITTED vs REPEATABLE READ (snapshot visibility demo)
    Part 6 - Deadlock (SQLSTATE 40P01) plus the fixed-order version

No pg_sleep tricks that need hand-pasting, no two-terminal psql demos.
"""

from __future__ import annotations

import psycopg2
import threading
import time
import sys
from dataclasses import dataclass

DB_NAME = "pensions"

# Two demo accounts. We INSERT these once at the start and DELETE at the end.
DEMO_EMPLOYEE_ID_HOLD = -1   # filled in after we insert the demo employee
DEMO_RSA_1 = 9_999_901        # we set rsa_account_id explicitly so threads
DEMO_RSA_2 = 9_999_902        # can target the same row by ID without lookups


# --------------------------------------------------------------------------- #
# Helpers
# --------------------------------------------------------------------------- #
def conn(isolation: str | None = None) -> psycopg2.extensions.connection:
    """Open a psycopg2 connection over the Unix socket, no password."""
    c = psycopg2.connect(dbname=DB_NAME)
    c.autocommit = False
    if isolation:
        c.set_isolation_level(
            {
                "READ COMMITTED": psycopg2.extensions.ISOLATION_LEVEL_READ_COMMITTED,
                "REPEATABLE READ": psycopg2.extensions.ISOLATION_LEVEL_REPEATABLE_READ,
                "SERIALIZABLE": psycopg2.extensions.ISOLATION_LEVEL_SERIALIZABLE,
            }[isolation]
        )
    return c


def reset_demo_account(acct_id: int, balance: float) -> None:
    """Make sure a demo RSA account exists with the given balance."""
    c = conn()
    with c.cursor() as cur:
        cur.execute(
            """
            INSERT INTO rsa_account
                (rsa_account_id, rsa_number, employee_id, fund_id, custodian_id,
                 balance, status, opened_at)
            VALUES
                (%s, %s, %s, 1, 1, %s, 'ACTIVE', now())
            ON CONFLICT (rsa_account_id) DO UPDATE
              SET balance = EXCLUDED.balance,
                  status  = 'ACTIVE',
                  updated_at = now()
            """,
            (acct_id, f"LHP/RSA/DEMO{acct_id % 100:02d}", DEMO_EMPLOYEE_ID_HOLD, balance),
        )
    c.commit()
    c.close()


def ensure_demo_employee() -> None:
    """Insert a single demo employee so the FK on rsa_account.employee_id holds."""
    global DEMO_EMPLOYEE_ID_HOLD
    c = conn()
    with c.cursor() as cur:
        # Pick an employer that always exists in seed (id 1, Dangote).
        cur.execute(
            """
            INSERT INTO employee
                (employee_id, employer_id, staff_no, first_name, last_name,
                 gender, date_of_birth, hire_date, monthly_salary,
                 city, state, nin)
            VALUES
                (-1, 1, 'DEMO-001', 'Demo', 'Account',
                 'M', DATE '1980-01-01', DATE '2020-01-01', 500000.00,
                 'Lagos', 'Lagos State', 'NINDEMO00001')
            ON CONFLICT (employee_id) DO NOTHING
            """,
        )
    c.commit()
    c.close()
    DEMO_EMPLOYEE_ID_HOLD = -1


def cleanup_demo_rows() -> None:
    """Drop everything we created so the database is left untouched."""
    c = conn()
    with c.cursor() as cur:
        cur.execute("DELETE FROM withdrawal_claim WHERE rsa_account_id IN (%s, %s)",
                    (DEMO_RSA_1, DEMO_RSA_2))
        cur.execute("DELETE FROM rsa_account WHERE rsa_account_id IN (%s, %s)",
                    (DEMO_RSA_1, DEMO_RSA_2))
        cur.execute("DELETE FROM employee WHERE employee_id = -1")
    c.commit()
    c.close()


def fetch_balance(acct_id: int, iso: str | None = None) -> float:
    c = conn(iso)
    with c.cursor() as cur:
        cur.execute("SELECT balance FROM rsa_account WHERE rsa_account_id = %s",
                    (acct_id,))
        row = cur.fetchone()
    c.rollback()
    c.close()
    return float(row[0]) if row else 0.0


# --------------------------------------------------------------------------- #
# Thread plumbing
# --------------------------------------------------------------------------- #
@dataclass
class ThreadResult:
    label: str
    rows_affected: int = 0
    final_balance: float | None = None
    error_code: str | None = None
    error_msg: str | None = None
    log: list[str] = None


def banner(title: str) -> None:
    print()
    print("=" * 70)
    print(title)
    print("=" * 70)


def run_two_threads(target, args1, args2) -> tuple[ThreadResult, ThreadResult]:
    r1 = ThreadResult(label="T1")
    r2 = ThreadResult(label="T2")
    t1 = threading.Thread(target=target, args=(r1,) + args1)
    t2 = threading.Thread(target=target, args=(r2,) + args2)
    # Stagger by 50ms so the second thread starts while the first is mid-flight.
    t1.start()
    time.sleep(0.05)
    t2.start()
    t1.join(timeout=15)
    t2.join(timeout=15)
    return r1, r2


# --------------------------------------------------------------------------- #
# Part 1 - the bug (read-modify-write race; lost update / overdraft)
# --------------------------------------------------------------------------- #
def part1_worker(res: ThreadResult, acct_id: int, amount: float) -> None:
    res.log = []
    try:
        c = conn("READ COMMITTED")
        with c.cursor() as cur:
            cur.execute("SELECT balance FROM rsa_account WHERE rsa_account_id = %s",
                        (acct_id,))
            bal = float(cur.fetchone()[0])
            res.log.append(f"read balance={bal}")
            new_bal = bal - amount
            # Simulate app-level think time so both threads read the same value.
            time.sleep(0.2)
            cur.execute(
                "UPDATE rsa_account SET balance = %s WHERE rsa_account_id = %s",
                (new_bal, acct_id),
            )
            res.rows_affected = cur.rowcount
            res.log.append(f"wrote balance={new_bal}")
        c.commit()
        res.final_balance = new_bal
        c.close()
    except psycopg2.Error as e:
        res.error_code = e.pgcode
        res.error_msg = e.pgerror.strip().splitlines()[0] if e.pgerror else str(e)
        res.log.append(f"ERROR {e.pgcode}: {res.error_msg}")


def part1_bug() -> None:
    banner("Part 1 - the bug (read balance then UPDATE; lost update / overdraft)")
    acct = DEMO_RSA_1
    start_bal = 100_000.00
    amt = 80_000.00
    reset_demo_account(acct, start_bal)
    print(f"Start balance on account {acct}: {start_bal:,.2f}")
    print(f"Two threads each withdraw {amt:,.2f} via read-modify-write.")
    r1, r2 = run_two_threads(part1_worker, (acct, amt), (acct, amt))
    end_bal = fetch_balance(acct)
    print(f"  T1: rows={r1.rows_affected}, wrote={r1.final_balance}, "
          f"err={r1.error_code}")
    print(f"  T2: rows={r2.rows_affected}, wrote={r2.final_balance}, "
          f"err={r2.error_code}")
    print(f"End balance on account {acct}: {end_bal:,.2f}")
    total_withdrawn = (start_bal - end_bal)
    expected_withdrawn = 2 * amt
    print(f"Total balance reduction observed: {total_withdrawn:,.2f}")
    print(f"Total the two threads claimed to withdraw: {expected_withdrawn:,.2f}")
    if total_withdrawn < expected_withdrawn:
        print("BUG: balance moved by less than the sum of the two withdrawals.")
        print("     One withdrawal was lost - the PFA is short of real money.")
    elif end_bal < 0:
        print("BUG: balance went negative.")
    else:
        print("No bug visible this run - rerun if you want to see the race.")


# --------------------------------------------------------------------------- #
# Part 2 - CHECK / UNIQUE constraint fix
# --------------------------------------------------------------------------- #
def part2_worker(res: ThreadResult, acct_id: int, amount: float) -> None:
    res.log = []
    try:
        c = conn("READ COMMITTED")
        with c.cursor() as cur:
            # Atomic decrement + CHECK(balance >= 0) on the table catches it.
            cur.execute(
                "UPDATE rsa_account "
                " SET balance = balance - %s "
                " WHERE rsa_account_id = %s",
                (amount, acct_id),
            )
            res.rows_affected = cur.rowcount
        c.commit()
        res.log.append("committed")
        c.close()
    except psycopg2.Error as e:
        c.rollback()
        res.error_code = e.pgcode
        res.error_msg = str(e).strip().splitlines()[0]
        res.log.append(f"ERROR {e.pgcode}: {res.error_msg}")


def part2_check() -> None:
    banner("Part 2 - CHECK constraint fix (atomic decrement + balance >= 0)")
    acct = DEMO_RSA_1
    start_bal = 100_000.00
    amt = 80_000.00
    reset_demo_account(acct, start_bal)
    print(f"Start balance on account {acct}: {start_bal:,.2f}")
    print(f"Two threads each do UPDATE rsa_account SET balance = balance - {amt:,.2f}")
    print("Schema has CHECK (balance >= 0).")
    r1, r2 = run_two_threads(part2_worker, (acct, amt), (acct, amt))
    end_bal = fetch_balance(acct)
    print(f"  T1: rows={r1.rows_affected}, err={r1.error_code}")
    print(f"  T2: rows={r2.rows_affected}, err={r2.error_code}")
    print(f"End balance on account {acct}: {end_bal:,.2f}")
    if r1.error_code == "23514" or r2.error_code == "23514":
        print("FIX: the second UPDATE raised SQLSTATE 23514 (check_violation) "
              "because it would have pushed balance below 0.")
    else:
        print("Note: this run did not show the check_violation - the threads "
              "may have serialised too cleanly. Rerun if needed.")


# --------------------------------------------------------------------------- #
# Part 3 - atomic conditional UPDATE (the chosen P3 fix)
# --------------------------------------------------------------------------- #
def part3_worker(res: ThreadResult, acct_id: int, amount: float) -> None:
    res.log = []
    try:
        c = conn("READ COMMITTED")
        with c.cursor() as cur:
            cur.execute(
                "UPDATE rsa_account "
                " SET balance = balance - %s "
                " WHERE rsa_account_id = %s "
                "   AND balance >= %s",
                (amount, acct_id, amount),
            )
            res.rows_affected = cur.rowcount
        c.commit()
        res.log.append(f"rowcount={res.rows_affected}")
        c.close()
    except psycopg2.Error as e:
        c.rollback()
        res.error_code = e.pgcode
        res.error_msg = str(e).strip().splitlines()[0]
        res.log.append(f"ERROR {e.pgcode}: {res.error_msg}")


def part3_atomic_conditional() -> None:
    banner("Part 3 - atomic conditional UPDATE (chosen P3 fix)")
    acct = DEMO_RSA_1
    start_bal = 100_000.00
    amt = 80_000.00
    reset_demo_account(acct, start_bal)
    print(f"Start balance on account {acct}: {start_bal:,.2f}")
    print(f"Two threads each run:")
    print("    UPDATE rsa_account SET balance = balance - :amt")
    print("     WHERE rsa_account_id = :id AND balance >= :amt")
    print("  and check the row count.")
    r1, r2 = run_two_threads(part3_worker, (acct, amt), (acct, amt))
    end_bal = fetch_balance(acct)
    print(f"  T1: rows_affected={r1.rows_affected}, err={r1.error_code}")
    print(f"  T2: rows_affected={r2.rows_affected}, err={r2.error_code}")
    print(f"End balance on account {acct}: {end_bal:,.2f}")
    if r1.rows_affected == 1 and r2.rows_affected == 0:
        print("FIX: one thread got rowcount=1 (success), the other got rowcount=0 "
              "(balance already below the withdrawal amount).")
        print("     The app turns rowcount=0 into 'insufficient funds' - "
              "no overdraft, no lost money.")
    elif r2.rows_affected == 1 and r1.rows_affected == 0:
        print("FIX: T2 succeeded, T1 got rowcount=0 - same outcome, "
              "just the other thread won.")
    else:
        print(f"Note: row counts were T1={r1.rows_affected}, T2={r2.rows_affected}. "
              "Rerun if you want a cleaner winner/loser.")


# --------------------------------------------------------------------------- #
# Part 4 - SERIALIZABLE (expects SQLSTATE 40001)
# --------------------------------------------------------------------------- #
def part4_worker(res: ThreadResult, acct_id: int, amount: float) -> None:
    res.log = []
    try:
        c = conn("SERIALIZABLE")
        with c.cursor() as cur:
            cur.execute("SELECT balance FROM rsa_account WHERE rsa_account_id = %s",
                        (acct_id,))
            bal = float(cur.fetchone()[0])
            time.sleep(0.2)   # let both txns overlap their reads
            cur.execute(
                "UPDATE rsa_account SET balance = balance - %s "
                " WHERE rsa_account_id = %s",
                (amount, acct_id),
            )
            res.rows_affected = cur.rowcount
        c.commit()
        res.log.append("committed")
        c.close()
    except psycopg2.Error as e:
        try:
            c.rollback()
        except Exception:
            pass
        res.error_code = e.pgcode
        res.error_msg = str(e).strip().splitlines()[0]
        res.log.append(f"ERROR {e.pgcode}: {res.error_msg}")
        try:
            c.close()
        except Exception:
            pass


def part4_serializable() -> None:
    banner("Part 4 - SERIALIZABLE isolation (expects SQLSTATE 40001)")
    acct = DEMO_RSA_1
    start_bal = 100_000.00
    amt = 80_000.00
    reset_demo_account(acct, start_bal)
    print(f"Start balance on account {acct}: {start_bal:,.2f}")
    print("Both threads run in SERIALIZABLE isolation, each reads balance "
          "then UPDATEs.")
    print("Expected: one commits, the other aborts with SQLSTATE 40001 "
          "(serialization_failure).")
    r1, r2 = run_two_threads(part4_worker, (acct, amt), (acct, amt))
    end_bal = fetch_balance(acct)
    print(f"  T1: rows={r1.rows_affected}, err={r1.error_code}")
    print(f"  T2: rows={r2.rows_affected}, err={r2.error_code}")
    print(f"End balance on account {acct}: {end_bal:,.2f}")
    if "40001" in (r1.error_code or "", r2.error_code or ""):
        print("FIX: one transaction was aborted with SQLSTATE 40001 "
              "so the conflict could not silently corrupt the balance.")
    else:
        print("Note: this run did not surface 40001 - rerun if you want to "
              "see the abort. (The balance is still consistent because "
              "PG only commits one writer.)")


# --------------------------------------------------------------------------- #
# Part 5 - READ COMMITTED vs REPEATABLE READ
# --------------------------------------------------------------------------- #
def part5() -> None:
    banner("Part 5 - READ COMMITTED vs REPEATABLE READ (visibility)")
    acct = DEMO_RSA_1
    reset_demo_account(acct, 100_000.00)
    print("A long-running transaction T1 reads balance twice with a gap in "
          "between.")
    print("A second transaction T2 commits a write between the two reads.")
    print("Under READ COMMITTED, T1's two reads return DIFFERENT values.")
    print("Under REPEATABLE READ, T1's two reads return the SAME value "
          "(snapshot frozen at first statement).")

    def reader(iso: str, out: list) -> None:
        c = conn(iso)
        with c.cursor() as cur:
            cur.execute("SELECT balance FROM rsa_account WHERE rsa_account_id = %s",
                        (acct,))
            out.append(("first_read", iso, float(cur.fetchone()[0])))
            time.sleep(0.5)   # let T2 commit in between
            cur.execute("SELECT balance FROM rsa_account WHERE rsa_account_id = %s",
                        (acct,))
            out.append(("second_read", iso, float(cur.fetchone()[0])))
        c.rollback()
        c.close()

    rc_seen: list = []
    rr_seen: list = []
    trc = threading.Thread(target=reader, args=("READ COMMITTED", rc_seen))
    trr = threading.Thread(target=reader, args=("REPEATABLE READ", rr_seen))
    trc.start()
    trr.start()
    time.sleep(0.2)

    # T2: bump the balance by +50,000 in its own committed transaction.
    c2 = conn("READ COMMITTED")
    with c2.cursor() as cur:
        cur.execute(
            "UPDATE rsa_account SET balance = balance + %s WHERE rsa_account_id = %s",
            (50_000.00, acct),
        )
    c2.commit()
    c2.close()

    trc.join(timeout=10)
    trr.join(timeout=10)

    rc_first = next(v for k, _, v in rc_seen if k == "first_read")
    rc_second = next(v for k, _, v in rc_seen if k == "second_read")
    rr_first = next(v for k, _, v in rr_seen if k == "first_read")
    rr_second = next(v for k, _, v in rr_seen if k == "second_read")

    print(f"  READ COMMITTED : first={rc_first:,.2f}  second={rc_second:,.2f}  "
          f"-> {'DIFFERENT' if rc_first != rc_second else 'SAME'}")
    print(f"  REPEATABLE READ: first={rr_first:,.2f}  second={rr_second:,.2f}  "
          f"-> {'DIFFERENT' if rr_first != rr_second else 'SAME'}")


# --------------------------------------------------------------------------- #
# Part 6 - deadlock (40P01) plus fixed-order version
# --------------------------------------------------------------------------- #
def part6_deadlock_worker(res: ThreadResult, first: int, second: int,
                          amount: float) -> None:
    res.log = []
    try:
        c = conn("READ COMMITTED")
        with c.cursor() as cur:
            cur.execute(
                "UPDATE rsa_account SET balance = balance - %s "
                " WHERE rsa_account_id = %s",
                (amount, first),
            )
            time.sleep(0.3)
            cur.execute(
                "UPDATE rsa_account SET balance = balance - %s "
                " WHERE rsa_account_id = %s",
                (amount, second),
            )
        c.commit()
        res.log.append("committed")
        c.close()
    except psycopg2.Error as e:
        try:
            c.rollback()
        except Exception:
            pass
        res.error_code = e.pgcode
        res.error_msg = str(e).strip().splitlines()[0]
        res.log.append(f"ERROR {e.pgcode}: {res.error_msg}")
        try:
            c.close()
        except Exception:
            pass


def part6() -> None:
    banner("Part 6 - deadlock (SQLSTATE 40P01) plus fixed-order version")
    a = DEMO_RSA_1
    b = DEMO_RSA_2
    reset_demo_account(a, 1_000_000.00)
    reset_demo_account(b, 1_000_000.00)

    print("--- 6a. PRONE order: T1 locks A then B; T2 locks B then A ---")
    r1, r2 = run_two_threads(
        part6_deadlock_worker,
        (a, b, 1_000.00),       # T1: A -> B
        (b, a, 1_000.00),       # T2: B -> A
    )
    print(f"  T1: err={r1.error_code} ({r1.error_msg})")
    print(f"  T2: err={r2.error_code} ({r2.error_msg})")
    if "40P01" in (r1.error_code or "", r2.error_code or ""):
        print("  DEADLOCK: one transaction was aborted with SQLSTATE 40P01.")
    else:
        print("  Note: deadlock did not surface this run - rerun to see 40P01.")

    print()
    print("--- 6b. FIXED order: both threads lock A first, then B ---")
    reset_demo_account(a, 1_000_000.00)
    reset_demo_account(b, 1_000_000.00)
    r1, r2 = run_two_threads(
        part6_deadlock_worker,
        (a, b, 1_000.00),       # T1: A -> B
        (a, b, 1_000.00),       # T2: A -> B (same order!)
    )
    print(f"  T1: err={r1.error_code} ({r1.error_msg})")
    print(f"  T2: err={r2.error_code} ({r2.error_msg})")
    if not r1.error_code and not r2.error_code:
        print("  NO DEADLOCK: both transactions committed because they "
              "acquired locks in the same order.")
    else:
        print("  Note: an error occurred, but not a deadlock - "
              f"T1={r1.error_code}, T2={r2.error_code}.")


# --------------------------------------------------------------------------- #
# main
# --------------------------------------------------------------------------- #
def main() -> int:
    try:
        ensure_demo_employee()
        part1_bug()
        part2_check()
        part3_atomic_conditional()
        part4_serializable()
        part5()
        part6()
    finally:
        cleanup_demo_rows()
        print()
        print("Cleanup: demo rows deleted. Database left as it was found.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
