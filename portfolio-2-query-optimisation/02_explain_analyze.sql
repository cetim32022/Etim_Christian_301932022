-- 02_explain_analyze.sql
-- EXPLAIN (ANALYZE, BUFFERS) comparison for the 4 SELECTIVE P2 queries
-- (Q1 single RSA statement, Q2 employer contributions, Q3 one fund,
--  Q4 last 30 days). Drops the P2 selective indexes, captures the
--  BEFORE plan, recreates them, captures the AFTER plan.
--
-- HONEST CAVEAT (also reflected in README.md): the FULL-TABLE AGGREGATE
-- queries (Q5-Q8) are NOT in here. They naturally stay as Seq Scans because
-- they touch most or all of the contribution table; an index would not help.
--
-- Run with:   psql -d pensions -v ON_ERROR_STOP=1 -f 02_explain_analyze.sql
-- Requires:   P1 schema + seed + bulk data already loaded.

\set ON_ERROR_STOP on
SET timezone = 'Africa/Lagos';

\echo '========================================================'
\echo 'PHASE 1 - DROP the P2 selective indexes'
\echo '========================================================'

DROP INDEX IF EXISTS idx_contribution_rsa_month;
DROP INDEX IF EXISTS idx_contribution_employer_month;
DROP INDEX IF EXISTS idx_contribution_posted_at;
-- We do NOT drop the FK indexes (idx_contribution_rsa_account_id, etc.)
-- because they are also needed by triggers; we are isolating the *report*
-- indexes here, not disabling referential integrity.

\echo ''
\echo '========================================================'
\echo 'PHASE 2 - BEFORE plans (selective indexes gone)'
\echo '========================================================'

\echo ''
\echo '--- Q1 BEFORE: single RSA holder statement ---'
EXPLAIN (ANALYZE, BUFFERS)
SELECT c.contribution_month, c.employer_share, c.employee_share,
       c.total_amount, c.units_credited, c.posted_at
  FROM contribution c
 WHERE c.rsa_account_id = 1
 ORDER BY c.contribution_month DESC
 LIMIT 24;

\echo ''
\echo '--- Q2 BEFORE: one employer, last 12 months ---'
EXPLAIN (ANALYZE, BUFFERS)
SELECT c.contribution_month, count(*),
       sum(c.employer_share), sum(c.employee_share), sum(c.total_amount)
  FROM contribution c
 WHERE c.employer_id = 1
   AND c.contribution_month >= (date_trunc('month', CURRENT_DATE) - INTERVAL '12 months')::DATE
 GROUP BY c.contribution_month
 ORDER BY c.contribution_month DESC;

\echo ''
\echo '--- Q3 BEFORE: one fund latest price + 30-day avg ---'
EXPLAIN (ANALYZE, BUFFERS)
SELECT f.fund_code, fp.price_date, fp.unit_price, avg30.avg_30d
  FROM pension_fund f
  JOIN LATERAL (
       SELECT price_date, unit_price FROM fund_price fp
        WHERE fp.fund_id = f.fund_id
        ORDER BY fp.price_date DESC LIMIT 1) fp ON true
  JOIN LATERAL (
       SELECT avg(fp.unit_price) AS avg_30d FROM fund_price fp
        WHERE fp.fund_id = f.fund_id
          AND fp.price_date >= (CURRENT_DATE - 30)) avg30 ON true
 WHERE f.fund_id = 3;

\echo ''
\echo '--- Q4 BEFORE: last 30 days of posted contributions ---'
EXPLAIN (ANALYZE, BUFFERS)
SELECT c.contribution_id, c.rsa_account_id, c.total_amount, c.posted_at
  FROM contribution c
 WHERE c.posted_at >= now() - INTERVAL '30 days'
 ORDER BY c.posted_at DESC
 LIMIT 50;

\echo ''
\echo '========================================================'
\echo 'PHASE 3 - RECREATE the P2 selective indexes'
\echo '========================================================'

CREATE INDEX IF NOT EXISTS idx_contribution_rsa_month
    ON contribution (rsa_account_id, contribution_month DESC);

CREATE INDEX IF NOT EXISTS idx_contribution_employer_month
    ON contribution (employer_id, contribution_month DESC);

CREATE INDEX IF NOT EXISTS idx_contribution_posted_at
    ON contribution (posted_at);

ANALYZE contribution;
ANALYZE fund_price;

\echo ''
\echo '========================================================'
\echo 'PHASE 4 - AFTER plans (selective indexes present)'
\echo '========================================================'

\echo ''
\echo '--- Q1 AFTER: single RSA holder statement ---'
EXPLAIN (ANALYZE, BUFFERS)
SELECT c.contribution_month, c.employer_share, c.employee_share,
       c.total_amount, c.units_credited, c.posted_at
  FROM contribution c
 WHERE c.rsa_account_id = 1
 ORDER BY c.contribution_month DESC
 LIMIT 24;

\echo ''
\echo '--- Q2 AFTER: one employer, last 12 months ---'
EXPLAIN (ANALYZE, BUFFERS)
SELECT c.contribution_month, count(*),
       sum(c.employer_share), sum(c.employee_share), sum(c.total_amount)
  FROM contribution c
 WHERE c.employer_id = 1
   AND c.contribution_month >= (date_trunc('month', CURRENT_DATE) - INTERVAL '12 months')::DATE
 GROUP BY c.contribution_month
 ORDER BY c.contribution_month DESC;

\echo ''
\echo '--- Q3 AFTER: one fund latest price + 30-day avg ---'
EXPLAIN (ANALYZE, BUFFERS)
SELECT f.fund_code, fp.price_date, fp.unit_price, avg30.avg_30d
  FROM pension_fund f
  JOIN LATERAL (
       SELECT price_date, unit_price FROM fund_price fp
        WHERE fp.fund_id = f.fund_id
        ORDER BY fp.price_date DESC LIMIT 1) fp ON true
  JOIN LATERAL (
       SELECT avg(fp.unit_price) AS avg_30d FROM fund_price fp
        WHERE fp.fund_id = f.fund_id
          AND fp.price_date >= (CURRENT_DATE - 30)) avg30 ON true
 WHERE f.fund_id = 3;

\echo ''
\echo '--- Q4 AFTER: last 30 days of posted contributions ---'
EXPLAIN (ANALYZE, BUFFERS)
SELECT c.contribution_id, c.rsa_account_id, c.total_amount, c.posted_at
  FROM contribution c
 WHERE c.posted_at >= now() - INTERVAL '30 days'
 ORDER BY c.posted_at DESC
 LIMIT 50;

\echo ''
\echo '========================================================'
\echo 'PHASE 5 - Reference: full-table aggregate stays Seq Scan'
\echo '(no index is created for these - it would not help)'
\echo '========================================================'

\echo ''
\echo '--- Q5 reference: total contributions per employer ---'
EXPLAIN (ANALYZE, BUFFERS)
SELECT emp.employer_code, count(*), sum(c.total_amount)
  FROM contribution c JOIN employer emp ON emp.employer_id = c.employer_id
 GROUP BY emp.employer_code;

\echo ''
\echo '=== End of 02_explain_analyze.sql ==='
