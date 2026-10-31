-- =====================================================
-- DATA ENGINEER SQL PATTERNS (Snowflake)
-- Run SETUP once, then each scenario independently
-- =====================================================
USE SCHEMA SQL_LEARNING.SQL_LEARNING_SCHEMA;

-- =====================================================
-- SETUP
-- =====================================================
CREATE OR REPLACE TABLE emp (
  emp_id NUMBER, name VARCHAR, dept VARCHAR, salary NUMBER(12,2), manager_id NUMBER
);
INSERT INTO emp VALUES
  (1,'Asha' ,'Exec' ,300000,NULL),
  (2,'Ravi' ,'Eng'  ,180000,1),
  (3,'Meena','Eng'  ,200000,2),   -- earns more than manager Ravi
  (4,'Karan','Eng'  ,150000,2),
  (5,'Divya','Eng'  ,150000,2),   -- tie with Karan
  (6,'Arun' ,'Sales',120000,1),
  (7,'Priya','Sales',130000,6),   -- earns more than manager Arun
  (8,'Vikas','Sales',100000,6);

CREATE OR REPLACE TABLE emp_dup (emp_id NUMBER, name VARCHAR, dept VARCHAR);
INSERT INTO emp_dup VALUES
  (1,'Asha','Exec'),(2,'Ravi','Eng'),(2,'Ravi','Eng'),
  (3,'Meena','Eng'),(3,'Meena','Eng'),(3,'Meena','Eng');

CREATE OR REPLACE TABLE logins (user_id NUMBER, login_date DATE);
INSERT INTO logins VALUES
  (1,'2026-10-01'),(1,'2026-10-02'),(1,'2026-10-03'),   -- streak of 3
  (1,'2026-10-05'),(1,'2026-10-06'),                    -- streak of 2
  (2,'2026-10-01'),(2,'2026-10-03'),(2,'2026-10-04');

CREATE OR REPLACE TABLE products (product_id NUMBER, product VARCHAR, category VARCHAR);
INSERT INTO products VALUES
  (10,'Laptop','Electronics'),(11,'Phone','Electronics'),(12,'Tablet','Electronics'),
  (13,'Watch','Electronics'),(20,'Shirt','Fashion'),(21,'Shoes','Fashion'),
  (22,'Cap','Fashion');                                 -- Cap never sold

CREATE OR REPLACE TABLE customers (customer_id NUMBER, cust_name VARCHAR);
INSERT INTO customers VALUES (100,'Anil'),(101,'Bala'),(102,'Chitra'),(103,'Deepa'); -- Deepa no orders

CREATE OR REPLACE TABLE orders (
  order_id NUMBER, customer_id NUMBER, product_id NUMBER, order_date DATE, amount NUMBER(10,2)
);
INSERT INTO orders VALUES
  (1,100,10,'2026-01-05',1000),(2,101,11,'2026-01-20', 800),(3,102,20,'2026-01-25', 50),
  (4,100,11,'2026-02-03', 800),(5,101,12,'2026-02-14', 500),(6,102,21,'2026-02-18',120),
  (7,100,13,'2026-03-01', 300),(8,101,10,'2026-03-09',1000),(9,102,20,'2026-03-15', 50),
  (10,100,10,'2026-03-20',1000),(11,101,21,'2026-03-28',120);   -- no orders 03-02..03-08 (gap demo)

CREATE OR REPLACE TABLE events (user_id NUMBER, event_ts TIMESTAMP_NTZ);
INSERT INTO events VALUES
  (1,'2026-10-01 09:00'),(1,'2026-10-01 09:10'),(1,'2026-10-01 09:25'),  -- session 1
  (1,'2026-10-01 11:00'),(1,'2026-10-01 11:05'),                         -- session 2 (>30 min gap)
  (2,'2026-10-01 10:00'),(2,'2026-10-01 10:45');                         -- 2 sessions

CREATE OR REPLACE TABLE customer_history (
  customer_id NUMBER, city VARCHAR, updated_at TIMESTAMP_NTZ
);
INSERT INTO customer_history VALUES
  (100,'Chennai'  ,'2026-01-01'),(100,'Bangalore','2026-06-01'),
  (101,'Mumbai'   ,'2026-02-01'),
  (102,'Delhi'    ,'2026-01-15'),(102,'Pune','2026-03-10'),(102,'Hyderabad','2026-09-01');

CREATE OR REPLACE TABLE raw_json (payload VARIANT);
INSERT INTO raw_json
  SELECT PARSE_JSON('{"order_id":1,"customer":{"id":100,"name":"Anil"},
                      "items":[{"sku":"A1","qty":2,"price":10.5},{"sku":"B2","qty":1,"price":99}]}')
  UNION ALL
  SELECT PARSE_JSON('{"order_id":2,"customer":{"id":101,"name":"Bala"},
                      "items":[{"sku":"C3","qty":5,"price":4}]}');

-- SCD target and incoming source
CREATE OR REPLACE TABLE dim_customer (
  customer_id NUMBER, city VARCHAR,
  valid_from TIMESTAMP_NTZ, valid_to TIMESTAMP_NTZ, is_current BOOLEAN
);
INSERT INTO dim_customer VALUES
  (100,'Chennai','2026-01-01',NULL,TRUE),
  (101,'Mumbai' ,'2026-02-01',NULL,TRUE);

CREATE OR REPLACE TABLE stg_customer (customer_id NUMBER, city VARCHAR);
INSERT INTO stg_customer VALUES
  (100,'Bangalore'),   -- changed  -> expire old, insert new
  (101,'Mumbai'),      -- same     -> no-op
  (102,'Pune');        -- new      -> insert

-- =====================================================
-- 1. NTH HIGHEST SALARY (overall and per department)
-- DENSE_RANK so ties don't skip a rank
-- =====================================================
-- 2nd highest overall
SELECT name, salary
FROM emp
QUALIFY DENSE_RANK() OVER (ORDER BY salary DESC) = 2;

-- 2nd highest per department
SELECT dept, name, salary
FROM emp
QUALIFY DENSE_RANK() OVER (PARTITION BY dept ORDER BY salary DESC) = 2;

SELECT dept, name, salary, DENSE_RANK()  OVER (PARTITION BY dept ORDER BY salary DESC) as DENSE_RANK
FROM emp;

-- Without window functions (classic interview version)
SELECT MAX(salary) AS second_highest
FROM emp
WHERE salary < (SELECT MAX(salary) FROM emp);

-- =====================================================
-- 2. DUPLICATES: find, then delete keeping one
-- =====================================================
-- Find duplicate keys
SELECT * FROM  emp_dup;

SELECT emp_id, name, COUNT(*) AS cnt
FROM emp_dup
GROUP BY emp_id, name
HAVING COUNT(*) > 1;

-- Show the extra copies (rn > 1)
SELECT *
FROM emp_dup
QUALIFY ROW_NUMBER() OVER (PARTITION BY emp_id, name, dept ORDER BY emp_id) > 1;

-- Deduplicate: Snowflake has no ROWID, so rebuild the table
-- INSERT OVERWRITE keeps grants/structure of the table
INSERT OVERWRITE INTO emp_dup
SELECT DISTINCT * FROM emp_dup;

SELECT * FROM emp_dup ORDER BY emp_id;

-- =====================================================
-- 3. GAPS AND ISLANDS: consecutive login streaks
-- Trick: date - row_number is constant within a streak
-- =====================================================
WITH g AS (
  SELECT user_id, login_date,
    DATEADD(day, -ROW_NUMBER() OVER (PARTITION BY user_id ORDER BY login_date), login_date) AS grp
  FROM logins
)
SELECT user_id,
       MIN(login_date) AS streak_start,
       MAX(login_date) AS streak_end,
       COUNT(*)        AS streak_days
FROM g
GROUP BY user_id, grp
ORDER BY user_id, streak_start;

-- Missing dates (gaps) per user
SELECT user_id,
       DATEADD(day, 1, login_date)                 AS gap_start,
       DATEADD(day, -1, next_date)                 AS gap_end
FROM (
  SELECT user_id, login_date,
         LEAD(login_date) OVER (PARTITION BY user_id ORDER BY login_date) AS next_date
  FROM logins
)
WHERE DATEDIFF(day, login_date, next_date) > 1;

-- =====================================================
-- 4. TOP N PER GROUP: top 2 products by revenue per category
-- =====================================================
SELECT p.category, p.product, SUM(o.amount) AS revenue
FROM orders o
JOIN products p ON p.product_id = o.product_id
GROUP BY p.category, p.product
QUALIFY ROW_NUMBER() OVER (PARTITION BY p.category ORDER BY revenue DESC) <= 2
ORDER BY p.category, revenue DESC;

-- =====================================================
-- 5. SELF JOIN: employees earning more than their manager
-- =====================================================
SELECT e.name AS employee, e.salary,
       m.name AS manager,  m.salary AS manager_salary
FROM emp e
JOIN emp m ON e.manager_id = m.emp_id
WHERE e.salary > m.salary;

-- =====================================================
-- 6. MONTH-ON-MONTH GROWTH %
-- For YoY use LAG(revenue, 12) on a full monthly series
-- =====================================================
WITH m AS (
  SELECT DATE_TRUNC('month', order_date) AS month, SUM(amount) AS revenue
  FROM orders
  GROUP BY 1
)
SELECT month, revenue,
  LAG(revenue) OVER (ORDER BY month)                                          AS prev_month,
  ROUND(DIV0NULL(revenue - prev_month, prev_month) * 100, 2)                  AS mom_pct
FROM m
ORDER BY month;

-- =====================================================
-- 7. SESSIONIZATION: new session if gap > 30 minutes
-- Step 1 flag a new session, Step 2 running SUM of flags
-- =====================================================
WITH f AS (
  SELECT user_id, event_ts,
    IFF(DATEDIFF(minute,
                 LAG(event_ts) OVER (PARTITION BY user_id ORDER BY event_ts),
                 event_ts) <= 30, 0, 1) AS new_session   -- first event: NULL -> 1
  FROM events
)
SELECT user_id, event_ts,
  SUM(new_session) OVER (PARTITION BY user_id ORDER BY event_ts
                         ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS session_id
FROM f
ORDER BY user_id, event_ts;

-- =====================================================
-- 8. PIVOT / UNPIVOT
-- =====================================================
-- Native PIVOT: revenue per category by month
SELECT *
FROM (
  SELECT p.category, TO_CHAR(o.order_date,'YYYY-MM') AS mon, o.amount
  FROM orders o JOIN products p ON p.product_id = o.product_id
)
PIVOT (SUM(amount) FOR mon IN ('2026-01','2026-02','2026-03'))
  AS pv (category, jan, feb, mar);

-- Same with conditional aggregation (works in any database)
SELECT p.category,
  SUM(IFF(MONTH(o.order_date) = 1, o.amount, 0)) AS jan,
  SUM(IFF(MONTH(o.order_date) = 2, o.amount, 0)) AS feb,
  SUM(IFF(MONTH(o.order_date) = 3, o.amount, 0)) AS mar
FROM orders o JOIN products p ON p.product_id = o.product_id
GROUP BY p.category;

-- UNPIVOT: columns back to rows
WITH wide AS (
  SELECT 'Electronics' AS category, 1000 AS jan, 1300 AS feb, 2300 AS mar
)
SELECT category, mon, revenue
FROM wide
UNPIVOT (revenue FOR mon IN (jan, feb, mar));

-- =====================================================
-- 9. ANTI-JOIN: customers with no orders, products never sold
-- =====================================================
SELECT c.*
FROM customers c
LEFT JOIN orders o ON o.customer_id = c.customer_id
WHERE o.order_id IS NULL;

SELECT p.*
FROM products p
WHERE NOT EXISTS (SELECT 1 FROM orders o WHERE o.product_id = p.product_id);
-- Avoid NOT IN when the subquery can return NULL: it returns no rows

-- =====================================================
-- 10. LATEST RECORD PER KEY
-- =====================================================
SELECT *
FROM customer_history
QUALIFY ROW_NUMBER() OVER (PARTITION BY customer_id ORDER BY updated_at DESC) = 1;

-- Snowflake shortcut for one column
SELECT customer_id, MAX_BY(city, updated_at) AS current_city
FROM customer_history
GROUP BY customer_id;

-- =====================================================
-- 11. % CONTRIBUTION and CUMULATIVE %
-- =====================================================
WITH c AS (
  SELECT customer_id, SUM(amount) AS revenue
  FROM orders GROUP BY customer_id
)
SELECT customer_id, revenue,
  ROUND(RATIO_TO_REPORT(revenue) OVER () * 100, 2)                     AS pct_of_total,
  ROUND(revenue / SUM(revenue) OVER () * 100, 2)                       AS pct_manual,
  ROUND(SUM(revenue) OVER (ORDER BY revenue DESC
          ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)
        / SUM(revenue) OVER () * 100, 2)                               AS cumulative_pct
FROM c
ORDER BY revenue DESC;

-- =====================================================
-- 12. DATE SPINE: show every date, 0 when no sales
-- ROW_NUMBER over SEQ4 guarantees no gaps in the sequence
-- =====================================================
WITH spine AS (
  SELECT DATEADD(day, ROW_NUMBER() OVER (ORDER BY SEQ4()) - 1, '2026-03-01'::DATE) AS dt
  FROM TABLE(GENERATOR(ROWCOUNT => 31))
)
SELECT s.dt, COALESCE(SUM(o.amount), 0) AS daily_sales
FROM spine s
LEFT JOIN orders o ON o.order_date = s.dt
GROUP BY s.dt
ORDER BY s.dt;

-- =====================================================
-- 13. MEDIAN / PERCENTILE per department
-- =====================================================
SELECT dept,
  MEDIAN(salary)                                           AS median_salary,
  PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY salary)      AS p50_interpolated,
  PERCENTILE_DISC(0.5) WITHIN GROUP (ORDER BY salary)      AS p50_actual_value,
  PERCENTILE_CONT(0.9) WITHIN GROUP (ORDER BY salary)      AS p90
FROM emp
GROUP BY dept;

-- =====================================================
-- 14. RECURSIVE CTE
-- =====================================================
-- Org hierarchy with level and path
WITH RECURSIVE org AS (
  SELECT emp_id, name, manager_id, 1 AS lvl, name::VARCHAR AS path
  FROM emp
  WHERE manager_id IS NULL
  UNION ALL
  SELECT e.emp_id, e.name, e.manager_id, o.lvl + 1, o.path || ' > ' || e.name
  FROM emp e
  JOIN org o ON e.manager_id = o.emp_id
)
SELECT * FROM org ORDER BY path;

-- Number series 1..10
WITH RECURSIVE n AS (
  SELECT 1 AS num
  UNION ALL
  SELECT num + 1 FROM n WHERE num < 10
)
SELECT num FROM n;

-- Snowflake also has CONNECT BY for hierarchies
SELECT emp_id, name, LEVEL AS lvl, SYS_CONNECT_BY_PATH(name, ' > ') AS path
FROM emp
START WITH manager_id IS NULL
CONNECT BY PRIOR emp_id = manager_id;

-- =====================================================
-- 15. SEMI-STRUCTURED: parse JSON and flatten arrays
-- =====================================================
SELECT
  payload:order_id::NUMBER          AS order_id,
  payload:customer.id::NUMBER       AS customer_id,
  payload:customer.name::VARCHAR    AS customer_name,
  i.index                           AS item_pos,
  i.value:sku::VARCHAR              AS sku,
  i.value:qty::NUMBER               AS qty,
  i.value:price::NUMBER(10,2)       AS price,
  qty * price                       AS line_total
FROM raw_json,
LATERAL FLATTEN(INPUT => payload:items) i
ORDER BY order_id, item_pos;

-- =====================================================
-- 16. MERGE: SCD Type 1 upsert and SCD Type 2 load
-- =====================================================
-- SCD1 (overwrite): run on a copy so the SCD2 demo still works
CREATE OR REPLACE TEMPORARY TABLE dim_customer_scd1 AS
SELECT customer_id, city FROM dim_customer;

MERGE INTO dim_customer_scd1 t
USING stg_customer s
  ON t.customer_id = s.customer_id
WHEN MATCHED AND t.city <> s.city THEN UPDATE SET t.city = s.city
WHEN NOT MATCHED THEN INSERT (customer_id, city) VALUES (s.customer_id, s.city);

SELECT * FROM dim_customer_scd1 ORDER BY customer_id;

-- SCD2 (keep history) in one MERGE:
-- changed rows appear twice in the source: once to expire (join key),
-- once with NULL join key so they fall into NOT MATCHED -> insert new version
MERGE INTO dim_customer t
USING (
  SELECT s.customer_id AS join_key, s.* FROM stg_customer s
  UNION ALL
  SELECT NULL, s.*
  FROM stg_customer s
  JOIN dim_customer d
    ON d.customer_id = s.customer_id AND d.is_current AND d.city <> s.city
) src
  ON t.customer_id = src.join_key AND t.is_current
WHEN MATCHED AND t.city <> src.city THEN
  UPDATE SET t.valid_to = CURRENT_TIMESTAMP()::TIMESTAMP_NTZ, t.is_current = FALSE
WHEN NOT MATCHED THEN
  INSERT (customer_id, city, valid_from, valid_to, is_current)
  VALUES (src.customer_id, src.city, CURRENT_TIMESTAMP()::TIMESTAMP_NTZ, NULL, TRUE);

SELECT * FROM dim_customer ORDER BY customer_id, valid_from;
