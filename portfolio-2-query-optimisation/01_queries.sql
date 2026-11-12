-- 01_queries.sql
-- 8 reporting queries for Lagos Heritage Pensions Ltd.
--   Q1-Q4: SELECTIVE (filter by a single RSA account / employer / fund / date)
--   Q5-Q8: FULL-TABLE AGGREGATES (no narrow WHERE filter)
--
-- All queries are written to be correct and readable; the goal of P2 is the
-- explain/analyse comparison in 02_explain_analyze.sql, NOT to be clever here.
--
-- Run with:   psql -d pensions -v ON_ERROR_STOP=1 -f 01_queries.sql
-- Requires:   P1 schema + seed + bulk data already loaded.

\set ON_ERROR_STOP on
SET timezone = 'Africa/Lagos';

\echo '=== Q1: RSA holder statement (single account) ==='
-- Selective: one RSA holder's contribution + claim history, joined and ordered.
SELECT
    c.contribution_month,
    c.employer_share,
    c.employee_share,
    c.total_amount,
    c.units_credited,
    c.posted_at
FROM contribution c
WHERE c.rsa_account_id = 1
ORDER BY c.contribution_month DESC
LIMIT 24;

\echo ''
\echo '=== Q2: One employer''s contributions (last 12 months) ==='
-- Selective: contributions posted by a single employer in the last year.
SELECT
    c.contribution_month,
    count(*)                       AS lines,
    sum(c.employer_share)          AS employer_total,
    sum(c.employee_share)          AS employee_total,
    sum(c.total_amount)            AS grand_total
FROM contribution c
WHERE c.employer_id = 1
  AND c.contribution_month >= (date_trunc('month', CURRENT_DATE) - INTERVAL '12 months')::DATE
GROUP BY c.contribution_month
ORDER BY c.contribution_month DESC;

\echo ''
\echo '=== Q3: One fund - latest price and 30-day moving average ==='
-- Selective: stats for one pension fund.
SELECT
    f.fund_code,
    f.fund_name,
    fp_latest.price_date      AS latest_price_date,
    fp_latest.unit_price      AS latest_unit_price,
    ROUND(fp_stats.avg_30d, 4) AS avg_unit_price_30d
FROM pension_fund f
JOIN LATERAL (
    SELECT price_date, unit_price
      FROM fund_price fp
     WHERE fp.fund_id = f.fund_id
     ORDER BY fp.price_date DESC
     LIMIT 1
) fp_latest ON true
JOIN LATERAL (
    SELECT avg(fp.unit_price) AS avg_30d
      FROM fund_price fp
     WHERE fp.fund_id = f.fund_id
       AND fp.price_date >= (CURRENT_DATE - 30)
) fp_stats ON true
WHERE f.fund_id = 3;

\echo ''
\echo '=== Q4: Last 30 days of activity (contributions posted) ==='
-- Selective: contributions posted in the last 30 days.
SELECT
    c.contribution_id,
    c.rsa_account_id,
    e.first_name || ' ' || e.last_name   AS holder,
    c.contribution_month,
    c.total_amount,
    c.posted_at
FROM contribution c
JOIN employee e ON e.employee_id = c.employee_id
WHERE c.posted_at >= now() - INTERVAL '30 days'
ORDER BY c.posted_at DESC
LIMIT 50;

\echo ''
\echo '=== Q5: Total contributions per employer (full aggregate) ==='
-- Full-table aggregate: sums across the whole contribution table.
SELECT
    emp.employer_code,
    emp.name,
    count(*)                       AS contribution_lines,
    sum(c.employer_share)          AS employer_total,
    sum(c.employee_share)          AS employee_total,
    sum(c.total_amount)            AS grand_total
FROM contribution c
JOIN employer emp ON emp.employer_id = c.employer_id
GROUP BY emp.employer_code, emp.name
ORDER BY grand_total DESC;

\echo ''
\echo '=== Q6: Average RSA balance per fund (full aggregate) ==='
-- Full-table aggregate: average balance across every RSA account, per fund.
SELECT
    f.fund_code,
    f.fund_name,
    count(*)                       AS accounts,
    ROUND(avg(ra.balance), 2)      AS avg_balance_naira,
    ROUND(sum(ra.balance), 2)      AS total_balance_naira
FROM rsa_account ra
JOIN pension_fund f ON f.fund_id = ra.fund_id
GROUP BY f.fund_code, f.fund_name
ORDER BY f.fund_code;

\echo ''
\echo '=== Q7: Withdrawal claims by status (full aggregate) ==='
-- Full-table aggregate: claim counts and total amounts grouped by status.
SELECT
    status,
    claim_type,
    count(*)                       AS claims,
    ROUND(sum(amount), 2)          AS total_claimed
FROM withdrawal_claim
GROUP BY status, claim_type
ORDER BY status, claim_type;

\echo ''
\echo '=== Q8: Monthly contribution totals across the whole fund (last 24 months) ==='
-- Full-table aggregate (time-bucketed).
SELECT
    to_char(date_trunc('month', c.contribution_month), 'YYYY-MM') AS yyyymm,
    count(*)                       AS lines,
    sum(c.total_amount)            AS total_naira
FROM contribution c
WHERE c.contribution_month >= (date_trunc('month', CURRENT_DATE) - INTERVAL '24 months')::DATE
GROUP BY date_trunc('month', c.contribution_month)
ORDER BY date_trunc('month', c.contribution_month) DESC;

\echo ''
\echo '=== End of 01_queries.sql ==='
