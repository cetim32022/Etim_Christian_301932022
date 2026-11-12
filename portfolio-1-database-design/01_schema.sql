-- 01_schema.sql
-- Lagos Heritage Pensions Ltd (Nigerian PFA) - full relational schema for the
-- "pensions" database. Creates 10 tables in 3NF plus 5 triggers that enforce
-- business rules: statutory minimum contribution (employer 10% / employee 8%),
-- withdrawal cannot exceed RSA balance, retirement-age claim requires age >= 50
-- unless flagged early, RSA balance updated from contribution ledger rows, and
-- total beneficiary share per RSA cannot exceed 100%.
--
-- Run with:   psql -d pensions -v ON_ERROR_STOP=1 -f 01_schema.sql
-- Idempotent: drops existing objects in dependency order before recreating.

\set ON_ERROR_STOP on
SET client_min_messages = warning;

-- Database time zone for all reporting / default now() calls.
ALTER DATABASE pensions SET timezone = 'Africa/Lagos';
SET timezone = 'Africa/Lagos';

-- =========================================================
-- Drop in dependency order
-- =========================================================
DROP TABLE IF EXISTS beneficiary        CASCADE;
DROP TABLE IF EXISTS fund_switch        CASCADE;
DROP TABLE IF EXISTS withdrawal_claim   CASCADE;
DROP TABLE IF EXISTS contribution       CASCADE;
DROP TABLE IF EXISTS fund_price         CASCADE;
DROP TABLE IF EXISTS rsa_account        CASCADE;
DROP TABLE IF EXISTS employee           CASCADE;
DROP TABLE IF EXISTS custodian          CASCADE;
DROP TABLE IF EXISTS pension_fund       CASCADE;
DROP TABLE IF EXISTS employer           CASCADE;

DROP FUNCTION IF EXISTS check_contribution_minimum()        CASCADE;
DROP FUNCTION IF EXISTS check_withdrawal_balance()          CASCADE;
DROP FUNCTION IF EXISTS check_retirement_age()              CASCADE;
DROP FUNCTION IF EXISTS update_balance_on_contribution_stmt() CASCADE;
DROP FUNCTION IF EXISTS update_balance_on_withdrawal()      CASCADE;
DROP FUNCTION IF EXISTS check_beneficiary_share()           CASCADE;

-- =========================================================
-- 1. employer
-- =========================================================
CREATE TABLE employer (
    employer_id              BIGSERIAL    PRIMARY KEY,
    employer_code            VARCHAR(20)  NOT NULL UNIQUE,
    name                     VARCHAR(200) NOT NULL,
    sector                   VARCHAR(60)  NOT NULL,
    city                     VARCHAR(80)  NOT NULL,
    state                    VARCHAR(60)  NOT NULL,
    contact_email            VARCHAR(160),
    monthly_contribution_day SMALLINT     NOT NULL
        CHECK (monthly_contribution_day BETWEEN 1 AND 28),
    created_at               TIMESTAMPTZ  NOT NULL DEFAULT now()
);

-- =========================================================
-- 2. pension_fund  (RSA Fund I, II, III, IV)
-- =========================================================
CREATE TABLE pension_fund (
    fund_id       BIGINT       PRIMARY KEY,
    fund_code     VARCHAR(10)  NOT NULL UNIQUE,
    fund_name     VARCHAR(120) NOT NULL,
    risk_profile  VARCHAR(30)  NOT NULL,
    suggested_min_age SMALLINT,
    created_at    TIMESTAMPTZ  NOT NULL DEFAULT now(),
    CHECK (risk_profile IN ('CONSERVATIVE','MODERATE','BALANCED','AGGRESSIVE'))
);

-- =========================================================
-- 3. custodian  (Pension Fund Custodian)
-- =========================================================
CREATE TABLE custodian (
    custodian_id BIGSERIAL    PRIMARY KEY,
    name         VARCHAR(200) NOT NULL,
    license_no   VARCHAR(40)  NOT NULL UNIQUE,
    city         VARCHAR(80)  NOT NULL,
    created_at   TIMESTAMPTZ  NOT NULL DEFAULT now()
);

-- =========================================================
-- 4. employee  (RSA holder)
-- =========================================================
CREATE TABLE employee (
    employee_id     BIGSERIAL    PRIMARY KEY,
    employer_id     BIGINT       NOT NULL REFERENCES employer(employer_id),
    staff_no        VARCHAR(40)  NOT NULL,
    first_name      VARCHAR(80)  NOT NULL,
    last_name       VARCHAR(80)  NOT NULL,
    gender          CHAR(1)      NOT NULL CHECK (gender IN ('M','F')),
    date_of_birth   DATE         NOT NULL,
    hire_date       DATE         NOT NULL,
    monthly_salary  NUMERIC(12,2) NOT NULL CHECK (monthly_salary > 0),
    city            VARCHAR(80)  NOT NULL,
    state           VARCHAR(60)  NOT NULL,
    nin             VARCHAR(20)  UNIQUE,
    created_at      TIMESTAMPTZ  NOT NULL DEFAULT now(),
    UNIQUE (employer_id, staff_no)
);

-- =========================================================
-- 5. rsa_account  (Retirement Savings Account)
-- Balance is NOT typed in by the user - it is maintained by triggers
-- from the contribution and withdrawal_claim ledger rows.
-- =========================================================
CREATE TABLE rsa_account (
    rsa_account_id BIGSERIAL     PRIMARY KEY,
    rsa_number     VARCHAR(20)   NOT NULL UNIQUE,
    employee_id    BIGINT        NOT NULL REFERENCES employee(employee_id),
    fund_id        BIGINT        NOT NULL REFERENCES pension_fund(fund_id),
    custodian_id   BIGINT        NOT NULL REFERENCES custodian(custodian_id),
    balance        NUMERIC(14,2) NOT NULL DEFAULT 0
        CHECK (balance >= 0),
    status         VARCHAR(20)   NOT NULL DEFAULT 'ACTIVE'
        CHECK (status IN ('ACTIVE','FROZEN','CLOSED')),
    opened_at      TIMESTAMPTZ   NOT NULL DEFAULT now(),
    updated_at     TIMESTAMPTZ   NOT NULL DEFAULT now()
);

-- =========================================================
-- 6. fund_price  (daily unit price per fund)
-- =========================================================
CREATE TABLE fund_price (
    fund_id      BIGINT        NOT NULL REFERENCES pension_fund(fund_id),
    price_date   DATE          NOT NULL,
    unit_price   NUMERIC(10,4) NOT NULL CHECK (unit_price > 0),
    recorded_at  TIMESTAMPTZ   NOT NULL DEFAULT now(),
    PRIMARY KEY (fund_id, price_date)
);

-- =========================================================
-- 7. contribution  (BIG table - the one we partition in P5 and bulk-load in P1)
-- =========================================================
CREATE TABLE contribution (
    contribution_id    BIGSERIAL     PRIMARY KEY,
    rsa_account_id     BIGINT        NOT NULL REFERENCES rsa_account(rsa_account_id),
    employer_id        BIGINT        NOT NULL REFERENCES employer(employer_id),
    employee_id        BIGINT        NOT NULL REFERENCES employee(employee_id),
    custodian_id       BIGINT        NOT NULL REFERENCES custodian(custodian_id),
    fund_id            BIGINT        NOT NULL REFERENCES pension_fund(fund_id),
    contribution_month DATE          NOT NULL,
    gross_salary       NUMERIC(12,2) NOT NULL CHECK (gross_salary > 0),
    employer_share     NUMERIC(12,2) NOT NULL CHECK (employer_share >= 0),
    employee_share     NUMERIC(12,2) NOT NULL CHECK (employee_share >= 0),
    total_amount       NUMERIC(12,2)
        GENERATED ALWAYS AS (employer_share + employee_share) STORED,
    units_credited     NUMERIC(14,4) NOT NULL DEFAULT 0
        CHECK (units_credited >= 0),
    posted_at          TIMESTAMPTZ   NOT NULL DEFAULT now(),
    UNIQUE (rsa_account_id, contribution_month)
);

-- =========================================================
-- 8. withdrawal_claim  (retirement / early / involuntary / death)
-- =========================================================
CREATE TABLE withdrawal_claim (
    claim_id       BIGSERIAL     PRIMARY KEY,
    rsa_account_id BIGINT        NOT NULL REFERENCES rsa_account(rsa_account_id),
    claim_type     VARCHAR(20)   NOT NULL
        CHECK (claim_type IN ('RETIREMENT','EARLY','INVOLUNTARY','DEATH')),
    amount         NUMERIC(14,2) NOT NULL CHECK (amount > 0),
    status         VARCHAR(20)   NOT NULL DEFAULT 'OPEN'
        CHECK (status IN ('OPEN','APPROVED','REJECTED','PAID')),
    is_early_flag  BOOLEAN       NOT NULL DEFAULT FALSE,
    requested_at   TIMESTAMPTZ   NOT NULL DEFAULT now(),
    decided_at     TIMESTAMPTZ,
    paid_at        TIMESTAMPTZ
);

-- =========================================================
-- 9. fund_switch  (member moves balance between RSA Funds)
-- =========================================================
CREATE TABLE fund_switch (
    switch_id     BIGSERIAL   PRIMARY KEY,
    rsa_account_id BIGINT     NOT NULL REFERENCES rsa_account(rsa_account_id),
    from_fund_id  BIGINT      NOT NULL REFERENCES pension_fund(fund_id),
    to_fund_id    BIGINT      NOT NULL REFERENCES pension_fund(fund_id),
    switched_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
    CHECK (from_fund_id <> to_fund_id)
);

-- =========================================================
-- 10. beneficiary  (nominee of an RSA holder)
-- =========================================================
CREATE TABLE beneficiary (
    beneficiary_id BIGSERIAL     PRIMARY KEY,
    rsa_account_id BIGINT        NOT NULL REFERENCES rsa_account(rsa_account_id),
    full_name      VARCHAR(160)  NOT NULL,
    relationship    VARCHAR(40)  NOT NULL,
    share_pct      NUMERIC(5,2)  NOT NULL
        CHECK (share_pct > 0 AND share_pct <= 100),
    created_at     TIMESTAMPTZ   NOT NULL DEFAULT now()
);

-- =========================================================
-- TRIGGERS (business rules that cannot live inside CHECK
-- because they read other tables or compare to CURRENT_DATE)
-- =========================================================

-- (a) Statutory minimum: employer 10%, employee 8% of monthly salary.
CREATE OR REPLACE FUNCTION check_contribution_minimum()
RETURNS TRIGGER AS $$
DECLARE
    emp_salary NUMERIC(12,2);
    min_employer NUMERIC(12,2);
    min_employee NUMERIC(12,2);
BEGIN
    SELECT monthly_salary INTO emp_salary
      FROM employee
     WHERE employee_id = NEW.employee_id;
    IF emp_salary IS NULL THEN
        RAISE EXCEPTION 'Employee % not found for contribution', NEW.employee_id;
    END IF;
    min_employer  := ROUND(emp_salary * 0.10, 2);
    min_employee  := ROUND(emp_salary * 0.08, 2);
    IF NEW.employer_share < min_employer THEN
        RAISE EXCEPTION 'Employer share % below statutory minimum % (10%% of salary %)',
            NEW.employer_share, min_employer, emp_salary
            USING ERRCODE = 'check_violation';
    END IF;
    IF NEW.employee_share < min_employee THEN
        RAISE EXCEPTION 'Employee share % below statutory minimum % (8%% of salary %)',
            NEW.employee_share, min_employee, emp_salary
            USING ERRCODE = 'check_violation';
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_contribution_minimum
BEFORE INSERT OR UPDATE ON contribution
FOR EACH ROW EXECUTE FUNCTION check_contribution_minimum();

-- (b) Withdrawal amount cannot exceed the RSA balance.
CREATE OR REPLACE FUNCTION check_withdrawal_balance()
RETURNS TRIGGER AS $$
DECLARE
    acct_balance NUMERIC(14,2);
BEGIN
    SELECT balance INTO acct_balance
      FROM rsa_account
     WHERE rsa_account_id = NEW.rsa_account_id;
    IF acct_balance IS NULL THEN
        RAISE EXCEPTION 'RSA account % not found', NEW.rsa_account_id;
    END IF;
    IF NEW.amount > acct_balance THEN
        RAISE EXCEPTION 'Withdrawal % exceeds RSA balance % for account %',
            NEW.amount, acct_balance, NEW.rsa_account_id
            USING ERRCODE = 'check_violation';
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_withdrawal_balance
BEFORE INSERT OR UPDATE OF amount, rsa_account_id ON withdrawal_claim
FOR EACH ROW EXECUTE FUNCTION check_withdrawal_balance();

-- (c) Retirement claim requires age >= 50 unless is_early_flag is TRUE.
-- (Cannot be a CHECK because it depends on CURRENT_DATE.)
CREATE OR REPLACE FUNCTION check_retirement_age()
RETURNS TRIGGER AS $$
DECLARE
    emp_dob      DATE;
    holder_age   INT;
BEGIN
    IF NEW.claim_type = 'RETIREMENT' AND NEW.is_early_flag IS NOT TRUE THEN
        SELECT e.date_of_birth
          INTO emp_dob
          FROM rsa_account a
          JOIN employee e ON e.employee_id = a.employee_id
         WHERE a.rsa_account_id = NEW.rsa_account_id;
        IF emp_dob IS NULL THEN
            RAISE EXCEPTION 'Cannot resolve RSA holder for account %', NEW.rsa_account_id;
        END IF;
        holder_age := EXTRACT(YEAR FROM age(CURRENT_DATE, emp_dob))::INT;
        IF holder_age < 50 THEN
            RAISE EXCEPTION
              'Retirement claim requires age >= 50 (holder age %). Set is_early_flag=TRUE for early retirement.',
              holder_age
              USING ERRCODE = 'check_violation';
        END IF;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_retirement_age
BEFORE INSERT OR UPDATE ON withdrawal_claim
FOR EACH ROW EXECUTE FUNCTION check_retirement_age();

-- (d) Keep rsa_account.balance in sync with the contribution ledger.
-- Uses a STATEMENT-level trigger + transition table so that the 60k-row
-- bulk load in 04_bulk_data.sql finishes in well under 30 seconds.
CREATE OR REPLACE FUNCTION update_balance_on_contribution_stmt()
RETURNS TRIGGER AS $$
BEGIN
    UPDATE rsa_account a
       SET balance = a.balance + agg.added,
           updated_at = now()
      FROM (
        SELECT rsa_account_id,
               SUM(employer_share + employee_share) AS added
          FROM new_rows
         GROUP BY rsa_account_id
      ) agg
     WHERE a.rsa_account_id = agg.rsa_account_id;
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_balance_on_contribution_stmt
AFTER INSERT ON contribution
REFERENCING NEW TABLE AS new_rows
FOR EACH STATEMENT
EXECUTE FUNCTION update_balance_on_contribution_stmt();

-- (e) When a withdrawal claim moves to PAID, decrement the RSA balance.
CREATE OR REPLACE FUNCTION update_balance_on_withdrawal()
RETURNS TRIGGER AS $$
BEGIN
    IF (TG_OP = 'UPDATE' AND OLD.status <> 'PAID' AND NEW.status = 'PAID')
        OR (TG_OP = 'INSERT' AND NEW.status = 'PAID') THEN
        UPDATE rsa_account
           SET balance = balance - NEW.amount,
               updated_at = now()
         WHERE rsa_account_id = NEW.rsa_account_id;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_balance_on_withdrawal
AFTER INSERT OR UPDATE OF status ON withdrawal_claim
FOR EACH ROW EXECUTE FUNCTION update_balance_on_withdrawal();

-- (f) Total beneficiary share per RSA must not exceed 100%.
CREATE OR REPLACE FUNCTION check_beneficiary_share()
RETURNS TRIGGER AS $$
DECLARE
    total_share NUMERIC(7,2);
BEGIN
    SELECT COALESCE(SUM(share_pct), 0)
      INTO total_share
      FROM beneficiary
     WHERE rsa_account_id = NEW.rsa_account_id;
    IF TG_OP = 'UPDATE' THEN
        total_share := total_share - OLD.share_pct;
    END IF;
    total_share := total_share + NEW.share_pct;
    IF total_share > 100 THEN
        RAISE EXCEPTION 'Total beneficiary share % exceeds 100%% for RSA account %',
            total_share, NEW.rsa_account_id
            USING ERRCODE = 'check_violation';
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_beneficiary_share
BEFORE INSERT OR UPDATE OF share_pct ON beneficiary
FOR EACH ROW EXECUTE FUNCTION check_beneficiary_share();

-- =========================================================
-- Partial UNIQUE index: at most one OPEN withdrawal claim
-- per RSA account at any time.
-- =========================================================
CREATE UNIQUE INDEX one_open_claim_per_rsa
    ON withdrawal_claim (rsa_account_id)
    WHERE status = 'OPEN';

-- Done.
