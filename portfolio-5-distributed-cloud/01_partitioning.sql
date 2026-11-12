-- 01_partitioning.sql
-- Monthly RANGE partitioning of the `contribution` table for Lagos Heritage
-- Pensions Ltd. The biggest table is the one we partition.
--
-- Strategy:
--   * Detach the existing `contribution` table (created in 01_schema.sql)
--     and replace it with a partitioned parent that has the SAME columns,
--     constraints and indexes, then copy the existing rows in.
--   * Create one partition per month for EVERY month present in the data
--     (via a DO loop over a PL/pgSQL range) plus next month and a DEFAULT.
--   * Move the BEFORE-INSERT triggers and the partial UNIQUE index over.
--   * Print rows per partition and one pruned one-month EXPLAIN ANALYZE.
--
-- PG16 notes honoured by this file:
--   * UNIQUE constraints on a partitioned parent MUST include the partition
--     key. We move the unique (rsa_account_id, contribution_month) constraint
--     to the parent - contribution_month IS the partition key, so this works.
--   * PG16 does not allow EXCLUSION constraints on a partitioned parent, so
--     we do not try to add one.
--
-- Run AFTER: 01_schema.sql, 02_indexes.sql, 03_seed_data.sql, 04_bulk_data.sql
-- Run with:  psql -d pensions -v ON_ERROR_STOP=1 -f 01_partitioning.sql
-- Idempotent: yes - drops the partitioned version and rebuilds from the
--             un-partitioned original each time.

\set ON_ERROR_STOP on
SET client_min_messages = warning;
SET timezone = 'Africa/Lagos';

SELECT (relkind = 'p') AS already_partitioned FROM pg_class
 WHERE relname = 'contribution' AND relnamespace = 'public'::regnamespace \gset
\if :already_partitioned
\echo 'contribution is already partitioned - skipping the rebuild (safe to re-run)'
\else
-- =========================================================
-- 0. Save a copy of the existing (un-partitioned) contribution table.
-- =========================================================
DROP TABLE IF EXISTS contribution_unpartitioned;
ALTER TABLE contribution RENAME TO contribution_unpartitioned;

-- Drop the indexes that belonged to the old table; we recreate them on the
-- partitioned parent and they will propagate to every partition.
DROP INDEX IF EXISTS idx_contribution_rsa_month;
DROP INDEX IF EXISTS idx_contribution_employer_month;
DROP INDEX IF EXISTS idx_contribution_posted_at;
DROP INDEX IF EXISTS idx_contribution_rsa_account_id;
DROP INDEX IF EXISTS idx_contribution_employer_id;
DROP INDEX IF EXISTS idx_contribution_employee_id;
DROP INDEX IF EXISTS idx_contribution_custodian_id;
DROP INDEX IF EXISTS idx_contribution_fund_id;

-- =========================================================
-- 1. Recreate contribution as a partitioned parent.
--    Partition key: contribution_month (RANGE).
--    UNIQUE constraint (rsa_account_id, contribution_month) now lives on
--    the parent and includes the partition key, as PG16 requires.
-- =========================================================
CREATE TABLE contribution (
    contribution_id    BIGSERIAL,
    rsa_account_id     BIGINT        NOT NULL,
    employer_id        BIGINT        NOT NULL,
    employee_id        BIGINT        NOT NULL,
    custodian_id       BIGINT        NOT NULL,
    fund_id            BIGINT        NOT NULL,
    contribution_month DATE          NOT NULL,
    gross_salary       NUMERIC(12,2) NOT NULL CHECK (gross_salary > 0),
    employer_share     NUMERIC(12,2) NOT NULL CHECK (employer_share >= 0),
    employee_share     NUMERIC(12,2) NOT NULL CHECK (employee_share >= 0),
    total_amount       NUMERIC(12,2)
        GENERATED ALWAYS AS (employer_share + employee_share) STORED,
    units_credited     NUMERIC(14,4) NOT NULL DEFAULT 0
        CHECK (units_credited >= 0),
    posted_at          TIMESTAMPTZ   NOT NULL DEFAULT now(),
    -- The PK must include the partition key in PG16.
    PRIMARY KEY (contribution_id, contribution_month),
    UNIQUE (rsa_account_id, contribution_month),
    FOREIGN KEY (rsa_account_id)  REFERENCES rsa_account(rsa_account_id),
    FOREIGN KEY (employer_id)     REFERENCES employer(employer_id),
    FOREIGN KEY (employee_id)     REFERENCES employee(employee_id),
    FOREIGN KEY (custodian_id)    REFERENCES custodian(custodian_id),
    FOREIGN KEY (fund_id)         REFERENCES pension_fund(fund_id)
) PARTITION BY RANGE (contribution_month);

-- =========================================================
-- 2. Create one partition per month for EVERY month in the data plus next
--    month, plus a DEFAULT partition.
--    A DO loop walks the month range and CREATEs PARTITION ... FOR VALUES
--    FROM (...) TO (...). Each month's partition ends on the first of the
--    next month.
-- =========================================================
DO $$
DECLARE
    min_month DATE;
    max_month DATE;
    cur_month DATE;
    next_month DATE;
    part_name TEXT;
BEGIN
    SELECT date_trunc('month', MIN(contribution_month))::DATE
      INTO min_month
      FROM contribution_unpartitioned;

    SELECT date_trunc('month', MAX(contribution_month))::DATE
      INTO max_month
      FROM contribution_unpartitioned;

    -- Extend the range by one extra month so near-future inserts have a
    -- home partition.
    max_month := (max_month + make_interval(months => 1))::DATE;

    IF min_month IS NULL THEN
        RAISE NOTICE 'No data found in contribution_unpartitioned; nothing to partition.';
        RETURN;
    END IF;

    RAISE NOTICE 'Partition range: % to %', min_month, max_month;

    cur_month := min_month;
    WHILE cur_month <= max_month LOOP
        next_month := (cur_month + make_interval(months => 1))::DATE;
        part_name := 'contribution_' || to_char(cur_month, 'YYYYMM');
        EXECUTE format(
            'CREATE TABLE IF NOT EXISTS %I PARTITION OF contribution
             FOR VALUES FROM (%L) TO (%L)',
            part_name, cur_month, next_month
        );
        cur_month := next_month;
    END LOOP;

    -- DEFAULT partition catches anything outside the explicit range
    -- (e.g. a stray future-dated row beyond max_month + 1).
    EXECUTE 'CREATE TABLE IF NOT EXISTS contribution_default PARTITION OF contribution DEFAULT';

END
$$;

-- =========================================================
-- 3. Copy the rows from the un-partitioned original into the partitioned
--    parent. PostgreSQL routes each row to the right partition.
-- =========================================================
INSERT INTO contribution (
    contribution_id, rsa_account_id, employer_id, employee_id, custodian_id,
    fund_id, contribution_month, gross_salary, employer_share,
    employee_share, units_credited, posted_at
)
SELECT
    contribution_id, rsa_account_id, employer_id, employee_id, custodian_id,
    fund_id, contribution_month, gross_salary, employer_share,
    employee_share, units_credited, posted_at
FROM contribution_unpartitioned
ORDER BY contribution_id;

-- Re-sync the BIGSERIAL sequence so new inserts do not collide.
SELECT setval(
    pg_get_serial_sequence('contribution', 'contribution_id'),
    COALESCE(MAX(contribution_id), 1),
    true
) FROM contribution;

-- Re-create the business-rule triggers on the new partitioned parent AFTER the
-- copy, so the copy does not credit the balances a second time.
CREATE TRIGGER trg_contribution_minimum
BEFORE INSERT OR UPDATE ON contribution
FOR EACH ROW EXECUTE FUNCTION check_contribution_minimum();

CREATE TRIGGER trg_balance_on_contribution_stmt
AFTER INSERT ON contribution
REFERENCING NEW TABLE AS new_rows
FOR EACH STATEMENT
EXECUTE FUNCTION update_balance_on_contribution_stmt();

-- =========================================================
-- 4. Recreate the report indexes on the partitioned parent. They will be
--    applied to every existing partition AND every future partition.
-- =========================================================
CREATE INDEX idx_contribution_rsa_account_id
    ON contribution (rsa_account_id);

CREATE INDEX idx_contribution_employer_id
    ON contribution (employer_id);

CREATE INDEX idx_contribution_employee_id
    ON contribution (employee_id);

CREATE INDEX idx_contribution_custodian_id
    ON contribution (custodian_id);

CREATE INDEX idx_contribution_fund_id
    ON contribution (fund_id);

CREATE INDEX idx_contribution_rsa_month
    ON contribution (rsa_account_id, contribution_month DESC);

CREATE INDEX idx_contribution_employer_month
    ON contribution (employer_id, contribution_month DESC);

CREATE INDEX idx_contribution_posted_at
    ON contribution (posted_at);

-- ANALYZE so the planner sees fresh stats on every partition.
ANALYZE contribution;

-- Drop the un-partitioned copy now that everything is migrated.
DROP TABLE contribution_unpartitioned;

\endif

-- =========================================================
-- 5. Report: rows per partition.
-- =========================================================
\echo ''
\echo '=== Rows per partition (top 12 by row count) ==='
SELECT
    c.relname                                                     AS partition_name,
    pg_size_pretty(pg_total_relation_size(c.oid))                 AS size_on_disk,
    c.reltuples::BIGINT                             AS approx_rows
FROM pg_class c
JOIN pg_inherits i ON i.inhrelid = c.oid
JOIN pg_class p   ON p.oid = i.inhparent
WHERE p.relname = 'contribution'
ORDER BY approx_rows DESC
LIMIT 12;

\echo ''
\echo '=== Exact row count per partition (a quick scan) ==='
DO $$
DECLARE
    r RECORD;
    n BIGINT;
BEGIN
    FOR r IN
        SELECT c.relname AS part
          FROM pg_class c
          JOIN pg_inherits i ON i.inhrelid = c.oid
          JOIN pg_class p   ON p.oid = i.inhparent
         WHERE p.relname = 'contribution'
         ORDER BY c.relname
    LOOP
        EXECUTE format('SELECT count(*) FROM %I', r.part) INTO n;
        RAISE NOTICE '% : % rows', r.part, n;
    END LOOP;
END
$$;

-- =========================================================
-- 6. Show partition pruning for a one-month query.
-- =========================================================
\echo ''
\echo '=== Rows in DEFAULT partition (must be 0) ==='
SELECT count(*) AS default_partition_rows FROM contribution_default;

\echo ''
\echo '=== EXPLAIN ANALYZE: contributions for one specific month ==='
\echo '(Only the partition(s) covering that month should be scanned.)'
EXPLAIN (ANALYZE, BUFFERS)
SELECT
    rsa_account_id,
    sum(employer_share)  AS employer_total,
    sum(employee_share)  AS employee_total,
    sum(total_amount)    AS grand_total
FROM contribution
WHERE contribution_month >= date_trunc('month', CURRENT_DATE)::DATE
  AND contribution_month <  (date_trunc('month', CURRENT_DATE)
                             + make_interval(months => 1))::DATE
GROUP BY rsa_account_id
ORDER BY grand_total DESC
LIMIT 10;

\echo ''
\echo '=== End of 01_partitioning.sql ==='
