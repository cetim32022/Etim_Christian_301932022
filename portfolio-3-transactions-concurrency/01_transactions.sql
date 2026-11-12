-- 01_transactions.sql
-- Three small, self-contained transaction demos for the pensions database:
--
--   (A) A committed contribution posting - the row survives.
--   (B) A rolled-back contribution posting   - the row does not survive.
--   (C) A SAVEPOINT recovery inside a batch of employer contributions:
--       one deliberately bad row is skipped, the rest commit.
--
-- Each block prints a short label and a verification count so a human can
-- read the result off the psql output.
--
-- Run with:   psql -d pensions -v ON_ERROR_STOP=1 -f 01_transactions.sql
-- Requires:   P1 schema + seed + bulk data already loaded.

\set ON_ERROR_STOP on
SET timezone = 'Africa/Lagos';

-- Re-run safety: remove the demo rows a previous run committed (months +7 and
-- +9 ahead) and take their amounts back out of the RSA balances.
WITH d AS (
    DELETE FROM contribution
     WHERE contribution_month IN (
             (date_trunc('month', CURRENT_DATE) + make_interval(months => 7))::DATE,
             (date_trunc('month', CURRENT_DATE) + make_interval(months => 9))::DATE)
    RETURNING rsa_account_id, total_amount
)
UPDATE rsa_account a SET balance = a.balance - s.t
  FROM (SELECT rsa_account_id, sum(total_amount) AS t FROM d GROUP BY 1) s
 WHERE a.rsa_account_id = s.rsa_account_id;

\echo '========================================================'
\echo '(A) COMMITTED contribution posting'
\echo '========================================================'

-- Find an unused (rsa_account_id, contribution_month) pair so we do not
-- trip the UNIQUE constraint by accident.
WITH pick AS (
    SELECT ra.rsa_account_id, ra.fund_id, e.employee_id, e.employer_id,
           ra.custodian_id, e.monthly_salary
      FROM rsa_account ra
      JOIN employee e ON e.employee_id = ra.employee_id
     WHERE ra.rsa_account_id = 4
     LIMIT 1
),
target_month AS (
    SELECT (date_trunc('month', CURRENT_DATE) + make_interval(months => 7))::DATE AS m
)
INSERT INTO contribution (
    rsa_account_id, employer_id, employee_id, custodian_id, fund_id,
    contribution_month, gross_salary, employer_share, employee_share,
    units_credited, posted_at
)
SELECT
    p.rsa_account_id, p.employer_id, p.employee_id, p.custodian_id, p.fund_id,
    tm.m, p.monthly_salary,
    ROUND(p.monthly_salary * 0.10, 2),
    ROUND(p.monthly_salary * 0.08, 2),
    100.0000,
    now()
FROM pick p, target_month tm;

\echo 'Committed. Verification count (should be 1):'
SELECT count(*) AS committed_rows
  FROM contribution
 WHERE rsa_account_id = 4
   AND contribution_month = (date_trunc('month', CURRENT_DATE)
                             + make_interval(months => 7))::DATE;

\echo ''
\echo '========================================================'
\echo '(B) ROLLED-BACK contribution posting'
\echo '========================================================'

BEGIN;
    WITH pick AS (
        SELECT ra.rsa_account_id, ra.fund_id, e.employee_id, e.employer_id,
               ra.custodian_id, e.monthly_salary
          FROM rsa_account ra
          JOIN employee e ON e.employee_id = ra.employee_id
         WHERE ra.rsa_account_id = 5
         LIMIT 1
    ),
    target_month AS (
        SELECT (date_trunc('month', CURRENT_DATE) + make_interval(months => 8))::DATE AS m
    )
    INSERT INTO contribution (
        rsa_account_id, employer_id, employee_id, custodian_id, fund_id,
        contribution_month, gross_salary, employer_share, employee_share,
        units_credited, posted_at
    )
    SELECT
        p.rsa_account_id, p.employer_id, p.employee_id, p.custodian_id, p.fund_id,
        tm.m, p.monthly_salary,
        ROUND(p.monthly_salary * 0.10, 2),
        ROUND(p.monthly_salary * 0.08, 2),
        100.0000,
        now()
    FROM pick p, target_month tm;
ROLLBACK;

\echo 'Rolled back. Verification count (should be 0):'
SELECT count(*) AS rolled_back_rows
  FROM contribution
 WHERE rsa_account_id = 5
   AND contribution_month = (date_trunc('month', CURRENT_DATE)
                             + make_interval(months => 8))::DATE;

\echo ''
\echo '========================================================'
\echo '(C) SAVEPOINT recovery in a batch of employer contributions'
\echo '========================================================'
\echo 'A batch of 3 rows is attempted. Row 2 deliberately violates the'
\echo 'statutory minimum trigger (employer_share below 10%).'
\echo 'We SAVEPOINT, skip the bad row, and COMMIT the other two.'

DO $$
DECLARE
    v_employer_id CONSTANT BIGINT := 6;       -- Lagos State Government
    v_months_ahead CONSTANT INT := 9;
    v_acct_1 BIGINT;
    v_acct_2 BIGINT;
    v_acct_3 BIGINT;
    v_emp_1 BIGINT;
    v_emp_2 BIGINT;
    v_emp_3 BIGINT;
    v_fund_1 BIGINT;
    v_fund_2 BIGINT;
    v_fund_3 BIGINT;
    v_cust_1 BIGINT;
    v_cust_2 BIGINT;
    v_cust_3 BIGINT;
    v_sal_1 NUMERIC(12,2);
    v_sal_2 NUMERIC(12,2);
    v_sal_3 NUMERIC(12,2);
    v_month DATE;
    v_good INT := 0;
    v_bad  INT := 0;
BEGIN
    -- Collect 3 different accounts under the chosen employer.
    SELECT ra.rsa_account_id, ra.fund_id, ra.custodian_id, e.employee_id, e.monthly_salary
      INTO v_acct_1, v_fund_1, v_cust_1, v_emp_1, v_sal_1
      FROM rsa_account ra
      JOIN employee e ON e.employee_id = ra.employee_id
     WHERE e.employer_id = v_employer_id
     ORDER BY ra.rsa_account_id
     LIMIT 1 OFFSET 0;

    SELECT ra.rsa_account_id, ra.fund_id, ra.custodian_id, e.employee_id, e.monthly_salary
      INTO v_acct_2, v_fund_2, v_cust_2, v_emp_2, v_sal_2
      FROM rsa_account ra
      JOIN employee e ON e.employee_id = ra.employee_id
     WHERE e.employer_id = v_employer_id
     ORDER BY ra.rsa_account_id
     LIMIT 1 OFFSET 1;

    SELECT ra.rsa_account_id, ra.fund_id, ra.custodian_id, e.employee_id, e.monthly_salary
      INTO v_acct_3, v_fund_3, v_cust_3, v_emp_3, v_sal_3
      FROM rsa_account ra
      JOIN employee e ON e.employee_id = ra.employee_id
     WHERE e.employer_id = v_employer_id
     ORDER BY ra.rsa_account_id
     LIMIT 1 OFFSET 2;

    v_month := (date_trunc('month', CURRENT_DATE)
                + make_interval(months => v_months_ahead))::DATE;

    BEGIN
        -- Row 1: good.
        INSERT INTO contribution (
            rsa_account_id, employer_id, employee_id, custodian_id, fund_id,
            contribution_month, gross_salary, employer_share, employee_share,
            units_credited
        )
        VALUES (
            v_acct_1, v_employer_id, v_emp_1, v_cust_1, v_fund_1,
            v_month, v_sal_1,
            ROUND(v_sal_1 * 0.10, 2),
            ROUND(v_sal_1 * 0.08, 2),
            100.0000
        );
        v_good := v_good + 1;
    EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE 'Row 1 unexpectedly failed: %', SQLERRM;
    END;


    BEGIN
        -- Row 2: BAD - employer_share deliberately below 10%.
        INSERT INTO contribution (
            rsa_account_id, employer_id, employee_id, custodian_id, fund_id,
            contribution_month, gross_salary, employer_share, employee_share,
            units_credited
        )
        VALUES (
            v_acct_2, v_employer_id, v_emp_2, v_cust_2, v_fund_2,
            v_month, v_sal_2,
            1000.00,                                -- way below 10% of any salary here
            ROUND(v_sal_2 * 0.08, 2),
            100.0000
        );
        v_good := v_good + 1;
    EXCEPTION WHEN check_violation THEN
        v_bad := v_bad + 1;
        RAISE NOTICE 'Row 2 skipped (statutory minimum trigger fired): %', SQLERRM;
    END;

    BEGIN
        -- Row 3: good.
        INSERT INTO contribution (
            rsa_account_id, employer_id, employee_id, custodian_id, fund_id,
            contribution_month, gross_salary, employer_share, employee_share,
            units_credited
        )
        VALUES (
            v_acct_3, v_employer_id, v_emp_3, v_cust_3, v_fund_3,
            v_month, v_sal_3,
            ROUND(v_sal_3 * 0.10, 2),
            ROUND(v_sal_3 * 0.08, 2),
            100.0000
        );
        v_good := v_good + 1;
    EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE 'Row 3 unexpectedly failed: %', SQLERRM;
    END;

    RAISE NOTICE 'Batch summary: good=%, bad=%', v_good, v_bad;
END
$$;

\echo ''
\echo 'Committed. Verification count (should be 2):'
SELECT count(*) AS good_rows
  FROM contribution
 WHERE employer_id = 6
   AND contribution_month = (date_trunc('month', CURRENT_DATE)
                             + make_interval(months => 9))::DATE;

\echo ''
\echo '=== End of 01_transactions.sql ==='
