-- 04_bulk_data.sql
-- Bulk data for the pensions database: 1,200 extra employees + 1,200 RSA
-- accounts + ~60,000 contributions via generate_series inside SQL.
--
-- Statutory minimums (employer 10% / employee 8%) are honoured, fund prices
-- already exist from 03_seed_data.sql, and the rsa_account.balance is kept
-- in sync by the STATEMENT-level transition-table trigger created in
-- 01_schema.sql so the whole load finishes in well under 30 seconds.
--
-- Every insert here is designed to succeed: dates are derived from
-- CURRENT_DATE, salaries are bounded, FK targets already exist.
--
-- Run AFTER 01_schema.sql, 02_indexes.sql, 03_seed_data.sql.
--   psql -d pensions -v ON_ERROR_STOP=1 -f 04_bulk_data.sql

\set ON_ERROR_STOP on
SET client_min_messages = warning;
SET timezone = 'Africa/Lagos';

-- Refill fund_price for any month in the bulk range that the seed file
-- (which uses 30-day steps) might have skipped. Cost is tiny and idempotent.
INSERT INTO fund_price (fund_id, price_date, unit_price)
SELECT
    f.fund_id,
    month_start::DATE,
    CASE
        WHEN f.fund_id = 1 THEN 1.0500 + (row_num % 30) * 0.0010
        WHEN f.fund_id = 2 THEN 1.1200 + (row_num % 30) * 0.0018
        WHEN f.fund_id = 3 THEN 1.2400 + (row_num % 30) * 0.0025
        WHEN f.fund_id = 4 THEN 1.3800 + (row_num % 30) * 0.0035
    END
FROM pension_fund f
CROSS JOIN (
    SELECT
        date_trunc('month',
            (CURRENT_DATE + make_interval(months => gs.m))::DATE
        ) AS month_start,
        gs.m AS row_num
    FROM generate_series(-120, 1) AS gs(m)
) ms
WHERE NOT EXISTS (
    SELECT 1 FROM fund_price fp
     WHERE fp.fund_id = f.fund_id AND fp.price_date = month_start::DATE
);

-- =========================================================
-- Bulk employees: 1,200 rows. gender-matched Nigerian names.
-- Salary range 45,000 - 1,500,000 Naira so statutory minimums
-- (10% / 8%) are always above 4,500 / 3,600 - well within
-- what we credit, so the contribution minimum trigger passes.
-- =========================================================
WITH params AS (
    SELECT
        ARRAY[
            'Chidi','Tunde','Bola','Emeka','Sani','Yakubu','Ibrahim','Olu','Kunle','Femi',
            'Seyi','Dele','Yemi','Bayo','Tobi','Kola','Wale','Sola','Nnamdi','Chukwu',
            'Danjuma','Ade','Tope','Gbolahan','Kabir','Musbau','Olumide','Henry','Samuel','Chika'
        ]::TEXT[] AS male_first,
        ARRAY[
            'Chioma','Funke','Ngozi','Aisha','Zainab','Halima','Bisi','Folake','Titi','Bukola',
            'Yetunde','Adaeze','Ifeoma','Toyin','Remi','Zainab','Amara','Nne','Ebere','Oluwaseun',
            'Sade','Modupe','Stella','Grace','Joy','Maryam','Aminat','Blessing','Patience','Hauwa'
        ]::TEXT[] AS female_first,
        ARRAY[
            'Adeyemi','Okafor','Mohammed','Okonkwo','Eze','Bello','Olawale','Ibrahim','Adeleke',
            'Ogunleye','Abubakar','Osuji','Okoro','Adebayo','Lawal','Ojo','Etim','Danjuma',
            'Adekunle','Nwosu','Obi','Salami','Adewale','Aliyu','Olatunji','Bashir','Adeyinka',
            'Ezeoke','Oyelowo','Ayodele'
        ]::TEXT[] AS last_names,
        ARRAY[
            'Lagos','Abuja','Kano','Ibadan','Port Harcourt','Enugu','Benin','Kaduna','Ilorin','Aba',
            'Warri','Jos','Ikeja','Surulere','Yaba','Lekki','Gbagada','Festac','Ikorodu','Agege'
        ]::TEXT[] AS cities,
        ARRAY[
            'Lagos State','FCT','Kano State','Oyo State','Rivers State','Enugu State',
            'Edo State','Kaduna State','Kwara State','Abia State','Delta State','Plateau State'
        ]::TEXT[] AS states
)
INSERT INTO employee (
    employer_id, staff_no, first_name, last_name, gender, date_of_birth,
    hire_date, monthly_salary, city, state, nin
)
SELECT
    (1 + (gs.id % 6))::BIGINT,                                       -- employer 1..6
    'BLK-' || lpad(gs.id::TEXT, 6, '0'),
    CASE WHEN gs.id % 2 = 0
         THEN p.male_first[1 + ((gs.id * 7)  % array_length(p.male_first,1))]
         ELSE p.female_first[1 + ((gs.id * 11) % array_length(p.female_first,1))]
    END,
    p.last_names[1 + ((gs.id * 13) % array_length(p.last_names,1))],
    CASE WHEN gs.id % 2 = 0 THEN 'M' ELSE 'F' END,
    (DATE '1960-01-01' + ((gs.id * 17) % 18000))::DATE,             -- 1960..2009-ish
    (DATE '2005-01-01' + ((gs.id * 19) % 6000))::DATE,             -- 2005..2021-ish
    45000.00 + ((gs.id * 23) % 1455000)::NUMERIC,                  -- 45,000 .. 1,500,000
    p.cities[1 + ((gs.id * 29) % array_length(p.cities,1))],
    p.states[1 + ((gs.id * 31) % array_length(p.states,1))],
    'NIN' || lpad(gs.id::TEXT, 11, '0')
FROM generate_series(1, 1200) AS gs(id)
CROSS JOIN params p;

-- =========================================================
-- Bulk RSA accounts: one per bulk employee.
-- Same fund-by-age rule as the seed file.
-- =========================================================
INSERT INTO rsa_account (rsa_number, employee_id, fund_id, custodian_id, balance, status, opened_at)
SELECT
    'LHP/RSA/' || to_char(e.employee_id, 'FM000000'),
    e.employee_id,
    CASE
        WHEN e.date_of_birth <= (CURRENT_DATE - INTERVAL '60 years')::DATE THEN 1
        WHEN e.date_of_birth <= (CURRENT_DATE - INTERVAL '50 years')::DATE THEN 2
        WHEN e.date_of_birth >  (CURRENT_DATE - INTERVAL '49 years')::DATE  THEN 4
        ELSE 3
    END,
    CASE WHEN e.employee_id % 2 = 0 THEN 1 ELSE 2 END,
    0,
    'ACTIVE',
    e.hire_date::TIMESTAMPTZ
FROM employee e
WHERE e.employee_id > 30;     -- seed already created accounts 1..30

-- =========================================================
-- Bulk contributions: ~60,000 rows.
-- 1,200 bulk RSA accounts x 50 months = 60,000 contributions.
-- Months cover the last 49 months plus the next 14 days (as a few
-- future-dated rows by stepping into month_start + 1 in the future).
-- =========================================================
INSERT INTO contribution (
    rsa_account_id, employer_id, employee_id, custodian_id, fund_id,
    contribution_month, gross_salary, employer_share, employee_share,
    units_credited, posted_at
)
SELECT
    ra.rsa_account_id,
    e.employer_id,
    e.employee_id,
    ra.custodian_id,
    ra.fund_id,
    cm.month_start::DATE,
    e.monthly_salary,
    ROUND(e.monthly_salary * 0.10, 2),
    ROUND(e.monthly_salary * 0.08, 2),
    ROUND((e.monthly_salary * 0.18) / fp.unit_price, 4),
    (cm.month_start + INTERVAL '1 day')::TIMESTAMPTZ
FROM rsa_account ra
JOIN employee e ON e.employee_id = ra.employee_id
CROSS JOIN LATERAL (
    SELECT date_trunc('month',
        (CURRENT_DATE + make_interval(months => gs.m))::DATE
    ) AS month_start
    FROM generate_series(-49, 0) AS gs(m)
) cm
JOIN LATERAL (
    SELECT fp.unit_price
      FROM fund_price fp
     WHERE fp.fund_id = ra.fund_id
       AND fp.price_date <= cm.month_start::DATE
     ORDER BY fp.price_date DESC
     LIMIT 1
) fp ON true
WHERE ra.rsa_account_id > 30;   -- seed already inserted history for accounts 1..30

-- A few FUTURE-DATED contributions in the next 14 days for the
-- first 10 accounts only - small batch, all should succeed.
INSERT INTO contribution (
    rsa_account_id, employer_id, employee_id, custodian_id, fund_id,
    contribution_month, gross_salary, employer_share, employee_share,
    units_credited, posted_at
)
SELECT
    ra.rsa_account_id,
    e.employer_id,
    e.employee_id,
    ra.custodian_id,
    ra.fund_id,
    (CURRENT_DATE + (gs.d * INTERVAL '1 day'))::DATE,
    e.monthly_salary,
    ROUND(e.monthly_salary * 0.10, 2),
    ROUND(e.monthly_salary * 0.08, 2),
    ROUND((e.monthly_salary * 0.18) /
        (SELECT unit_price FROM fund_price
          WHERE fund_id = ra.fund_id
            AND price_date <= CURRENT_DATE
          ORDER BY price_date DESC LIMIT 1), 4),
    now()
FROM rsa_account ra
JOIN employee e ON e.employee_id = ra.employee_id
CROSS JOIN generate_series(1, 10) AS gs(d)
WHERE ra.rsa_account_id BETWEEN 1 AND 10;

-- Sanity counts
SELECT 'employee_count' AS metric, count(*)::TEXT AS value FROM employee
UNION ALL SELECT 'rsa_account_count', count(*)::TEXT FROM rsa_account
UNION ALL SELECT 'contribution_count', count(*)::TEXT FROM contribution
UNION ALL SELECT 'fund_price_count', count(*)::TEXT FROM fund_price;

-- Done.
