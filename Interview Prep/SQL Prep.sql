-- =====================================================
-- SETUP: CREATE + INSERT (idempotent, Snowflake style)
-- =====================================================
CREATE DATABASE IF NOT EXISTS SQL_LEARNING;
CREATE SCHEMA IF NOT EXISTS SQL_LEARNING.SQL_LEARNING_SCHEMA;
USE SCHEMA SQL_LEARNING.SQL_LEARNING_SCHEMA;

CREATE OR REPLACE TABLE SQL_LEARNING.SQL_LEARNING_SCHEMA.sales (
  region    VARCHAR(20),
  sale_date DATE,
  amount    NUMBER(10,2)
);

INSERT INTO SQL_LEARNING.SQL_LEARNING_SCHEMA.sales VALUES
  ('South','2026-10-01',100),
  ('South','2026-10-02',150),
  ('South','2026-10-03',120),
  ('South','2026-10-04',200),
  ('South','2026-10-05',180),
  ('North','2026-10-01',300),
  ('North','2026-10-02',250),
  ('North','2026-10-03',400),
  ('North','2026-10-05',350);   -- 10-04 missing on purpose (date gap scenario)

CREATE OR REPLACE TABLE SQL_LEARNING.SQL_LEARNING_SCHEMA.emp_salary (
  emp_id NUMBER,
  year   NUMBER,
  salary NUMBER(12,2)
);

INSERT INTO SQL_LEARNING.SQL_LEARNING_SCHEMA.emp_salary VALUES
  (101,2023,600000),(101,2024,660000),(101,2025,726000),   -- 10% every year
  (102,2023,800000),(102,2024,840000),(102,2025,882000),   -- 5% every year
  (103,2023,500000),(103,2024,500000),(103,2025,550000);   -- no hike in 2024

CREATE OR REPLACE TABLE SQL_LEARNING.SQL_LEARNING_SCHEMA.emp_rating (
  emp_id NUMBER,
  salary NUMBER(12,2),
  rating VARCHAR(1)
);

INSERT INTO SQL_LEARNING.SQL_LEARNING_SCHEMA.emp_rating VALUES
  (101,726000,'A'),
  (102,882000,'B'),
  (103,550000,'C');

-- =====================================================
-- SCENARIO 1: Running total + 3-row rolling sum/avg
-- (named WINDOW clause is not supported; frames inline)
-- =====================================================
SELECT region, sale_date, amount,
  SUM(amount) OVER (PARTITION BY region ORDER BY sale_date
        ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)   AS running_total,
        SUM(amount) OVER (PARTITION BY region ORDER BY sale_date) as RUNNING_TOTAL_EXAMPLE,
          SUM(amount) OVER (PARTITION BY region ORDER BY sale_date
        ROWS BETWEEN 1 PRECEDING AND CURRENT ROW)           AS rolling_2row_sum,
  SUM(amount) OVER (PARTITION BY region ORDER BY sale_date
        ROWS BETWEEN 2 PRECEDING AND CURRENT ROW)           AS rolling_3row_sum,
  ROUND(AVG(amount) OVER (PARTITION BY region ORDER BY sale_date
        ROWS BETWEEN 2 PRECEDING AND CURRENT ROW), 2)       AS rolling_3row_avg
FROM SQL_LEARNING.SQL_LEARNING_SCHEMA.sales
ORDER BY region, sale_date;

-- =====================================================
-- SCENARIO 2: Rolling by DATE range (handles gaps)
-- Snowflake supports RANGE with INTERVAL on DATE/TIMESTAMP
-- =====================================================
SELECT region, sale_date, amount,
SUM(amount) OVER (PARTITION BY region ORDER BY sale_date
        RANGE BETWEEN INTERVAL '1 DAYS' PRECEDING AND CURRENT ROW) AS rolling_2day_sum,
    
  SUM(amount) OVER (PARTITION BY region ORDER BY sale_date
        RANGE BETWEEN INTERVAL '2 DAYS' PRECEDING AND CURRENT ROW) AS rolling_3day_sum
FROM SQL_LEARNING.SQL_LEARNING_SCHEMA.sales
ORDER BY region, sale_date;

-- =====================================================
-- SCENARIO 3: Year-on-year hike amount and %
-- DIV0NULL replaces NULLIF(x,0) division
-- =====================================================
SELECT emp_id, year, salary,
  LAG(salary) OVER (PARTITION BY emp_id ORDER BY year)           AS prev_salary,
  salary - prev_salary                                           AS hike_amt,
  ROUND(DIV0NULL(salary - prev_salary, prev_salary) * 100, 2)    AS hike_pct
FROM SQL_LEARNING.SQL_LEARNING_SCHEMA.emp_salary
ORDER BY emp_id, year;   -- Snowflake allows reusing column aliases in the same SELECT

-- =====================================================
-- SCENARIO 4: Same, filtering first row with QUALIFY (no CTE needed)
-- =====================================================
SELECT emp_id, year, salary,
  LAG(salary) OVER (PARTITION BY emp_id ORDER BY year)           AS prev_salary,
  salary - prev_salary                                           AS hike_amt,
  ROUND(DIV0NULL(salary - prev_salary, prev_salary) * 100, 2)    AS hike_pct
FROM SQL_LEARNING.SQL_LEARNING_SCHEMA.emp_salary
QUALIFY prev_salary IS NOT NULL
ORDER BY emp_id, year;

-- =====================================================
-- SCENARIO 5: Highest hike % per year
-- (2025 returns a tie: 101 and 103, since RANK keeps ties)
-- =====================================================
WITH h AS (
  SELECT emp_id, year, salary,
  LAG(salary) OVER (PARTITION BY emp_id ORDER BY year)           AS prev_salary,
  salary - prev_salary                                           AS hike_amt,
  ROUND(DIV0NULL(salary - prev_salary, prev_salary) * 100, 2)    AS hike_pct
FROM SQL_LEARNING.SQL_LEARNING_SCHEMA.emp_salary
)
SELECT emp_id, year, ROUND(hike_pct, 2) AS hike_pct
FROM h
WHERE hike_pct IS NOT NULL
QUALIFY RANK() OVER (PARTITION BY year ORDER BY hike_pct DESC) = 1
ORDER BY year;

-- =====================================================
-- SCENARIO 6: Employees who got a hike EVERY year
-- BOOLAND_AGG = TRUE only if every row is TRUE (expected: 101, 102)
-- =====================================================
WITH h AS (
  SELECT emp_id, salary,
    LAG(salary) OVER (PARTITION BY emp_id ORDER BY year) AS prev_salary
  FROM SQL_LEARNING.SQL_LEARNING_SCHEMA.emp_salary
  QUALIFY prev_salary IS NOT NULL
)
SELECT emp_id
FROM h
GROUP BY emp_id
HAVING BOOLAND_AGG(salary > prev_salary);

-- =====================================================
-- SCENARIO 7: Employee-years with NO hike
-- =====================================================
SELECT emp_id, year
FROM SQL_LEARNING.SQL_LEARNING_SCHEMA.emp_salary
QUALIFY salary <= LAG(salary) OVER (PARTITION BY emp_id ORDER BY year);

-- =====================================================
-- SCENARIO 8: Apply hike by rating (A=15%, B=10%, else 5%)
-- DECODE is Snowflake's compact CASE
-- =====================================================
SELECT emp_id, salary, rating,
  salary * DECODE(rating, 'A', 1.15, 'B', 1.10, 1.05) AS new_salary
FROM SQL_LEARNING.SQL_LEARNING_SCHEMA.emp_rating;

SELECT *  FROM SQL_LEARNING.SQL_LEARNING_SCHEMA.emp_rating;
-- =====================================================
-- SCENARIO 9: Project next 3 years at 10%
-- GENERATOR builds the year rows (no hard-coded columns)
-- =====================================================
SELECT s.emp_id,
       2025 + g.n                              AS proj_year,
       ROUND(s.salary * POWER(1.10, g.n), 2)   AS proj_salary
FROM SQL_LEARNING.SQL_LEARNING_SCHEMA.emp_salary s
CROSS JOIN (SELECT SEQ4() + 1 AS n FROM TABLE(GENERATOR(ROWCOUNT => 3))) g
WHERE s.year = 2025
ORDER BY s.emp_id, proj_year;

-- =====================================================
-- SCENARIO 10: First vs latest salary + total career growth %
-- MIN_BY / MAX_BY replace FIRST_VALUE/LAST_VALUE + DISTINCT
-- =====================================================
SELECT emp_id,
  MIN_BY(salary, year)                                                  AS first_salary,
  MAX_BY(salary, year)                                                  AS latest_salary,
  (DIV0NULL(MAX_BY(salary, year), MIN_BY(salary, year))) as Ref,
  ROUND((DIV0NULL(MAX_BY(salary, year), MIN_BY(salary, year)) - 1) * 100, 2) AS total_growth_pct
FROM SQL_LEARNING.SQL_LEARNING_SCHEMA.emp_salary
GROUP BY emp_id
ORDER BY emp_id;

-- =====================================================
-- SCENARIO 11: Cumulative salary paid + next year's salary (LEAD)
-- =====================================================
SELECT emp_id, year, salary,
  SUM(salary) OVER (PARTITION BY emp_id ORDER BY year
        ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS cumulative_paid,
  LEAD(salary) OVER (PARTITION BY emp_id ORDER BY year)   AS next_year_salary
FROM SQL_LEARNING.SQL_LEARNING_SCHEMA.emp_salary
ORDER BY emp_id, year;
