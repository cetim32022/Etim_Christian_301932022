-- 03_seed_data.sql
-- Small, hand-curated seed data for Lagos Heritage Pensions Ltd.
-- Realistic Nigerian employers, names, locations, Naira amounts.
-- All dates are RELATIVE to today via CURRENT_DATE so this file never goes stale.
--
-- Run with:   psql -d pensions -v ON_ERROR_STOP=1 -f 03_seed_data.sql
-- Idempotent: DELETEs in dependency order before re-seeding.

\set ON_ERROR_STOP on
SET client_min_messages = warning;
SET timezone = 'Africa/Lagos';

-- Clean slate (children first)
DELETE FROM beneficiary;
DELETE FROM fund_switch;
DELETE FROM withdrawal_claim;
DELETE FROM contribution;
DELETE FROM fund_price;
DELETE FROM rsa_account;
DELETE FROM employee;
DELETE FROM custodian;
DELETE FROM pension_fund;
DELETE FROM employer;
SELECT setval('employer_employer_id_seq', 1, false);
SELECT setval('employee_employee_id_seq', 1, false);
SELECT setval('rsa_account_rsa_account_id_seq', 1, false);
SELECT setval('custodian_custodian_id_seq', 1, false);
SELECT setval('contribution_contribution_id_seq', 1, false);
SELECT setval('withdrawal_claim_claim_id_seq', 1, false);
SELECT setval('fund_switch_switch_id_seq', 1, false);
SELECT setval('beneficiary_beneficiary_id_seq', 1, false);

-- ===== Employers (6) =====
INSERT INTO employer (employer_code, name, sector, city, state, contact_email, monthly_contribution_day) VALUES
 ('LHP-EMP01', 'Dangote Industries Limited',         'Manufacturing',  'Lagos',     'Lagos State',     'pension@dangote.com',     25),
 ('LHP-EMP02', 'First Bank of Nigeria Plc',          'Financial Services','Lagos',  'Lagos State',     'rsa@firstbank.ng',        20),
 ('LHP-EMP03', 'MTN Nigeria Communications Plc',     'Telecommunications','Lagos',  'Lagos State',     'pensions@mtn.ng',         27),
 ('LHP-EMP04', 'NNPC Limited',                       'Oil and Gas',    'Abuja',     'FCT',             'rsa@nnpcgroup.com',       18),
 ('LHP-EMP05', 'University of Lagos',                'Education',      'Lagos',     'Lagos State',     'pensions@unilag.edu.ng',  28),
 ('LHP-EMP06', 'Lagos State Government',             'Public Service', 'Ikeja',     'Lagos State',     'pension@lagosstate.gov.ng', 22);

-- ===== Pension Funds (RSA Fund I to IV) =====
INSERT INTO pension_fund (fund_id, fund_code, fund_name, risk_profile, suggested_min_age) VALUES
 (1, 'FUND-I',  'RSA Fund I  - Retirees',                 'CONSERVATIVE', 60),
 (2, 'FUND-II', 'RSA Fund II - Pre-retirees (50+)',       'MODERATE',     50),
 (3, 'FUND-III','RSA Fund III - Mid-career (49 and below)','BALANCED',     18),
 (4, 'FUND-IV', 'RSA Fund IV - Active young (below 49)',  'AGGRESSIVE',   18);

-- ===== Custodians =====
INSERT INTO custodian (name, license_no, city) VALUES
 ('Sterling Pension Fund Custodian Limited', 'PFC/01/2006',  'Lagos'),
 ('Zenith Pensions Custodian Limited',       'PFC/05/2007',  'Lagos');

-- ===== Employees (30, gender-matched Nigerian names) =====
INSERT INTO employee (employer_id, staff_no, first_name, last_name, gender, date_of_birth, hire_date, monthly_salary, city, state, nin) VALUES
 (1, 'DNG-001', 'Chinedu',   'Adeyemi',     'M', DATE '1972-03-14', DATE '2009-06-01', 850000.00, 'Lagos',  'Lagos State', '12345678901'),
 (1, 'DNG-002', 'Aisha',     'Bello',       'F', DATE '1980-11-02', DATE '2012-09-12', 620000.00, 'Lagos',  'Lagos State', '12345678902'),
 (1, 'DNG-003', 'Emeka',     'Okonkwo',     'M', DATE '1985-07-23', DATE '2015-02-16', 540000.00, 'Lagos',  'Lagos State', '12345678903'),
 (2, 'FBN-001', 'Bolanle',   'Okafor',      'F', DATE '1978-04-19', DATE '2010-08-02', 980000.00, 'Lagos',  'Lagos State', '12345678904'),
 (2, 'FBN-002', 'Tunde',     'Olawale',     'M', DATE '1990-01-30', DATE '2018-04-09', 480000.00, 'Lagos',  'Lagos State', '12345678905'),
 (2, 'FBN-003', 'Ngozi',     'Eze',         'F', DATE '1995-05-12', DATE '2020-11-23', 410000.00, 'Lagos',  'Lagos State', '12345678906'),
 (3, 'MTN-001', 'Ibrahim',   'Danjuma',     'M', DATE '1976-08-08', DATE '2008-03-17', 1120000.00,'Lagos',  'Lagos State', '12345678907'),
 (3, 'MTN-002', 'Zainab',    'Abubakar',    'F', DATE '1988-12-25', DATE '2014-07-30', 720000.00, 'Lagos',  'Lagos State', '12345678908'),
 (3, 'MTN-003', 'Olusegun',  'Adekunle',    'M', DATE '1992-02-11', DATE '2019-05-05', 510000.00, 'Lagos',  'Lagos State', '12345678909'),
 (4, 'NNP-001', 'Yakubu',    'Mohammed',    'M', DATE '1968-06-30', DATE '2003-10-14', 1340000.00,'Abuja',  'FCT',         '12345678910'),
 (4, 'NNP-002', 'Halima',    'Yusuf',       'F', DATE '1974-09-21', DATE '2006-12-01', 890000.00, 'Abuja',  'FCT',         '12345678911'),
 (4, 'NNP-003', 'Chukwuemeka','Nwosu',      'M', DATE '1983-03-09', DATE '2013-08-20', 670000.00, 'Abuja',  'FCT',         '12345678912'),
 (5, 'UNI-001', 'Adaeze',    'Osuji',       'F', DATE '1979-10-04', DATE '2011-02-07', 460000.00, 'Lagos',  'Lagos State', '12345678913'),
 (5, 'UNI-002', 'Seyi',      'Adebayo',     'M', DATE '1986-06-18', DATE '2016-09-13', 420000.00, 'Lagos',  'Lagos State', '12345678914'),
 (5, 'UNI-003', 'Ifeoma',    'Obi',         'F', DATE '1993-08-29', DATE '2021-03-22', 380000.00, 'Lagos',  'Lagos State', '12345678915'),
 (6, 'LSG-001', 'Babatunde', 'Lawal',       'M', DATE '1969-12-11', DATE '2001-04-02', 760000.00, 'Ikeja',  'Lagos State', '12345678916'),
 (6, 'LSG-002', 'Bukola',    'Salami',      'F', DATE '1982-04-07', DATE '2010-06-21', 580000.00, 'Ikeja',  'Lagos State', '12345678917'),
 (6, 'LSG-003', 'Kolawole',  'Ojo',         'M', DATE '1991-11-15', DATE '2019-10-08', 450000.00, 'Ikeja',  'Lagos State', '12345678918'),
 (1, 'DNG-004', 'Yetunde',   'Adewale',     'F', DATE '1987-09-03', DATE '2017-01-15', 560000.00, 'Lagos',  'Lagos State', '12345678919'),
 (2, 'FBN-004', 'Sani',      'Aliyu',       'M', DATE '1975-02-28', DATE '2007-05-09', 1050000.00,'Lagos',  'Lagos State', '12345678920'),
 (3, 'MTN-004', 'Chioma',    'Adeleke',     'F', DATE '1996-07-12', DATE '2022-08-01', 390000.00, 'Lagos',  'Lagos State', '12345678921'),
 (4, 'NNP-004', 'Olumide',   'Ogunleye',    'M', DATE '1989-10-22', DATE '2018-12-03', 720000.00, 'Abuja',  'FCT',         '12345678922'),
 (5, 'UNI-004', 'Funke',     'Olatunji',    'F', DATE '1984-03-19', DATE '2014-04-11', 510000.00, 'Lagos',  'Lagos State', '12345678923'),
 (6, 'LSG-004', 'Ibrahim',   'Sani',        'M', DATE '1971-08-14', DATE '2005-07-19', 910000.00, 'Ikeja',  'Lagos State', '12345678924'),
 (1, 'DNG-005', 'Amara',     'Etim',        'F', DATE '1998-01-09', DATE '2023-02-13', 360000.00, 'Lagos',  'Lagos State', '12345678925'),
 (2, 'FBN-005', 'Bayo',      'Olatunji',    'M', DATE '1981-12-05', DATE '2012-11-26', 690000.00, 'Lagos',  'Lagos State', '12345678926'),
 (3, 'MTN-005', 'Zainab',    'Yusuf',       'F', DATE '1973-06-08', DATE '2006-03-15', 1020000.00,'Lagos',  'Lagos State', '12345678927'),
 (4, 'NNP-005', 'Tobi',      'Akinwale',    'M', DATE '1994-04-30', DATE '2020-09-07', 530000.00, 'Abuja',  'FCT',         '12345678928'),
 (5, 'UNI-005', 'Ebere',     'Nwankwo',     'F', DATE '1988-09-17', DATE '2016-12-01', 470000.00, 'Lagos',  'Lagos State', '12345678929'),
 (6, 'LSG-005', 'Femi',      'Olawale',     'M', DATE '1970-10-25', DATE '2002-06-04', 880000.00, 'Ikeja',  'Lagos State', '12345678930');

-- ===== RSA Accounts (one per employee) =====
-- Fund assignment follows PenCom rules of thumb: Fund I for 60+, Fund II for
-- 50-59, Fund IV for below 49, Fund III otherwise.
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
FROM employee e;

-- Fund prices for the last 36 months + next 14 days, per fund.
-- Uses generate_series on integers (no generate_series on time types).
INSERT INTO fund_price (fund_id, price_date, unit_price)
SELECT
    f.fund_id,
    (CURRENT_DATE + (gs.offset_days))::DATE,
    CASE
        WHEN f.fund_id = 1 THEN 1.0500 + (gs.offset_days % 30) * 0.0010
        WHEN f.fund_id = 2 THEN 1.1200 + (gs.offset_days % 30) * 0.0018
        WHEN f.fund_id = 3 THEN 1.2400 + (gs.offset_days % 30) * 0.0025
        WHEN f.fund_id = 4 THEN 1.3800 + (gs.offset_days % 30) * 0.0035
    END
FROM pension_fund f
CROSS JOIN generate_series(-1080, 14, 30) AS gs(offset_days);

-- ===== A handful of contributions (manual) for the seed employees
-- so the seed database alone tells a story even before bulk load.
-- Statutory minimums respected: 10% employer, 8% employee.
INSERT INTO contribution (
    rsa_account_id, employer_id, employee_id, custodian_id, fund_id,
    contribution_month, gross_salary, employer_share, employee_share,
    units_credited, posted_at
)
SELECT
    ra.rsa_account_id, e.employer_id, e.employee_id, ra.custodian_id, ra.fund_id,
    d.month_start, e.monthly_salary,
    ROUND(e.monthly_salary * 0.10, 2),
    ROUND(e.monthly_salary * 0.08, 2),
    ROUND((e.monthly_salary * 0.18) /
        (SELECT unit_price FROM fund_price fp
          WHERE fp.fund_id = ra.fund_id
            AND fp.price_date <= d.month_start
          ORDER BY fp.price_date DESC LIMIT 1), 4),
    d.month_start + INTERVAL '1 day'
FROM rsa_account ra
JOIN employee e ON e.employee_id = ra.employee_id
CROSS JOIN LATERAL (
    SELECT (date_trunc('month', CURRENT_DATE - INTERVAL '3 months') +
            (gs.n * INTERVAL '1 month'))::DATE AS month_start
    FROM generate_series(0, 3) AS gs(n)
) d
WHERE ra.rsa_account_id <= 30;

-- ===== Withdrawal claims (a few) =====
-- Two OPEN claims on different accounts; one PAID claim.
INSERT INTO withdrawal_claim (rsa_account_id, claim_type, amount, status, is_early_flag, requested_at, decided_at, paid_at)
SELECT rsa_account_id, 'EARLY', 50000.00, 'OPEN', TRUE, now() - INTERVAL '2 days', NULL, NULL
  FROM rsa_account WHERE rsa_account_id = 1;

INSERT INTO withdrawal_claim (rsa_account_id, claim_type, amount, status, is_early_flag, requested_at, decided_at, paid_at)
SELECT rsa_account_id, 'EARLY', 75000.00, 'OPEN', TRUE, now() - INTERVAL '1 day', NULL, NULL
  FROM rsa_account WHERE rsa_account_id = 7;

-- PAID claim on a retirement-eligible account (employee_id 10, Yakubu Mohammed, DOB 1968).
INSERT INTO withdrawal_claim (rsa_account_id, claim_type, amount, status, is_early_flag, requested_at, decided_at, paid_at)
SELECT rsa_account_id, 'RETIREMENT', 100000.00, 'PAID', FALSE,
       now() - INTERVAL '30 days', now() - INTERVAL '25 days', now() - INTERVAL '20 days'
  FROM rsa_account WHERE rsa_account_id = 10;

-- ===== Fund switches =====
INSERT INTO fund_switch (rsa_account_id, from_fund_id, to_fund_id, switched_at)
SELECT rsa_account_id, 4, 3, now() - INTERVAL '10 days'
  FROM rsa_account WHERE rsa_account_id = 3;

INSERT INTO fund_switch (rsa_account_id, from_fund_id, to_fund_id, switched_at)
SELECT rsa_account_id, 3, 2, now() - INTERVAL '5 days'
  FROM rsa_account WHERE rsa_account_id = 13;

-- ===== Beneficiaries =====
INSERT INTO beneficiary (rsa_account_id, full_name, relationship, share_pct)
SELECT rsa_account_id, 'Adeyemi Bisi', 'Spouse', 60.00
  FROM rsa_account WHERE rsa_account_id = 1;

INSERT INTO beneficiary (rsa_account_id, full_name, relationship, share_pct)
SELECT rsa_account_id, 'Adeyemi Chika', 'Child', 40.00
  FROM rsa_account WHERE rsa_account_id = 1;

INSERT INTO beneficiary (rsa_account_id, full_name, relationship, share_pct)
SELECT rsa_account_id, 'Bello Sadiq', 'Son', 100.00
  FROM rsa_account WHERE rsa_account_id = 2;

-- Done.
