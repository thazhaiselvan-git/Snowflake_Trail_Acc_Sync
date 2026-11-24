# Semantic Model vs Semantic View in Snowflake

## 1. What is a Semantic Layer?
A semantic layer sits on top of raw tables and describes them in business terms:
- **Logical tables**: which physical tables are involved
- **Relationships**: how tables join (foreign key → primary key)
- **Dimensions**: attributes you group or filter by (region, product, date)
- **Facts**: row-level numeric values (amount, quantity)
- **Metrics**: aggregated business measures (total sales, average order value)
- **Synonyms and comments**: help Cortex Analyst map natural language to SQL

Both a semantic model and a semantic view express this layer. They differ in how it is stored and managed.

---

## 2. Semantic Model (the older approach)
- A **YAML file** uploaded to a Snowflake **stage** (e.g. `@my_stage/sales_model.yaml`).
- Cortex Analyst reads it by file path.
- It is **not a database object**: no object grants, no lineage, and it can't be queried with SQL.
- Versioning is manual, usually with git and re-uploading the file.

### Example YAML
```yaml
name: sales_model
tables:
  - name: orders
    base_table:
      database: SALES_DB
      schema: PUBLIC
      table: ORDERS
    primary_key:
      columns: [order_id]
    dimensions:
      - name: order_status
        expr: status
        data_type: VARCHAR
    time_dimensions:
      - name: order_date
        expr: order_date
        data_type: DATE
    facts:
      - name: order_amount
        expr: amount
        data_type: NUMBER
    metrics:
      - name: total_sales
        expr: SUM(amount)
relationships:
  - name: orders_to_customers
    left_table: orders
    right_table: customers
    relationship_columns:
      - left_column: customer_id
        right_column: customer_id
```

### Using it
```bash
# Cortex Analyst REST API request body (excerpt)
{"semantic_model_file": "@SALES_DB.PUBLIC.MY_STAGE/sales_model.yaml", "messages": [...]}
```

---

## 3. Semantic View (the current, recommended approach)
- A **native schema-level object** created with `CREATE SEMANTIC VIEW`.
- Governed with RBAC (`GRANT SELECT ON SEMANTIC VIEW ...`), ownership, sharing and Marketplace listings.
- Appears in the catalog and in lineage.
- **Queryable directly with SQL** using `SEMANTIC_VIEW(...)`.
- Used by Cortex Analyst, Cortex Agents and BI tools.

---

## 4. Comparison

| Aspect | Semantic Model | Semantic View |
|---|---|---|
| Form | YAML file on a stage | Native schema object |
| Created by | File upload | `CREATE SEMANTIC VIEW` DDL |
| Access control | Stage permissions | Object grants (RBAC) |
| Direct SQL query | No | Yes (`SEMANTIC_VIEW(...)`) |
| Lineage / catalog | No | Yes |
| Sharing / listings | No | Yes |
| Used by | Cortex Analyst | Cortex Analyst, Cortex Agents, SQL, BI tools |
| Status | Legacy | Recommended |

---

## 5. Semantic View Scenarios

### Scenario 1: Retail sales analytics
**Business need:** Analysts and executives ask "What were total sales by region last quarter?" in plain English.

```sql
CREATE OR REPLACE SEMANTIC VIEW SALES_DB.ANALYTICS.SALES_SV
  TABLES (
    orders    AS SALES_DB.PUBLIC.ORDERS    PRIMARY KEY (order_id)
              WITH SYNONYMS = ('sales', 'transactions')
              COMMENT = 'One row per customer order',
    customers AS SALES_DB.PUBLIC.CUSTOMERS PRIMARY KEY (customer_id)
              WITH SYNONYMS = ('clients', 'buyers'),
    products  AS SALES_DB.PUBLIC.PRODUCTS  PRIMARY KEY (product_id)
  )
  RELATIONSHIPS (
    orders_to_customers AS orders (customer_id) REFERENCES customers,
    orders_to_products  AS orders (product_id)  REFERENCES products
  )
  FACTS (
    orders.order_amount AS amount,
    orders.quantity     AS qty
  )
  DIMENSIONS (
    customers.region   AS region   WITH SYNONYMS = ('territory', 'area'),
    customers.segment  AS segment,
    products.category  AS category,
    orders.order_date  AS order_date
  )
  METRICS (
    orders.total_sales     AS SUM(orders.order_amount) WITH SYNONYMS = ('revenue'),
    orders.order_count     AS COUNT(orders.order_id),
    orders.avg_order_value AS AVG(orders.order_amount)
  )
  COMMENT = 'Retail sales semantic view';
```

**Query it with SQL:**
```sql
SELECT * FROM SEMANTIC_VIEW(
  SALES_DB.ANALYTICS.SALES_SV
  DIMENSIONS customers.region, products.category
  METRICS orders.total_sales, orders.order_count
  WHERE orders.order_date >= '2026-07-01'
)
ORDER BY total_sales DESC;
```

**Ask in natural language (Cortex Analyst):**
"Show revenue by territory for Q3" → Analyst maps *revenue* to `total_sales` and *territory* to `region`.

---

### Scenario 2: Finance / P&L reporting
**Business need:** One governed definition of "Gross Margin" so every team gets the same number.

```sql
CREATE OR REPLACE SEMANTIC VIEW FIN_DB.REPORTING.PNL_SV
  TABLES (
    gl   AS FIN_DB.CORE.GENERAL_LEDGER PRIMARY KEY (entry_id),
    acct AS FIN_DB.CORE.ACCOUNTS       PRIMARY KEY (account_id)
  )
  RELATIONSHIPS (
    gl_to_acct AS gl (account_id) REFERENCES acct
  )
  FACTS (
    gl.revenue_amt AS IFF(acct_type = 'REVENUE', amount, 0),
    gl.cogs_amt    AS IFF(acct_type = 'COGS',    amount, 0)
  )
  DIMENSIONS (
    gl.fiscal_month   AS fiscal_month,
    acct.business_unit AS business_unit
  )
  METRICS (
    gl.revenue      AS SUM(gl.revenue_amt),
    gl.cogs         AS SUM(gl.cogs_amt),
    gl.gross_margin AS SUM(gl.revenue_amt) - SUM(gl.cogs_amt),
    gl.gross_margin_pct AS DIV0(SUM(gl.revenue_amt) - SUM(gl.cogs_amt), SUM(gl.revenue_amt))
  );

-- Governance: only finance analysts can use it
GRANT SELECT ON SEMANTIC VIEW FIN_DB.REPORTING.PNL_SV TO ROLE FINANCE_ANALYST;
```

---

### Scenario 3: Customer support / operations KPIs
**Business need:** Support managers track ticket volume and resolution time with a Cortex Agent.

```sql
CREATE OR REPLACE SEMANTIC VIEW OPS_DB.SUPPORT.TICKETS_SV
  TABLES (
    tickets AS OPS_DB.SUPPORT.TICKETS PRIMARY KEY (ticket_id),
    agents  AS OPS_DB.SUPPORT.AGENTS  PRIMARY KEY (agent_id)
  )
  RELATIONSHIPS (
    tickets_to_agents AS tickets (agent_id) REFERENCES agents
  )
  FACTS (
    tickets.resolution_hours AS DATEDIFF('hour', created_at, resolved_at)
  )
  DIMENSIONS (
    tickets.priority AS priority,
    tickets.channel  AS channel WITH SYNONYMS = ('source'),
    agents.team      AS team,
    tickets.created_date AS TO_DATE(created_at)
  )
  METRICS (
    tickets.ticket_count         AS COUNT(tickets.ticket_id),
    tickets.avg_resolution_hours AS AVG(tickets.resolution_hours)
  );
```
Attach this semantic view to a Cortex Agent as a Cortex Analyst tool. Users can then ask: *"Which team had the slowest resolution time for high-priority tickets last month?"*

---

### Scenario 4: Sharing data products externally
**Business need:** A data provider shares curated metrics with partners through a Marketplace listing.
- Build a semantic view over the shared tables.
- Add it to the share or listing so consumers get business-ready metrics plus AI-ready natural-language querying.
- This isn't possible with a YAML semantic model, because a file on a stage can't be shared as an object.

---

### Scenario 5: Migrating a YAML semantic model to a semantic view
**Business need:** Move an existing Cortex Analyst YAML model to a governed object.
```sql
CALL SYSTEM$CREATE_SEMANTIC_VIEW_FROM_YAML(
  'SALES_DB.ANALYTICS',
  $$ <paste YAML content here> $$
);
```
Afterwards, point Cortex Analyst and Agents at `SALES_DB.ANALYTICS.<view_name>` instead of the stage file.

---

## 6. Useful Commands
```sql
SHOW SEMANTIC VIEWS IN SCHEMA SALES_DB.ANALYTICS;
DESCRIBE SEMANTIC VIEW SALES_DB.ANALYTICS.SALES_SV;
SHOW SEMANTIC METRICS    IN SEMANTIC VIEW SALES_DB.ANALYTICS.SALES_SV;
SHOW SEMANTIC DIMENSIONS IN SEMANTIC VIEW SALES_DB.ANALYTICS.SALES_SV;
SELECT GET_DDL('SEMANTIC_VIEW', 'SALES_DB.ANALYTICS.SALES_SV');
DROP SEMANTIC VIEW IF EXISTS SALES_DB.ANALYTICS.SALES_SV;
```

## 7. Best Practices
1. Add **synonyms** and **comments** generously, since they directly improve Cortex Analyst accuracy.
2. Define **primary keys** and **relationships** so joins are generated correctly.
3. Put complex business logic in **metrics** once, not in every report.
4. Use **RBAC grants** to control who can query each semantic view.
5. Keep the semantic view DDL in git, or manage it with dbt or DCM, for CI/CD.
6. Prefer semantic views over YAML models for all new work.

> Note: table, column and database names in these examples (SALES_DB, FIN_DB, OPS_DB) are illustrative. Replace them with your own objects.

---

## 8. Real Example: SF_SCENARIO_BASED_LEARNING (created and tested)

Source tables: `SF_SCENARIO_BASED_LEARNING.DATA_QUALITY.CUSTOMERS` and `.ORDERS`

```sql
CREATE OR REPLACE SEMANTIC VIEW SF_SCENARIO_BASED_LEARNING.DATA_QUALITY.CUSTOMER_ORDERS_SV
  TABLES (
    customers AS SF_SCENARIO_BASED_LEARNING.DATA_QUALITY.CUSTOMERS PRIMARY KEY (customer_id)
      WITH SYNONYMS = ('clients','buyers') COMMENT = 'Customer master data',
    orders AS SF_SCENARIO_BASED_LEARNING.DATA_QUALITY.ORDERS PRIMARY KEY (order_id)
      WITH SYNONYMS = ('sales','transactions') COMMENT = 'One row per order'
  )
  RELATIONSHIPS (
    orders_to_customers AS orders (customer_id) REFERENCES customers
  )
  FACTS (
    orders.order_amount AS order_amount COMMENT = 'Order value'
  )
  DIMENSIONS (
    customers.city AS city,
    customers.state AS state WITH SYNONYMS = ('region'),
    customers.customer_name AS first_name || ' ' || last_name,
    customers.signup_date AS created_at,
    orders.order_date AS order_date,
    orders.order_status AS order_status WITH SYNONYMS = ('status'),
    orders.order_month AS DATE_TRUNC('month', order_date)
  )
  METRICS (
    orders.total_sales AS SUM(orders.order_amount) WITH SYNONYMS = ('revenue'),
    orders.order_count AS COUNT(orders.order_id),
    orders.avg_order_value AS AVG(orders.order_amount),
    customers.customer_count AS COUNT(DISTINCT customers.customer_id)
  )
  COMMENT = 'Customer & order analytics demo';

-- Query: sales by state and order status
SELECT * FROM SEMANTIC_VIEW(SF_SCENARIO_BASED_LEARNING.DATA_QUALITY.CUSTOMER_ORDERS_SV
  DIMENSIONS customers.state, orders.order_status
  METRICS orders.total_sales, orders.order_count, orders.avg_order_value)
ORDER BY total_sales DESC NULLS LAST;
```

Sample result (top rows):

| STATE | ORDER_STATUS | TOTAL_SALES | ORDER_COUNT | AVG_ORDER_VALUE |
|---|---|---|---|---|
| TX | DELIVERED | 15588 | 16 | 974.25 |
| TX | SHIPPED | 15287 | 15 | 1019.13 |
| TX | RETURNED | 14598 | 19 | 768.32 |

Natural-language questions Cortex Analyst could answer with this view:
- "What is the revenue by region?"
- "How many returned orders per month?"
- "Top 5 clients by total sales"
