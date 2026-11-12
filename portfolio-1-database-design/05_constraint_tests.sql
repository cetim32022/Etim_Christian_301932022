-- 05_constraint_tests.sql
-- Constraint and trigger tests for the pensions schema.
-- 10 tests that MUST FAIL on the intended constraint, plus 1 control test
-- that MUST SUCCEED. Every test runs inside BEGIN ... ROLLBACK so it leaves
-- the database exactly as it found it.
--
-- Each test prints PASS / FAIL with RAISE NOTICE so a human can read the
-- output. Tests catch only the SQLSTATE class they are meant to trigger,
-- so an unexpected error is still surfaced.
--
-- Run with:   psql -d pensions -v ON_ERROR_STOP=1 -f 05_constraint_tests.sql
-- Requires:   01_schema.sql, 02_indexes.sql, 03_seed_data.sql, 04_bulk_data.sql already loaded.

\set ON_ERROR_STOP on
SET client_min_messages = notice;
SET timezone = 'Africa/Lagos';

\echo ''
\echo '=== Constraint tests (10 expected failures + 1 control success) ==='
\echo ''

-- =========================================================
-- TEST 1  - PK violation on employer
-- =========================================================
BEGIN;
DO $$
BEGIN
    INSERT INTO employer (employer_id, employer_code, name, sector, city, state, monthly_contribution_day)
    VALUES (1, 'XX-DUP', 'Duplicate PK Test', 'Manufacturing', 'Lagos', 'Lagos State', 15);
    RAISE NOTICE 'TEST 1 (employer PK): FAIL - insert unexpectedly succeeded';
EXCEPTION
    WHEN unique_violation THEN
        RAISE NOTICE 'TEST 1 (employer PK): PASS - unique_violation caught';
END
$$;
ROLLBACK;

-- =========================================================
-- TEST 2  - UNIQUE violation on employer.employer_code
-- =========================================================
BEGIN;
DO $$
BEGIN
    INSERT INTO employer (employer_code, name, sector, city, state, monthly_contribution_day)
    VALUES ('LHP-EMP01', 'Duplicate code Test', 'Manufacturing', 'Lagos', 'Lagos State', 15);
    RAISE NOTICE 'TEST 2 (employer_code UNIQUE): FAIL - insert unexpectedly succeeded';
EXCEPTION
    WHEN unique_violation THEN
        RAISE NOTICE 'TEST 2 (employer_code UNIQUE): PASS - unique_violation caught';
END
$$;
ROLLBACK;

-- =========================================================
-- TEST 3  - FK violation: employee with non-existent employer_id
-- =========================================================
BEGIN;
DO $$
BEGIN
    INSERT INTO employee (employer_id, staff_no, first_name, last_name, gender,
        date_of_birth, hire_date, monthly_salary, city, state, nin)
    VALUES (999999, 'FK-001', 'Test', 'User', 'M',
        DATE '1990-01-01', DATE '2020-01-01', 200000.00, 'Lagos', 'Lagos State', 'NINFK001');
    RAISE NOTICE 'TEST 3 (employee FK): FAIL - insert unexpectedly succeeded';
EXCEPTION
    WHEN foreign_key_violation THEN
        RAISE NOTICE 'TEST 3 (employee FK): PASS - foreign_key_violation caught';
END
$$;
ROLLBACK;

-- =========================================================
-- TEST 4  - CHECK violation: monthly_salary <= 0
-- =========================================================
BEGIN;
DO $$
BEGIN
    INSERT INTO employee (employer_id, staff_no, first_name, last_name, gender,
        date_of_birth, hire_date, monthly_salary, city, state, nin)
    VALUES (1, 'CHK-001', 'Test', 'User', 'M',
        DATE '1990-01-01', DATE '2020-01-01', 0, 'Lagos', 'Lagos State', 'NINCHK001');
    RAISE NOTICE 'TEST 4 (salary CHECK): FAIL - insert unexpectedly succeeded';
EXCEPTION
    WHEN check_violation THEN
        RAISE NOTICE 'TEST 4 (salary CHECK): PASS - check_violation caught';
END
$$;
ROLLBACK;

-- =========================================================
-- TEST 5  - Trigger check_contribution_minimum: employer_share < 10%
-- =========================================================
BEGIN;
DO $$
DECLARE
    target_emp BIGINT;
    target_acct BIGINT;
BEGIN
    -- Find a bulk employee with salary >> statutory minimum so the only
    -- thing failing is the deliberately low employer_share.
    SELECT e.employee_id INTO target_emp
      FROM employee e WHERE e.employee_id = 1 LIMIT 1;
    SELECT rsa_account_id INTO target_acct
      FROM rsa_account WHERE employee_id = target_emp LIMIT 1;

    INSERT INTO contribution (
        rsa_account_id, employer_id, employee_id, custodian_id, fund_id,
        contribution_month, gross_salary, employer_share, employee_share, units_credited
    )
    VALUES (
        target_acct, 1, target_emp, 1, 1,
        (date_trunc('month', CURRENT_DATE) + INTERVAL '4 months')::DATE,
        850000.00,
        5000.00,   -- way below 10% of 850000 = 85000
        68000.00,  -- exactly 8%
        0
    );
    RAISE NOTICE 'TEST 5 (contribution minimum trigger): FAIL - insert unexpectedly succeeded';
EXCEPTION
    WHEN check_violation THEN
        RAISE NOTICE 'TEST 5 (contribution minimum trigger): PASS - check_violation caught';
END
$$;
ROLLBACK;

-- =========================================================
-- TEST 6  - Trigger check_withdrawal_balance: amount > balance
-- =========================================================
BEGIN;
DO $$
DECLARE
    target_acct BIGINT;
BEGIN
    SELECT rsa_account_id INTO target_acct
      FROM rsa_account WHERE rsa_account_id = 1;

    INSERT INTO withdrawal_claim (rsa_account_id, claim_type, amount, status, is_early_flag)
    VALUES (target_acct, 'EARLY', 999999999.00, 'OPEN', TRUE);

    RAISE NOTICE 'TEST 6 (withdrawal balance trigger): FAIL - insert unexpectedly succeeded';
EXCEPTION
    WHEN check_violation THEN
        RAISE NOTICE 'TEST 6 (withdrawal balance trigger): PASS - check_violation caught';
END
$$;
ROLLBACK;

-- =========================================================
-- TEST 7  - Trigger check_retirement_age: RETIREMENT claim for under-50 holder
--           without is_early_flag.
-- =========================================================
BEGIN;
DO $$
DECLARE
    young_acct BIGINT;
BEGIN
    -- Pick an RSA account whose holder is below 50.
    SELECT a.rsa_account_id INTO young_acct
      FROM rsa_account a
      JOIN employee e ON e.employee_id = a.employee_id
     WHERE e.date_of_birth > (CURRENT_DATE - INTERVAL '50 years')::DATE
       AND a.balance >= 1000
     ORDER BY a.rsa_account_id
     LIMIT 1;

    INSERT INTO withdrawal_claim (rsa_account_id, claim_type, amount, status, is_early_flag)
    VALUES (young_acct, 'RETIREMENT', 500.00, 'OPEN', FALSE);

    RAISE NOTICE 'TEST 7 (retirement age trigger): FAIL - insert unexpectedly succeeded';
EXCEPTION
    WHEN check_violation THEN
        RAISE NOTICE 'TEST 7 (retirement age trigger): PASS - check_violation caught';
END
$$;
ROLLBACK;

-- =========================================================
-- TEST 8  - Partial UNIQUE index: two OPEN claims on the same RSA account
-- =========================================================
BEGIN;
DO $$
DECLARE
    target_acct BIGINT;
BEGIN
    SELECT rsa_account_id INTO target_acct
      FROM rsa_account WHERE rsa_account_id = 5;

    -- Pick an account that has NO open claim yet (id 5 is in bulk range with balance > 0).
    INSERT INTO withdrawal_claim (rsa_account_id, claim_type, amount, status, is_early_flag)
    VALUES (target_acct, 'EARLY', 500.00, 'OPEN', TRUE);

    INSERT INTO withdrawal_claim (rsa_account_id, claim_type, amount, status, is_early_flag)
    VALUES (target_acct, 'EARLY', 500.00, 'OPEN', TRUE);

    RAISE NOTICE 'TEST 8 (one_open_claim_per_rsa): FAIL - second OPEN insert unexpectedly succeeded';
EXCEPTION
    WHEN unique_violation THEN
        RAISE NOTICE 'TEST 8 (one_open_claim_per_rsa): PASS - unique_violation caught';
END
$$;
ROLLBACK;

-- =========================================================
-- TEST 9  - CHECK violation on beneficiary.share_pct: must be <= 100
-- =========================================================
BEGIN;
DO $$
BEGIN
    INSERT INTO beneficiary (rsa_account_id, full_name, relationship, share_pct)
    VALUES (3, 'Test Beneficiary', 'Sibling', 150.00);
    RAISE NOTICE 'TEST 9 (beneficiary share_pct CHECK): FAIL - insert unexpectedly succeeded';
EXCEPTION
    WHEN check_violation THEN
        RAISE NOTICE 'TEST 9 (beneficiary share_pct CHECK): PASS - check_violation caught';
END
$$;
ROLLBACK;

-- =========================================================
-- TEST 10 - Trigger check_beneficiary_share: total > 100%
--           Account 1 already has 60% + 40% = 100% from seed data,
--           so any extra beneficiary must fail.
-- =========================================================
BEGIN;
DO $$
BEGIN
    INSERT INTO beneficiary (rsa_account_id, full_name, relationship, share_pct)
    VALUES (1, 'Extra Beneficiary', 'Cousin', 10.00);
    RAISE NOTICE 'TEST 10 (beneficiary total share trigger): FAIL - insert unexpectedly succeeded';
EXCEPTION
    WHEN check_violation THEN
        RAISE NOTICE 'TEST 10 (beneficiary total share trigger): PASS - check_violation caught';
END
$$;
ROLLBACK;

-- =========================================================
-- CONTROL TEST - must SUCCEED. Uses a fresh bulk account,
-- fully valid contribution row, no rules broken.
-- Wrapped in BEGIN/ROLLBACK so it still leaves the DB clean.
-- =========================================================
BEGIN;
DO $$
DECLARE
    v_emp BIGINT;
    v_acct BIGINT;
    v_fund BIGINT;
    v_count INT;
BEGIN
    SELECT employee_id INTO v_emp FROM employee WHERE employee_id = 4;     -- Bolanle Okafor, FBN
    SELECT rsa_account_id, fund_id INTO v_acct, v_fund
      FROM rsa_account WHERE employee_id = v_emp LIMIT 1;

    INSERT INTO contribution (
        rsa_account_id, employer_id, employee_id, custodian_id, fund_id,
        contribution_month, gross_salary, employer_share, employee_share,
        units_credited
    )
    VALUES (
        v_acct, 2, v_emp, 1, v_fund,
        (date_trunc('month', CURRENT_DATE) + INTERVAL '6 months')::DATE,
        980000.00,
        ROUND(980000.00 * 0.10, 2),    -- 98,000 - meets 10% minimum
        ROUND(980000.00 * 0.08, 2),    -- 78,400 - meets 8% minimum
        100.0000
    );

    GET DIAGNOSTICS v_count = ROW_COUNT;
    IF v_count = 1 THEN
        RAISE NOTICE 'CONTROL TEST (valid contribution): PASS - inserted 1 row as expected';
    ELSE
        RAISE NOTICE 'CONTROL TEST (valid contribution): FAIL - unexpected row count %', v_count;
    END IF;
EXCEPTION
    WHEN OTHERS THEN
        RAISE NOTICE 'CONTROL TEST (valid contribution): FAIL - %', SQLERRM;
END
$$;
ROLLBACK;

\echo ''
\echo '=== End of constraint tests ==='
