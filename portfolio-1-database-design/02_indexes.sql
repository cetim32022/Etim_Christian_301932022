-- 02_indexes.sql
-- Secondary indexes for the pensions database.
-- Indexes every FK that triggers or reports use, plus the columns used by
-- the selective P2 queries. The partial UNIQUE index on withdrawal_claim
-- is already created in 01_schema.sql and is only re-listed here for reference.
--
-- Run with:   psql -d pensions -v ON_ERROR_STOP=1 -f 02_indexes.sql

\set ON_ERROR_STOP on
SET client_min_messages = warning;

-- FK indexes (used by triggers / reports / joins)
CREATE INDEX IF NOT EXISTS idx_employee_employer_id
    ON employee (employer_id);

CREATE INDEX IF NOT EXISTS idx_rsa_account_employee_id
    ON rsa_account (employee_id);

CREATE INDEX IF NOT EXISTS idx_rsa_account_fund_id
    ON rsa_account (fund_id);

CREATE INDEX IF NOT EXISTS idx_rsa_account_custodian_id
    ON rsa_account (custodian_id);

CREATE INDEX IF NOT EXISTS idx_contribution_rsa_account_id
    ON contribution (rsa_account_id);

CREATE INDEX IF NOT EXISTS idx_contribution_employer_id
    ON contribution (employer_id);

CREATE INDEX IF NOT EXISTS idx_contribution_employee_id
    ON contribution (employee_id);

CREATE INDEX IF NOT EXISTS idx_contribution_custodian_id
    ON contribution (custodian_id);

CREATE INDEX IF NOT EXISTS idx_contribution_fund_id
    ON contribution (fund_id);

CREATE INDEX IF NOT EXISTS idx_withdrawal_claim_rsa_account_id
    ON withdrawal_claim (rsa_account_id);

CREATE INDEX IF NOT EXISTS idx_withdrawal_claim_status
    ON withdrawal_claim (status);

CREATE INDEX IF NOT EXISTS idx_fund_switch_rsa_account_id
    ON fund_switch (rsa_account_id);

CREATE INDEX IF NOT EXISTS idx_beneficiary_rsa_account_id
    ON beneficiary (rsa_account_id);

-- Selective query indexes (used by P2 / 02_explain_analyze.sql)
CREATE INDEX IF NOT EXISTS idx_contribution_rsa_month
    ON contribution (rsa_account_id, contribution_month DESC);

CREATE INDEX IF NOT EXISTS idx_contribution_employer_month
    ON contribution (employer_id, contribution_month DESC);

CREATE INDEX IF NOT EXISTS idx_contribution_posted_at
    ON contribution (posted_at);

-- fund_price primary key (fund_id, price_date) already gives us the
-- composite index we need for fund lookups.

-- Re-listing the partial unique index from 01_schema.sql for reference;
-- IF NOT EXISTS keeps this idempotent.
CREATE UNIQUE INDEX IF NOT EXISTS one_open_claim_per_rsa
    ON withdrawal_claim (rsa_account_id)
    WHERE status = 'OPEN';

-- Done.
