# Snowflake Cortex AI – Complete Guide
## Cortex Search · Cortex Analyst · Cortex Agents
### Concepts · Real-time Scenario · Hands-on SQL · Interview Prep

> Run the SQL step by step in a Snowsight worksheet. Syntax follows current Snowflake docs. Features change often, so check `docs.snowflake.com` for the latest parameters and region/model availability.

---

## 0. The Big Picture

| Component | What it does | Data type | Answers questions like |
|---|---|---|---|
| **Cortex Search** | Hybrid (vector + keyword) search with semantic reranking, used for RAG | **Unstructured** text (docs, tickets, PDFs, transcripts) | "What is our refund policy for damaged items?" |
| **Cortex Analyst** | Text-to-SQL using a **semantic model/view** | **Structured** tables | "What was total revenue by region last quarter?" |
| **Cortex Agents** | Orchestrator: plans, picks tools (Search, Analyst, custom tools), reflects, answers | Both | "Which region had the most returns last month, and what do customers complain about?" |

```
                 User question
                       │
                ┌──────▼──────┐
                │ Cortex Agent │  ← LLM orchestration (plan → tool use → reflect → respond)
                └──┬───────┬──┘
        structured │       │ unstructured
        ┌──────────▼─┐   ┌─▼─────────────┐
        │  Analyst   │   │ Cortex Search │
        │ (Text2SQL) │   │   (RAG)       │
        └─────┬──────┘   └──────┬────────┘
     Semantic View          Search Service
        │                        │
   Tables (orders…)       Text (tickets, docs)
```

**One-line memory hook:** *Search = find text, Analyst = write SQL, Agent = decide which one to use and combine the results.*

---

## 1. Real-Time Scenario Used Throughout

**Company:** "ShopSmart", an e-commerce retailer.

- **Structured data:** `CUSTOMERS`, `PRODUCTS`, `ORDERS` → Analyst
- **Unstructured data:** `SUPPORT_TICKETS` (free-text complaints), `POLICY_DOCS` → Search
- **Goal:** a support/business assistant that answers revenue questions and policy/complaint questions in one chat → Agent

---

## 2. Setup (Database, Warehouse, Role, Sample Data)

```sql
USE ROLE ACCOUNTADMIN;   -- or a role with CREATE DATABASE rights

CREATE OR REPLACE WAREHOUSE CORTEX_WH WAREHOUSE_SIZE = XSMALL AUTO_SUSPEND = 60;
CREATE OR REPLACE DATABASE CORTEX_DEMO;
CREATE OR REPLACE SCHEMA CORTEX_DEMO.SHOP;
USE SCHEMA CORTEX_DEMO.SHOP;
USE WAREHOUSE CORTEX_WH;

-- Required to use Cortex LLM features
GRANT DATABASE ROLE SNOWFLAKE.CORTEX_USER TO ROLE ACCOUNTADMIN;

-- If your region lacks a model, allow cross-region inference
-- ALTER ACCOUNT SET CORTEX_ENABLED_CROSS_REGION = 'ANY_REGION';
```

### 2.1 Structured tables

```sql
CREATE OR REPLACE TABLE CUSTOMERS (
  CUSTOMER_ID INT, CUSTOMER_NAME STRING, REGION STRING, SEGMENT STRING, SIGNUP_DATE DATE);

INSERT INTO CUSTOMERS VALUES
 (1,'Asha Rao','South','Consumer','2024-01-10'),
 (2,'John Smith','North','Corporate','2023-11-05'),
 (3,'Priya Nair','South','Corporate','2024-03-22'),
 (4,'Mike Chen','West','Consumer','2024-02-14'),
 (5,'Sara Ali','East','Home Office','2023-09-30'),
 (6,'Ravi Kumar','North','Consumer','2024-05-01');

CREATE OR REPLACE TABLE PRODUCTS (
  PRODUCT_ID INT, PRODUCT_NAME STRING, CATEGORY STRING, UNIT_PRICE NUMBER(10,2));

INSERT INTO PRODUCTS VALUES
 (101,'Wireless Earbuds','Electronics',59.99),
 (102,'Smart Watch','Electronics',199.00),
 (103,'Running Shoes','Apparel',89.50),
 (104,'Coffee Maker','Home',120.00),
 (105,'Yoga Mat','Fitness',25.00);

CREATE OR REPLACE TABLE ORDERS (
  ORDER_ID INT, CUSTOMER_ID INT, PRODUCT_ID INT, ORDER_DATE DATE,
  QUANTITY INT, AMOUNT NUMBER(10,2), STATUS STRING);  -- STATUS: DELIVERED / RETURNED / CANCELLED

INSERT INTO ORDERS VALUES
 (1001,1,101,'2026-08-03',2,119.98,'DELIVERED'),
 (1002,2,102,'2026-08-15',1,199.00,'RETURNED'),
 (1003,3,104,'2026-09-02',1,120.00,'DELIVERED'),
 (1004,4,103,'2026-09-10',2,179.00,'DELIVERED'),
 (1005,5,105,'2026-09-21',4,100.00,'CANCELLED'),
 (1006,6,102,'2026-10-05',1,199.00,'RETURNED'),
 (1007,1,104,'2026-10-12',1,120.00,'DELIVERED'),
 (1008,2,101,'2026-10-20',3,179.97,'DELIVERED'),
 (1009,3,102,'2026-10-28',1,199.00,'RETURNED'),
 (1010,4,105,'2026-11-02',2,50.00,'DELIVERED');
```

### 2.2 Unstructured tables

```sql
CREATE OR REPLACE TABLE SUPPORT_TICKETS (
  TICKET_ID INT, CUSTOMER_ID INT, PRODUCT_ID INT, REGION STRING,
  CREATED_AT DATE, TICKET_TEXT STRING);

INSERT INTO SUPPORT_TICKETS VALUES
 (1,2,102,'North','2026-08-18','The smart watch battery drains within 4 hours. I want a refund.'),
 (2,6,102,'North','2026-10-07','Smart watch screen flickers and the strap broke after a week.'),
 (3,3,102,'South','2026-10-30','Watch does not sync with my Android phone, returning it.'),
 (4,1,101,'South','2026-08-10','Earbuds are great but the left one is slightly quieter.'),
 (5,4,103,'West','2026-09-15','Shoes arrived late, delivery took 12 days.'),
 (6,5,105,'East','2026-09-22','Cancelled the yoga mat order because shipping cost was too high.');

CREATE OR REPLACE TABLE POLICY_DOCS (DOC_ID INT, TITLE STRING, CONTENT STRING);

INSERT INTO POLICY_DOCS VALUES
 (1,'Return Policy','Items can be returned within 30 days of delivery. Electronics must be in original packaging. Damaged or defective items get a full refund including shipping.'),
 (2,'Shipping Policy','Standard shipping takes 3-7 business days. Orders above $100 ship free. Express shipping costs $15.'),
 (3,'Warranty Policy','Electronics carry a 1-year manufacturer warranty covering battery and screen defects. Physical damage is not covered.');
```

> **Real PDFs?** Load them into a stage and parse with `SNOWFLAKE.CORTEX.PARSE_DOCUMENT` (or `AI_PARSE_DOCUMENT`), then chunk with `SNOWFLAKE.CORTEX.SPLIT_TEXT_RECURSIVE_CHARACTER` before indexing. See section 3.6.

---

## 3. Cortex Search

### 3.1 Concept
- A managed **search service** over a text column. Snowflake handles embeddings, the index, refreshes and serving.
- **Hybrid retrieval:** vector (semantic) search plus keyword (lexical) search, followed by **semantic reranking**.
- Built mainly for **RAG** (Retrieval Augmented Generation): retrieve relevant chunks, then pass them to an LLM to generate a grounded answer.
- Stays fresh automatically through **TARGET_LAG** (incremental refresh, like dynamic tables).
- **ATTRIBUTES** columns can be used as **filters** (e.g., region = 'North').

### 3.2 Create the services

```sql
CREATE OR REPLACE CORTEX SEARCH SERVICE TICKET_SEARCH
  ON TICKET_TEXT                       -- column that gets searched
  ATTRIBUTES REGION, PRODUCT_ID        -- filterable columns
  WAREHOUSE = CORTEX_WH
  TARGET_LAG = '1 hour'                -- freshness
  EMBEDDING_MODEL = 'snowflake-arctic-embed-m-v1.5'   -- optional
AS (
  SELECT TICKET_ID, TICKET_TEXT, REGION, PRODUCT_ID, CUSTOMER_ID, CREATED_AT
  FROM SUPPORT_TICKETS
);

CREATE OR REPLACE CORTEX SEARCH SERVICE POLICY_SEARCH
  ON CONTENT
  ATTRIBUTES TITLE
  WAREHOUSE = CORTEX_WH
  TARGET_LAG = '1 day'
AS (SELECT DOC_ID, TITLE, CONTENT FROM POLICY_DOCS);

SHOW CORTEX SEARCH SERVICES;
DESCRIBE CORTEX SEARCH SERVICE TICKET_SEARCH;
```

### 3.3 Query it (SQL)

```sql
-- Semantic query: none of these exact words appear in the tickets
SELECT PARSE_JSON(
  SNOWFLAKE.CORTEX.SEARCH_PREVIEW(
    'CORTEX_DEMO.SHOP.TICKET_SEARCH',
    '{"query": "wearable device power problems",
      "columns": ["TICKET_ID","TICKET_TEXT","REGION"],
      "limit": 3}'
  ))['results'] AS RESULTS;

-- With a filter
SELECT PARSE_JSON(
  SNOWFLAKE.CORTEX.SEARCH_PREVIEW(
    'CORTEX_DEMO.SHOP.TICKET_SEARCH',
    '{"query": "watch issues",
      "columns": ["TICKET_TEXT","REGION"],
      "filter": {"@eq": {"REGION": "North"}},
      "limit": 5}'
  ))['results'] AS RESULTS;
```
Filter operators: `@eq`, `@contains` (arrays), `@gte`, `@lte`, `@and`, `@or`, `@not`.

### 3.4 Build RAG: Search + LLM

```sql
WITH ctx AS (
  SELECT PARSE_JSON(SNOWFLAKE.CORTEX.SEARCH_PREVIEW(
    'CORTEX_DEMO.SHOP.POLICY_SEARCH',
    '{"query":"Can I return a smart watch with a battery defect?","columns":["TITLE","CONTENT"],"limit":3}'
  ))['results'] AS r
)
SELECT SNOWFLAKE.CORTEX.COMPLETE(
  'claude-3-5-sonnet',   -- or 'mistral-large2', 'llama3.1-70b', etc. (region-dependent)
  'Answer ONLY using this context. If unknown, say so.\nContext: ' || r::STRING ||
  '\nQuestion: Can I return a smart watch with a battery defect?'
) AS ANSWER
FROM ctx;
```
Expected answer: yes. The item is within the 30-day return window, it's defective so the refund is full, and the warranty covers battery defects for 1 year.

### 3.5 Query from Python / REST
```python
from snowflake.core import Root
from snowflake.snowpark import Session
session = Session.builder.getOrCreate()
svc = (Root(session).databases["CORTEX_DEMO"].schemas["SHOP"]
       .cortex_search_services["TICKET_SEARCH"])
resp = svc.search(query="screen problems", columns=["TICKET_TEXT","REGION"], limit=3)
print(resp.to_json())
```
REST: `POST /api/v2/databases/{db}/schemas/{schema}/cortex-search-services/{name}:query`

### 3.6 PDF pipeline (production pattern)
```sql
CREATE OR REPLACE STAGE DOCS_STAGE DIRECTORY = (ENABLE = TRUE) ENCRYPTION = (TYPE='SNOWFLAKE_SSE');
-- upload PDFs to @DOCS_STAGE via Snowsight

CREATE OR REPLACE TABLE DOC_CHUNKS AS
WITH parsed AS (
  SELECT RELATIVE_PATH,
         SNOWFLAKE.CORTEX.PARSE_DOCUMENT(@DOCS_STAGE, RELATIVE_PATH, {'mode':'LAYOUT'}):content::STRING AS TXT
  FROM DIRECTORY(@DOCS_STAGE)
)
SELECT RELATIVE_PATH, c.value::STRING AS CHUNK
FROM parsed,
LATERAL FLATTEN(SNOWFLAKE.CORTEX.SPLIT_TEXT_RECURSIVE_CHARACTER(TXT,'markdown',1500,200)) c;
-- then CREATE CORTEX SEARCH SERVICE ... ON CHUNK AS (SELECT * FROM DOC_CHUNKS)
```

### 3.7 More real-world Search scenarios
| Industry | Use case |
|---|---|
| HR | Employee policy chatbot (leave, benefits) |
| Banking | Search KYC/compliance manuals |
| Healthcare | Search clinical notes (with governance) |
| Manufacturing | Search maintenance logs for "similar failure" |
| Retail | Product catalog semantic search ("comfortable shoes for marathon") |
| IT | Incident/RCA knowledge base |

---

## 4. Cortex Analyst

### 4.1 Concept
- **Natural language → SQL** over structured data. It generates the SQL, runs it, and returns the SQL, the results and an explanation.
- Accuracy comes from a **semantic model** that describes business meaning: tables, dimensions, time dimensions, facts, metrics, relationships, synonyms and **verified queries**.
- The model is defined as either:
  - a **Semantic View** (native schema object, recommended), or
  - a **semantic model YAML file** on a stage (older approach).
- Accessed through the **REST API** (`/api/v2/cortex/analyst/message`), Snowflake Intelligence, Agents, or Streamlit apps.
- Asks for clarification when a question is ambiguous and suggests alternative questions.

### 4.2 Create a semantic view

```sql
CREATE OR REPLACE SEMANTIC VIEW CORTEX_DEMO.SHOP.SALES_SV
  TABLES (
    customers AS CORTEX_DEMO.SHOP.CUSTOMERS PRIMARY KEY (CUSTOMER_ID)
      WITH SYNONYMS = ('clients','buyers') COMMENT = 'Customer master',
    products  AS CORTEX_DEMO.SHOP.PRODUCTS  PRIMARY KEY (PRODUCT_ID)
      COMMENT = 'Product catalog',
    orders    AS CORTEX_DEMO.SHOP.ORDERS    PRIMARY KEY (ORDER_ID)
      COMMENT = 'One row per order line'
  )
  RELATIONSHIPS (
    orders_to_customers AS orders (CUSTOMER_ID) REFERENCES customers,
    orders_to_products  AS orders (PRODUCT_ID)  REFERENCES products
  )
  FACTS (
    orders.order_amount AS AMOUNT   COMMENT = 'Order value in USD',
    orders.order_qty    AS QUANTITY
  )
  DIMENSIONS (
    customers.customer_name AS CUSTOMER_NAME,
    customers.region        AS REGION  WITH SYNONYMS = ('area','zone'),
    customers.segment       AS SEGMENT,
    products.product_name   AS PRODUCT_NAME,
    products.category       AS CATEGORY,
    orders.order_date       AS ORDER_DATE,
    orders.order_month      AS DATE_TRUNC('MONTH', ORDER_DATE),
    orders.status           AS STATUS  COMMENT = 'DELIVERED, RETURNED or CANCELLED'
  )
  METRICS (
    orders.total_revenue AS SUM(orders.order_amount) WITH SYNONYMS = ('sales','revenue'),
    orders.order_count   AS COUNT(orders.ORDER_ID),
    orders.return_count  AS COUNT_IF(orders.STATUS = 'RETURNED'),
    orders.avg_order_value AS AVG(orders.order_amount)
  )
  COMMENT = 'ShopSmart sales semantic view';

SHOW SEMANTIC VIEWS;
DESCRIBE SEMANTIC VIEW SALES_SV;
```

### 4.3 Query the semantic view directly with SQL
```sql
SELECT * FROM SEMANTIC_VIEW(
  CORTEX_DEMO.SHOP.SALES_SV
  DIMENSIONS customers.region
  METRICS orders.total_revenue, orders.return_count
) ORDER BY total_revenue DESC;
```

### 4.4 Ask in natural language (Analyst REST API, Python)
```python
import requests, json
# Inside Snowflake (Streamlit/Notebook) use _snowflake.send_snow_api_request instead.
resp = requests.post(
  f"https://{ACCOUNT}.snowflakecomputing.com/api/v2/cortex/analyst/message",
  headers={"Authorization": f"Bearer {TOKEN}", "Content-Type": "application/json"},
  json={
    "messages": [{"role":"user","content":[{"type":"text","text":"Which region has the highest return count?"}]}],
    "semantic_view": "CORTEX_DEMO.SHOP.SALES_SV"
    # or "semantic_model_file": "@CORTEX_DEMO.SHOP.MODELS/sales.yaml"
  })
print(json.dumps(resp.json(), indent=2))   # contains text + generated SQL
```
Try these questions:
- "Total revenue by month" → time-series SQL
- "Top 3 products by sales" → ORDER BY / LIMIT
- "Which region has the most returns?" → North (2 returns)
- "Revenue from corporate clients in South" → synonym "clients" plus filters

### 4.5 Verified Queries (VQR)
Add trusted question→SQL pairs. Analyst uses them as examples and marks answers as verified. In Snowsight: **AI & ML → Cortex Analyst → your view → Verified queries**. You can also review real user questions there and promote them.

### 4.6 Analyst best practices
- Keep the model focused (one business domain per view).
- Add **descriptions + synonyms** to dimensions/metrics.
- Use **sample values** / Cortex Search integration for high-cardinality columns such as product names, so a typo like "smartwatch" still maps to "Smart Watch".
- Add verified queries for the top 20 business questions.
- Security: Analyst runs SQL with the **caller's role**, so RBAC, row access policies and masking still apply.

---

## 5. Cortex Agents

### 5.1 Concept
- An agent is an **orchestration layer**. For each question it:
  1. **Plans**: breaks the question into sub-tasks.
  2. **Uses tools**: Cortex Analyst (structured), Cortex Search (unstructured), and custom tools (stored procedures/UDFs, web search, etc.).
  3. **Reflects**: checks results and decides whether more tool calls are needed.
  4. **Responds**: combines the results into a final answer with citations, SQL and charts.
- Created as a **schema object** (`CREATE AGENT`) and used through Snowflake Intelligence, the REST API (`:run`), or your own app.
- Has instructions (response style, orchestration rules), a model choice, a tool list and tool resources.

### 5.2 Create the agent

```sql
CREATE OR REPLACE AGENT CORTEX_DEMO.SHOP.SHOPSMART_AGENT
  COMMENT = 'Sales + support assistant'
  PROFILE = '{"display_name": "ShopSmart Assistant"}'
  FROM SPECIFICATION
$$
models:
  orchestration: auto

instructions:
  response: "Be concise. Show numbers in tables. Cite policy titles when used."
  orchestration: >
    Use SalesAnalyst for any revenue, order, return or customer metric question.
    Use TicketSearch for customer complaints/feedback.
    Use PolicySearch for return, shipping or warranty rules.
    For mixed questions, call Analyst first, then Search, then combine.
  sample_questions:
    - question: "Which region had the most returns and why?"
    - question: "Is a smart watch with battery issues covered by warranty?"

tools:
  - tool_spec:
      type: cortex_analyst_text_to_sql
      name: SalesAnalyst
      description: "Structured sales data: orders, revenue, returns, customers, products."
  - tool_spec:
      type: cortex_search
      name: TicketSearch
      description: "Free-text customer support tickets and complaints."
  - tool_spec:
      type: cortex_search
      name: PolicySearch
      description: "Company return, shipping and warranty policies."

tool_resources:
  SalesAnalyst:
    semantic_view: CORTEX_DEMO.SHOP.SALES_SV
    execution_environment:
      type: warehouse
      warehouse: CORTEX_WH
  TicketSearch:
    name: CORTEX_DEMO.SHOP.TICKET_SEARCH
    max_results: 5
    id_column: TICKET_ID
  PolicySearch:
    name: CORTEX_DEMO.SHOP.POLICY_SEARCH
    max_results: 3
    title_column: TITLE
    id_column: DOC_ID
$$;

SHOW AGENTS IN SCHEMA CORTEX_DEMO.SHOP;
DESCRIBE AGENT CORTEX_DEMO.SHOP.SHOPSMART_AGENT;
```

### 5.3 Use it
- **UI:** Snowsight → **AI & ML → Agents** (test) or **Snowflake Intelligence** (business users). To show it in Snowflake Intelligence, add the agent to the account's Snowflake Intelligence object, or create it in the `SNOWFLAKE_INTELLIGENCE.AGENTS` schema, depending on your account version.
- **REST:**
```bash
curl -X POST "https://$ACCOUNT.snowflakecomputing.com/api/v2/databases/CORTEX_DEMO/schemas/SHOP/agents/SHOPSMART_AGENT:run" \
  -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  -d '{"messages":[{"role":"user","content":[{"type":"text","text":"Which region had the most returns and what are customers complaining about?"}]}]}'
```
The response is streamed as server-sent events (thinking, tool_use, tool_result, text, charts).

### 5.4 Walkthrough: what happens for the mixed question
**Q:** "Which region had the most returns and what are customers complaining about?"
1. Plan: a structured part (returns by region) and an unstructured part (complaints).
2. SalesAnalyst → SQL: `COUNT_IF(status='RETURNED') GROUP BY region` → **North = 2**, South = 1.
3. TicketSearch with filter REGION = North → battery drain, screen flicker, strap broke.
4. (Optional) PolicySearch → warranty covers battery/screen defects.
5. Answer: "North has the most returns (2, both Smart Watch). Customers report battery drain and screen flicker, which the 1-year warranty covers."

### 5.5 Custom tools (extend the agent)
```sql
CREATE OR REPLACE PROCEDURE CREATE_REFUND_REQUEST(ORDER_ID INT, REASON STRING)
RETURNS STRING LANGUAGE SQL AS
$$ BEGIN RETURN 'Refund request created for order ' || :ORDER_ID; END; $$;
```
Add it to the spec as `type: generic` with an input schema, and in `tool_resources` point it at the procedure (`type: procedure`, identifier, warehouse). The agent can then **take actions**, not just answer questions.

---

## 6. Comparison Cheat-Sheet

| Aspect | Cortex Search | Cortex Analyst | Cortex Agents |
|---|---|---|---|
| Input data | Text | Tables | Both (through tools) |
| Core tech | Embeddings + keyword + rerank | LLM text-to-SQL + semantic model | LLM orchestration/planning |
| Object | `CORTEX SEARCH SERVICE` | `SEMANTIC VIEW` / YAML | `AGENT` |
| Output | Ranked results (chunks) | SQL + result + explanation | Final answer + citations/SQL/charts |
| Freshness | TARGET_LAG refresh | Live query | Depends on tools |
| Governance | Owner's rights on the source query; usage grant on the service | Caller's role, RBAC/masking | Caller's role + tool grants |
| Cost drivers | Warehouse for refresh, serving per GB/month indexed, embedding tokens | LLM per message + warehouse for SQL | LLM tokens + underlying tool costs |

**Decision rule:** a precise number from tables → Analyst. Meaning from text → Search. Both, or multi-step work → Agent.

---

## 7. Security & Governance
```sql
CREATE ROLE IF NOT EXISTS SHOP_ANALYST;
GRANT DATABASE ROLE SNOWFLAKE.CORTEX_USER TO ROLE SHOP_ANALYST;
GRANT USAGE ON DATABASE CORTEX_DEMO TO ROLE SHOP_ANALYST;
GRANT USAGE ON SCHEMA CORTEX_DEMO.SHOP TO ROLE SHOP_ANALYST;
GRANT USAGE ON WAREHOUSE CORTEX_WH TO ROLE SHOP_ANALYST;
GRANT SELECT ON ALL TABLES IN SCHEMA CORTEX_DEMO.SHOP TO ROLE SHOP_ANALYST;
GRANT SELECT ON SEMANTIC VIEW CORTEX_DEMO.SHOP.SALES_SV TO ROLE SHOP_ANALYST;
GRANT USAGE ON CORTEX SEARCH SERVICE CORTEX_DEMO.SHOP.TICKET_SEARCH TO ROLE SHOP_ANALYST;
GRANT USAGE ON CORTEX SEARCH SERVICE CORTEX_DEMO.SHOP.POLICY_SEARCH TO ROLE SHOP_ANALYST;
GRANT USAGE ON AGENT CORTEX_DEMO.SHOP.SHOPSMART_AGENT TO ROLE SHOP_ANALYST;
```
- Data never leaves Snowflake's governance boundary, and models run inside Snowflake.
- Restrict which models can be used with the account parameter `CORTEX_MODELS_ALLOWLIST`.
- Monitor usage and cost with `SNOWFLAKE.ACCOUNT_USAGE` views (e.g., `CORTEX_SEARCH_SERVING_USAGE_HISTORY`, `CORTEX_ANALYST_USAGE_HISTORY`, `METERING_DAILY_HISTORY`), plus AI observability/agent monitoring in Snowsight.

---

## 8. Interview Questions & Answers

### Fundamentals
1. **What is Snowflake Cortex?**
   Snowflake's fully managed AI layer. It includes LLM functions (COMPLETE, AI_CLASSIFY, SUMMARIZE, SENTIMENT, TRANSLATE, EXTRACT_ANSWER, AI_* functions), Cortex Search, Cortex Analyst, Cortex Agents, Document AI and fine-tuning. Everything runs inside Snowflake's security perimeter.

2. **Difference between Cortex Search and Cortex Analyst?**
   Search retrieves relevant **unstructured** text through hybrid semantic + keyword search. Analyst generates **SQL** over **structured** data using a semantic model. Search gives you the most relevant passages. Analyst gives you an exact computed answer.

3. **What is RAG, and how does Cortex Search enable it?**
   Retrieve relevant context, then let the LLM generate an answer grounded in that context. This reduces hallucination and lets the model use private data. Cortex Search is the managed retrieval layer, and COMPLETE or an Agent is the generation layer.

4. **Why hybrid search instead of only vector search?**
   Vector search catches meaning (synonyms, paraphrases). Keyword search catches exact terms such as SKUs, error codes and names. Reranking then improves the top results. Together they're more accurate than either one alone.

5. **What is a semantic view / semantic model?**
   A business-layer definition of tables, relationships, dimensions, facts, metrics, synonyms and verified queries. It tells the LLM what "revenue" means and how tables join, which makes the generated SQL much more accurate and consistent.

6. **What is a Cortex Agent?**
   An LLM orchestrator that plans, picks tools (Analyst, Search, custom procedures), reflects on the results and returns a combined answer. It handles multi-step questions that span structured and unstructured data.

### Scenario-based
7. **The CFO asks "revenue last quarter by region" and gets different numbers from different people. How do you fix it?**
   Define the `total_revenue` metric once in a semantic view, add verified queries, and expose it through Analyst or an Agent. Everyone then gets the same governed definition.

8. **Analyst generates wrong SQL for "smartwatch sales". Why, and how do you fix it?**
   The literal value doesn't match the stored "Smart Watch". Fix it by adding sample values or synonyms, linking a Cortex Search service to that dimension for value lookup, and adding a verified query.

9. **A support team needs answers from 10,000 PDFs updated daily.**
   Stage → PARSE_DOCUMENT → SPLIT_TEXT chunking → table → Cortex Search service with TARGET_LAG = '1 day' and attributes for filtering (product, date) → Agent or RAG app with citations.

10. **"Which products have the most returns and why?" Which component?**
    An Agent. Analyst answers "most returns" and Search answers "why" from tickets. The Agent combines them.

11. **How do you secure it so a regional manager sees only their region?**
    Put a row access policy on the base tables. Analyst and Agent run as the caller's role, so the policy applies automatically. For Search, use attribute filters, or separate services or views per audience, because the service is built with the owner's rights.

12. **How do you reduce Cortex Search cost?**
    Index only the needed columns and rows, use a sensible TARGET_LAG, use an X-Small warehouse for refreshes, suspend unused services (`ALTER CORTEX SEARCH SERVICE ... SUSPEND`), and choose an appropriate embedding model.

13. **How do you evaluate quality?**
    Build a golden question set. For Search, measure recall and precision@k. For Analyst, track SQL accuracy against verified queries. For Agents, use AI observability / TruLens (groundedness, relevance) and track user feedback.

14. **The LLM hallucinates in your RAG app. What steps do you take?**
    Improve chunking (size and overlap), add filters, increase or decrease `limit`, add a strict prompt ("answer only from context"), return citations, and use a stronger model.

15. **When would you NOT use an Agent?**
    When a question is single-purpose. A dashboard KPI should use a semantic view or plain SQL, and a pure document lookup should call Search directly. Skipping the agent gives lower latency and cost and is easier to debug.

### Rapid-fire
- Function to test search in SQL → `SNOWFLAKE.CORTEX.SEARCH_PREVIEW`
- Role needed for Cortex → `SNOWFLAKE.CORTEX_USER` database role
- Analyst endpoint → `/api/v2/cortex/analyst/message`
- Agent run endpoint → `.../agents/{name}:run`
- Filterable columns in Search → `ATTRIBUTES`
- Freshness setting → `TARGET_LAG`
- Business UI for agents → Snowflake Intelligence
- Models running cross-region → `CORTEX_ENABLED_CROSS_REGION`

---

## 9. Hands-on Practice Plan
1. Run section 2 (setup).
2. Create both search services and run 5 different SEARCH_PREVIEW queries, including filters.
3. Build the RAG query in 3.4 and change the question.
4. Create SALES_SV, query it with `SEMANTIC_VIEW()`, then try natural-language questions in Snowsight's Cortex Analyst playground.
5. Add 3 verified queries.
6. Create the agent and ask the mixed question from 5.4. Open the "thinking"/tool trace to see the orchestration.
7. Add the refund stored procedure as a custom tool.
8. Grant access to a new role and test RBAC.

## 10. Cleanup
```sql
DROP AGENT IF EXISTS CORTEX_DEMO.SHOP.SHOPSMART_AGENT;
DROP CORTEX SEARCH SERVICE IF EXISTS CORTEX_DEMO.SHOP.TICKET_SEARCH;
DROP CORTEX SEARCH SERVICE IF EXISTS CORTEX_DEMO.SHOP.POLICY_SEARCH;
DROP DATABASE IF EXISTS CORTEX_DEMO;
DROP WAREHOUSE IF EXISTS CORTEX_WH;
```
