-- SQL INTERVIEW PRACTICE: SNOWFLAKE
-- Run this script from top to bottom in a Snowflake worksheet.
-- Select a database and schema before running it.
-- All tables are TRANSIENT and will be removed when your session ends.

-- ============================================================
-- PART 1: DDL — CREATE SAMPLE TABLES
-- ============================================================
USE SCHEMA SF_SCENARIO_BASED_LEARNING.SQL_LEARNING_SCHEMA;
CREATE TRANSIENT TABLE departments (
    department_id   NUMBER,
    department_name VARCHAR
);

CREATE TRANSIENT TABLE employees (
    employee_id   NUMBER,
    employee_name VARCHAR,
    department_id NUMBER,
    manager_id    NUMBER,
    salary        NUMBER(10, 2),
    hire_date     DATE
);

CREATE TRANSIENT TABLE customers_Bkp (
    customer_id   NUMBER,
    customer_name VARCHAR
);

CREATE TRANSIENT TABLE orders_Bkp (
    order_id    NUMBER,
    customer_id NUMBER,
    order_date  DATE,
    amount      NUMBER(10, 2),
    status      VARCHAR
);

CREATE TRANSIENT TABLE signups (
    signup_id NUMBER,
    email     VARCHAR,
    created_at TIMESTAMP_NTZ
);

-- ============================================================
-- PART 2: DML — INSERT SAMPLE DATA
-- ============================================================

INSERT INTO departments (department_id, department_name) VALUES
    (10, 'Engineering'),
    (20, 'Sales'),
    (30, 'Marketing'),
    (40, 'Research');

INSERT INTO employees
    (employee_id, employee_name, department_id, manager_id, salary, hire_date)
VALUES
    (101, 'Alice', 10, NULL, 120000.00, '2018-03-15'),
    (102, 'Bob',   10, 101,  90000.00, '2020-06-01'),
    (103, 'Cara',  10, 101,  90000.00, '2021-01-20'),
    (104, 'Dan',   10, 102,  70000.00, '2022-09-10'),
    (201, 'Eva',   20, NULL, 110000.00, '2017-11-05'),
    (202, 'Finn',  20, 201,  80000.00, '2020-02-14'),
    (203, 'Gia',   20, 201,  75000.00, '2023-04-03'),
    (301, 'Hugo',  30, NULL,  95000.00, '2019-08-22'),
    (302, 'Ivy',   30, 301,  65000.00, '2022-12-01');

INSERT INTO customers_Bkp (customer_id, customer_name) VALUES
    (1, 'Acme Corp'),
    (2, 'Blue Sky Ltd'),
    (3, 'Cedar Works'),
    (4, 'Delta Services'),
    (5, 'Evergreen Inc'),
    (6, 'Foxglove Group');

INSERT INTO orders_Bkp (order_id, customer_id, order_date, amount, status) VALUES
    (1001, 1, '2025-01-10', 100.00, 'completed'),
    (1002, 1, '2025-01-20', 150.00, 'completed'),
    (1003, 1, '2025-02-05', 200.00, 'completed'),
    (1004, 2, '2025-01-12',  80.00, 'completed'),
    (1005, 2, '2025-02-14', 120.00, 'pending'),
    (1006, 3, '2025-02-15', 300.00, 'completed'),
    (1007, 3, '2025-03-01',  50.00, 'cancelled'),
    (1008, 4, '2025-03-03', 400.00, 'completed'),
    (1009, 6, '2025-03-10', 250.00, 'pending');

INSERT INTO signups (signup_id, email, created_at) VALUES
    (1, 'alex@example.com', '2025-01-01 09:00:00'),
    (2, 'blair@example.com', '2025-01-03 10:30:00'),
    (3, 'alex@example.com', '2025-02-10 14:15:00'),
    (4, 'casey@example.com', '2025-02-12 08:45:00'),
    (5, 'blair@example.com', '2025-03-01 12:00:00');

-- ============================================================
-- PART 3: INTERVIEW SCENARIOS
-- Each section includes a question, runnable answer, and explanation.
-- ============================================================


-- ------------------------------------------------------------
-- SCENARIO 1: Employees earning above their department average
-- ------------------------------------------------------------
-- Question:
-- Find employees whose salary is greater than the average salary
-- in their own department.

 SELECT DEPARTMENT_ID,AVG(salary)
FROM employees
GROUP BY DEPARTMENT_ID;

 SELECT *
FROM employees;

SELECT
    e.employee_id,
    e.employee_name,
    e.department_id,
    e.salary
FROM employees AS e
WHERE e.salary > (
    SELECT AVG(e2.salary)
    FROM employees AS e2
    WHERE e2.department_id = e.department_id
)
ORDER BY e.department_id, e.salary DESC;

-- Explanation:
-- The subquery calculates an average for the department of each outer
-- employee row. It is a correlated subquery because it refers to e.department_id.


-- ------------------------------------------------------------
-- SCENARIO 2: Top 3 salary ranks in each department, including ties
-- ------------------------------------------------------------
-- Question:
-- Return employees whose salary rank is in the top three for their department.
-- Employees tied on salary share a rank.

WITH ranked_employees AS (
    SELECT
        employee_id,
        employee_name,
        department_id,
        salary,
        DENSE_RANK() OVER (
            PARTITION BY department_id
            ORDER BY salary DESC
        ) AS salary_rank
    FROM employees
)
SELECT
    employee_id,
    employee_name,
    department_id,
    salary,
    salary_rank
FROM ranked_employees
WHERE salary_rank <= 3
ORDER BY department_id, salary DESC, employee_id;

-- Explanation:
-- DENSE_RANK gives equal salaries the same rank and does not leave gaps.
-- This can return more than three employees in a department if salaries tie.
-- Use ROW_NUMBER instead if the requirement is exactly three rows per department.


-- ------------------------------------------------------------
-- SCENARIO 3: customers_Bkp who have never placed an order
-- ------------------------------------------------------------
-- Question:
-- Find customers_Bkp with no matching row in the orders_Bkp table.

SELECT
    c.customer_id,
    c.customer_name
FROM customers_Bkp AS c
LEFT JOIN orders_Bkp AS o
    ON o.customer_id = c.customer_id
WHERE o.order_id IS NULL
ORDER BY c.customer_id;

-- Explanation:
-- LEFT JOIN retains every customer. For customers_Bkp without an order,
-- o.order_id is NULL, so the WHERE clause keeps only those customers_Bkp.


-- ------------------------------------------------------------
-- SCENARIO 4: Monthly revenue from completed orders_Bkp
-- ------------------------------------------------------------
-- Question:
-- Calculate completed-order revenue by month.

SELECT
    DATE_TRUNC('MONTH', order_date)::DATE AS order_month,
    SUM(amount) AS monthly_revenue
FROM orders_Bkp
WHERE status = 'completed'
GROUP BY DATE_TRUNC('MONTH', order_date)::DATE
ORDER BY order_month;

-- Explanation:
-- DATE_TRUNC groups dates into calendar months, and SUM adds completed
-- order amounts within each month.


-- ------------------------------------------------------------
-- SCENARIO 5: Second-highest distinct salary
-- ------------------------------------------------------------
-- Question:
-- Find the second-highest distinct salary in the company.

WITH ranked_salaries AS (
    SELECT
        salary,
        DENSE_RANK() OVER (ORDER BY salary DESC) AS salary_rank
    FROM employees
)
SELECT DISTINCT salary
FROM ranked_salaries
WHERE salary_rank = 2;

-- Explanation:
-- DENSE_RANK ranks distinct salary values. If multiple employees earn
-- the second-highest salary, the query returns that salary once.
-- To return employee details too, rank employees and filter on salary_rank = 2.



-- ------------------------------------------------------------
-- SCENARIO 6: Running completed-order total for each customer
-- ------------------------------------------------------------
-- Question:
-- Show each completed order and the customer's cumulative total up to it.

SELECT
    customer_id,
    order_id,
    order_date,
    amount,
    SUM(amount) OVER (
        PARTITION BY customer_id
        ORDER BY order_date, order_id
        ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
    ) AS running_total
FROM orders_Bkp
WHERE status = 'completed'
ORDER BY customer_id, order_date, order_id;

-- Explanation:
-- The window function accumulates amounts for each customer.
-- order_id makes the ordering deterministic when two orders_Bkp share a date.


-- ------------------------------------------------------------
-- SCENARIO 7: Keep only the most recent signup for each email
-- ------------------------------------------------------------
-- Question:
-- Return the newest signup record for each email address.

WITH ranked_signups AS (
    SELECT
        signup_id,
        email,
        created_at,
        ROW_NUMBER() OVER (
            PARTITION BY email
            ORDER BY created_at DESC, signup_id DESC
        ) AS row_num
    FROM signups
)
SELECT
    signup_id,
    email,
    created_at
FROM ranked_signups
WHERE row_num = 1
ORDER BY email;

-- Explanation:
-- ROW_NUMBER numbers each email's rows from newest to oldest.
-- The extra signup_id sort is a tie-breaker if timestamps match.


-- ------------------------------------------------------------
-- SCENARIO 8: Employee count by department, including empty departments
-- ------------------------------------------------------------
-- Question:
-- Show every department and its employee count, including departments
-- that have no employees.

SELECT * FROM departments;

SELECT
    d.department_id,
    d.department_name,
    COUNT(e.employee_id) AS employee_count
FROM departments AS d
LEFT JOIN employees AS e
    ON e.department_id = d.department_id
GROUP BY d.department_id, d.department_name
ORDER BY d.department_id;

-- Explanation:
-- LEFT JOIN keeps departments with no employees. COUNT(employee_id) returns
-- zero for those departments; COUNT(*) would count the department row itself.


-- ------------------------------------------------------------
-- SCENARIO 9: Completed-order revenue per customer, including zero revenue
-- ------------------------------------------------------------
-- Question:
-- Show every customer and their completed-order total. customers_Bkp with no
-- completed orders_Bkp should show zero.

SELECT
    c.customer_id,
    c.customer_name,
    COALESCE(SUM(IFF(o.status = 'completed', o.amount, 0)), 0)
        AS completed_revenue
FROM customers_Bkp AS c
LEFT JOIN orders_Bkp AS o
    ON o.customer_id = c.customer_id
GROUP BY c.customer_id, c.customer_name
ORDER BY completed_revenue DESC, c.customer_id;

-- Explanation:
-- COALESCE turns a NULL total into zero. The conditional IFF counts only
-- completed orders_Bkp. Keeping the status condition out of WHERE preserves
-- customers_Bkp who have no completed orders_Bkp.


-- ------------------------------------------------------------
-- SCENARIO 10: Rank orders_Bkp by amount within each customer
-- ------------------------------------------------------------
-- Question:
-- Rank each customer's orders_Bkp from largest to smallest.

SELECT
    customer_id,
    order_id,
    amount,
    status,
    RANK() OVER (
        PARTITION BY customer_id
        ORDER BY amount DESC
    ) AS amount_rank
FROM orders_Bkp
ORDER BY customer_id, amount_rank, order_id;

-- Explanation:
-- RANK assigns equal amounts the same rank and leaves gaps after ties.
-- Use DENSE_RANK if you do not want gaps, or ROW_NUMBER for unique row numbers.


-- ------------------------------------------------------------
-- SCENARIO 11: Each employee's share of department payroll
-- ------------------------------------------------------------
-- Question:
-- Calculate each employee's percentage of their department's total salary.

SELECT
    employee_id,
    employee_name,
    department_id,
    salary,
    ROUND(
        100.0 * salary
        / NULLIF(SUM(salary) OVER (PARTITION BY department_id), 0),
        2
    ) AS department_payroll_percentage
FROM employees
ORDER BY department_id, salary DESC;

-- Explanation:
-- The window SUM calculates total salary per department without collapsing
-- employee rows. NULLIF protects against division by zero.


-- ------------------------------------------------------------
-- SCENARIO 12: Find duplicate email addresses
-- ------------------------------------------------------------
-- Question:
-- Find email addresses that appear more than once and show their counts.

SELECT
    email,
    COUNT(*) AS signup_count
FROM signups
GROUP BY email
HAVING COUNT(*) > 1
ORDER BY signup_count DESC, email;

-- Explanation:
-- GROUP BY forms one group per email. HAVING filters the grouped results,
-- much like WHERE filters individual rows.


-- ------------------------------------------------------------
-- SCENARIO 13: Show each employee and their manager
-- ------------------------------------------------------------
-- Question:
-- Return each employee's name alongside their manager's name.

SELECT
    e.employee_id,
    e.employee_name,
    m.employee_name AS manager_name
FROM employees AS e
LEFT JOIN employees AS m
    ON e.manager_id = m.employee_id
ORDER BY e.employee_id;

-- Explanation:
-- This is a self-join: employees is used once for the employee and again
-- for the manager. LEFT JOIN retains top-level employees with no manager.


-- ------------------------------------------------------------
-- SCENARIO 14: orders_Bkp larger than the overall average order amount
-- ------------------------------------------------------------
-- Question:
-- Find orders_Bkp whose amount is greater than the average amount of all orders_Bkp.

SELECT
    order_id,
    customer_id,
    order_date,
    amount,
    status
FROM orders_Bkp
WHERE amount > (
    SELECT AVG(amount)
    FROM orders_Bkp
)
ORDER BY amount DESC;

-- Explanation:
-- The scalar subquery returns one overall average value. The outer query
-- compares every order amount against that value.


-- ------------------------------------------------------------
-- SCENARIO 15: Month-over-month completed revenue change
-- ------------------------------------------------------------
-- Question:
-- Show monthly completed revenue and the difference from the previous
-- month with completed revenue.

WITH monthly_revenue AS (
    SELECT
        DATE_TRUNC('MONTH', order_date)::DATE AS order_month,
        SUM(amount) AS revenue
    FROM orders_Bkp
    WHERE status = 'completed'
    GROUP BY DATE_TRUNC('MONTH', order_date)::DATE
),
revenue_with_previous_month AS (
    SELECT
        order_month,
        revenue,
        LAG(revenue) OVER (ORDER BY order_month) AS previous_month_revenue
    FROM monthly_revenue
)
SELECT
    order_month,
    revenue,
    previous_month_revenue,
    revenue - previous_month_revenue AS revenue_change
FROM revenue_with_previous_month
ORDER BY order_month;

-- Explanation:
-- LAG reads the revenue value from the previous row in month order.
-- The first month has no previous month, so its previous value and change
-- are NULL. Months with no completed orders_Bkp are not generated by this query.


-- ------------------------------------------------------------
-- SCENARIO 16: Cumulative completed revenue by month
-- ------------------------------------------------------------
-- Question:
-- Calculate monthly completed revenue and the cumulative revenue total.

WITH monthly_revenue AS (
    SELECT
        DATE_TRUNC('MONTH', order_date)::DATE AS order_month,
        SUM(amount) AS revenue
    FROM orders_Bkp
    WHERE status = 'completed'
    GROUP BY DATE_TRUNC('MONTH', order_date)::DATE
)
SELECT
    order_month,
    revenue,
    SUM(revenue) OVER (
        ORDER BY order_month
        ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
    ) AS cumulative_revenue
FROM monthly_revenue
ORDER BY order_month;

-- Explanation:
-- The windowed SUM adds each month's revenue to all prior months'
-- revenue, while retaining one output row per month.

-- ============================================================
-- END OF SCRIPT
-- ============================================================