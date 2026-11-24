# Snowflake CoWork: Complete Beginner's Guide

All features and options, plus how CoWork compares with Cortex Agents and Cortex Code (CoCo)

Prepared: November 24, 2026. Source: Snowflake documentation (docs.snowflake.com). Feature status (GA / Preview) reflects the documentation at the time of writing.

## 1. What is Snowflake CoWork?

Snowflake CoWork is a ready-to-use agentic application with a conversational interface that helps business users discover and act on insights. You ask questions in plain English about your structured data (tables) and unstructured data (documents), and AI "data agents" do four things:

- Understand the question
- Perform the analysis
- Generate trusted insights
- Take action

The goal is to move beyond stale dashboards and rigid reports, so users can find answers on their own with full traceability while all Snowflake security and governance rules still apply.

**Note:** *Older Snowflake material calls this product "Snowflake Intelligence". SQL objects still use that name, for example CREATE SNOWFLAKE INTELLIGENCE and the SNOWFLAKE_INTELLIGENCE database.*

### Key capabilities at a glance

| Capability | What it gives you |
|---|---|
| Natural language chat | Ask questions in plain language and get deep insights |
| Unified data access | Structured and unstructured enterprise data in one conversation |
| Trustworthy answers | Traceability to source data and SQL; data teams can add Verified Answers |
| Built-in visualization | Automatic charts (most Vega-Lite types) and interactive maps (Preview) |
| Deep Research | Multi-step investigation that produces a structured, cited report |
| Extended thinking | More thorough reasoning for complex questions |
| File upload | Attach PDFs, spreadsheets, decks, images and more as context |
| Artifacts | Save charts, tables and maps; share conversations as snapshots |
| Document generation | Create PDF, Word, PowerPoint and HTML outputs |
| Automations | Recurring reports emailed to you (hourly to monthly) |
| User skills | Reusable workflows you run with /skill-name |
| User memory | Remembers preferences you ask it to save |
| Profiles | Per-team experiences that route questions to the right agent |
| Governance | Inherits RBAC, row access policies and masking policies |
| Admin control | IdP integration, CoWork-only users, private connectivity, budgets |
| Mobile | iOS app with the same features as the web app |

## 2. How it works (architecture)

CoWork is powered by the Cortex Agent API. Each question flows through these steps:

1. User input: you type a question, for example "How are Q4 sales trending?"
2. Cortex Agent API: the question goes to a Cortex Agent, an AI model connected to semantic views, search services and tools.
3. Orchestration: an LLM (the orchestrator) works out what you mean, picks tools, and plans the steps. It may use one tool, chain several, or decide the question is out of scope.
4. Tool execution: the selected tools run.
5. Reflection and response: the orchestrator reviews the results and returns an answer with summaries, tables or charts.

### Tool types an agent can use

| Tool | Data type | What it does |
|---|---|---|
| Cortex Analyst | Structured | Turns natural language into SQL over semantic views |
| Cortex Search | Unstructured | Searches documents and text (RAG and enterprise search); optional analytical search for counts, lists and trends |
| Custom tools | Any | Runs UDFs or stored procedures for custom business logic or actions |
| Code execution (sandbox) | Any | Needed for document generation and for skills that run scripts |
| Web search | External | Optional; Deep Research can also search the web |
| MCP connectors | External apps | Connectors configured on profiles or agents (for example CRM) |

## 3. Getting access and opening CoWork

### Ways to open CoWork

| Method | How |
|---|---|
| Standard URL | https://ai.snowflake.com |
| Private connectivity | https://si-<org-acct>.privatelink.snowflakecomputing.com |
| Direct link to an agent | Snowsight > AI & ML > Agents > select agent > Preview in Snowflake CoWork > copy URL |
| Mobile | Snowflake CoWork app for iOS (App Store) |

### What you need as a user

- A default role and a default warehouse. CoWork starts your session with them; you can switch later.
- USAGE on the agent, plus its database and schema.
- Access to what the agent's tools use: SELECT on tables behind semantic views, USAGE on semantic views and Cortex Search services, USAGE on custom tool procedures or functions, and READ on stages to open cited documents.
- The CORTEX_USER role (granted to PUBLIC by default) or the narrower SNOWFLAKE.CORTEX_AGENT_USER database role.
- A verified email address, if you want automation emails.

## 4. Chatting with your data (the basics)

- Ask questions in plain language, for example: "What product sold the most units last month?" or "Show me the sales trend for the last year."
- The agent decides whether to show a chart or a table. Trends and comparisons become charts; detailed lookups become tables.
- Every answer is traceable. You can see the SQL and source data, and citations link to documents. PDFs can open in the in-app viewer when the search tool is configured with a stage path.
- Tables can be sorted, filtered, searched and resized without asking a new question. In explorer mode, charts and tables stay in sync.
- You can switch between agents in the same thread and keep the context.
- Use @ to tag a specific agent; with profiles, only agents in that profile can be tagged.
- You can rate responses with feedback, which admins see in agent monitoring.
- Data teams can add Verified Answers (verified queries) so common questions get trusted, consistent, fast answers. An exact match runs the validated SQL directly.

### Tips for good questions

- Be specific about the format and style you want; vague prompts cause inconsistent answers.
- Rolling windows such as "last 30 days" are recalculated each run. Give fixed dates for a fixed period.
- Very long threads lose early context; start a new thread for a new topic.

## 5. Chat modes: Extended thinking and Deep Research

### Extended thinking

By default, agents balance speed and quality. Turn on extended thinking in the chat window to make the agent more thorough: it validates SQL logic, joins and access controls before running anything. It takes longer and uses more tokens. The setting stays on until you turn it off.

### Deep Research

An investigation mode for complex, open-ended "why" questions:

- Start it from the + button in the message bar > Deep Research.
- It splits the question into sub-investigations, runs them in parallel across structured and unstructured data, and combines the results into a structured report.
- Every claim traces back to its source data and queries.
- A run can take up to 10 minutes. The report stays in context, so follow-ups such as "break that down by region" run as normal chat turns.
- If the agent has web search enabled, it also researches the web and cites web sources. Web research runs separately and has no access to your data.
- Example questions: "Why has forecast accuracy been declining?" or "Which customer segments show early churn signals?"
- For quick lookups, the standard chat is faster.

|  | Standard chat | Extended thinking | Deep Research |
|---|---|---|---|
| Best for | Quick metrics, lookups, follow-ups | Complex single answers | Open-ended 'why' investigations |
| How | Default | Toggle in chat window | + menu > Deep Research |
| Speed | Fastest | Slower | Up to ~10 minutes |
| Output | Answer, chart or table | More carefully checked answer | Structured, cited report |

**Note:** *You can combine them: turn on extended thinking during a Deep Research run.*

## 6. File upload (zero setup)

Attach files in the chat to give the agent extra context.

| Category | Supported file types |
|---|---|
| Documents | .pdf, .txt, .md, .docx, .doc |
| Spreadsheets | .xlsx, .xls, .csv |
| Presentations | .pptx |
| Code and data | .json |
| Images | .png, .jpg, .jpeg, .gif, .svg, .bmp, .tiff, .tif, .webp, .heic, .heif |

- Limits: each file must be under 50 MB, with up to 5 files.
- Files are saved to your personal user stage and are available within the same thread.
- Files are deleted automatically when the thread is deleted or expires.
- Complex processing may use your default warehouse to run Snowpark code.
- Uploads are treated as customer data under normal governance.

## 7. Charts and visualizations

CoWork supports most Vega-Lite chart types:

- Bar, line, pie and scatter (these four also have a manual chart editor)
- Area charts, heatmaps and box plots
- Dual-axis and layered charts (for example, bars plus a line)
- Faceted charts and small multiples
- Error bars and error bands
- Text annotations

For any other change, just ask in chat, for example "make it a stacked area chart".

### Chart customization (Preview), for agent builders

| Level | Where to configure | Use it for |
|---|---|---|
| Agent level | <chart_customization> block in instructions.orchestration | Brand palette, fonts, background, number and currency defaults |
| Semantic view level | <chart_customization> in module_custom_instructions.sql_generation | Per-column colors, domain chart-type rules, overriding agent defaults |

- **vega_template:** a partial Vega-Lite JSON that is always merged into every chart. It is deterministic.
- **Free-text instructions:** guidance such as "Prefer horizontal bars for ranked data". The model tries to follow it but it isn't guaranteed.
- **Precedence:** the agent template is applied first, then the semantic view template; the semantic view wins conflicts.
- **Caution:** templates affect every chart. Don't force "mark" or column-specific colors at agent level. Test templates in the Vega Editor.

## 8. Geospatial maps (Preview)

When a result has locations or geometry, CoWork can draw an interactive map instead of a chart.

| Layer type | Used for | Source columns |
|---|---|---|
| Points (lat/lon) | Stores, sites, addresses | Latitude and longitude columns |
| H3 hexagons | Density, heatmaps, aggregates over area | H3 cell IDs (for example from H3_LATLNG_TO_CELL_STRING) |
| GeoJSON | Lines and region polygons (ZIP codes, territories, routes) | GEOGRAPHY or GEOMETRY columns |

- Example prompts: "Show store locations on a map colored by revenue", "Map delivery density as hexagons".
- Pan, zoom, open Explore, and ask follow-ups such as "switch that to H3".
- Maps can be saved and shared like charts.
- Limitations: chart customization and the chart editor don't apply to maps; there's no PNG export (CSV export is available); snapshot-only maps don't refresh.

## 9. Artifacts: save, refresh and share

| Artifact type | Contains | Refreshes? |
|---|---|---|
| Chart artifact | A saved chart, table or map, plus its SQL query | Yes; reruns SQL with the viewer's credentials |
| Thread artifact | A snapshot of a whole conversation | No; fixed snapshot |

### Using artifacts

- Save: select Save on any chart, table or map result.
- Artifacts hub: the Saved tab (yours) and Shared with me (opened through links).
- Auto-refresh happens when you view an artifact more than 12 hours after your last view; you can also refresh manually.
- Each viewer sees data under their own permissions, so different people may see different numbers.
- Ask follow-up questions on a saved artifact. This starts a new private conversation and leaves the original alone.
- Share a conversation with the sharing control to create a Thread artifact link.
- Review threads for sensitive content before sharing; recipients see saved content even without source access.
- Admins can turn off sharing for the whole account.

### Lifecycle

- Saved charts, tables and maps last until you delete them, even if the source thread is deleted.
- Shared threads are deleted when the source conversation is deleted, including through retention.
- If you lose access to the source data, refresh stops but the last snapshot stays visible.
- There are no folders or labels; each artifact is a single result tile.

## 10. Document generation

Turn an analysis into a file you can view inline in CoWork.

| Format | File type | Typical use |
|---|---|---|
| PDF | .pdf | Written brief, summary or report |
| Word | .docx | Written report or brief |
| PowerPoint | .pptx | Presentation deck with slides and talking points |
| HTML | .html | Formatted report viewed inline |

- Example prompt: "Create a PowerPoint deck that summarizes Q4 pipeline risk by region for the leadership review."
- To match your branding, attach a .pptx template and ask CoWork to use it.
- You can attach a PDF as a reference; the layout isn't guaranteed to match exactly.
- You can customize the behavior with a user skill or an agent skill; these take precedence over the built-in behavior.
- Prerequisite: the agent must have the code execution tool enabled; ask your admin if generation fails.

## 11. Automations (scheduled reports)

An automation subscribes you to a question. On each run, CoWork re-runs the question against the latest data and emails you the results.

### Create an automation

- **From a conversation:** ask a question, then accept CoWork's suggestion ("Want me to send it every Monday at 9 AM?") or say "Send me this report every Monday".
- **From the Automations tab:** Create automation > From a conversation or Manually, then set Name, Instructions and Frequency (hourly, daily, weekly or monthly).

### Manage automations conversationally

| To do this | Say something like |
|---|---|
| List | "What automations do I have?" |
| Reschedule | "Change my Monday report to 7 AM instead" |
| Pause | "Pause the quarterly review report" |
| Resume | "Resume the quarterly review report" |
| Delete | "Delete my weekly demand forecast report" |

- Each email contains a summary, key metrics, and a link that opens the full report as a thread where you can ask follow-ups.
- Each run creates a new thread. Run history is kept for 60 days.
- Forwarded links don't work for recipients; use Share to send a snapshot instead.
- Automations run with caller's rights (your role and warehouse), so all policies apply.
- Results are encrypted at rest (including Tri-Secret Secure) and every run is logged in Account Usage.
- Cost: uses your compute, billed as standard Snowflake tasks. The fastest schedule is once per hour.
- Requires a verified email. Admins can also verify a whole email domain with a DNS TXT record.
- On by default, through EXECUTE AGENT TASK granted to PUBLIC. Admins can revoke it (see section 23).

## 12. User skills

A user skill packages a repeatable workflow (steps, data sources, output style) so you can run it again on demand.

### Create a skill

- **Conversationally:** "Create a skill that prepares me for a customer meeting: pull account health, risks, recent Slack and email threads, and build a PowerPoint."
- **From the UI:** + menu > Skills > Create new. A guided interview asks for a name (kebab-case), purpose, triggers, and the tools to use.
- **Upload:** Capabilities > Skills > upload a skill folder.

### Run a skill

- **Explicitly:** type /skill-name plus optional context (for example /prepare-for-customer-meeting Acme Corp), or pick it from the + menu or Capabilities > Skills.
- **Implicitly:** describe what you need. CoWork matches your request to the skill's name and description and runs it.
- Manage skills by asking "What skills do I have?", "Update my meeting prep skill to include NPS" or "Delete ... skill", or use Capabilities > Skills.
- Skills are private to you and run with caller's rights.
- Agent skills (developer-written SKILL.md packages attached to an agent) also appear in the / menu with agent badges.
- Limitations: skills that run scripts need the code execution tool, and a skill can only use tools the agent already has.

## 13. User memory

- Ask CoWork to remember preferences, for example "Remember that I prefer concise answers".
- Memory applies only in CoWork, not to direct Cortex Agent API calls.
- Turn it off with Settings > Memories > Reference saved memories. This doesn't delete saved memories.

## 14. Profiles and agent routing (Preview)

A profile defines what CoWork looks like for one group of users: which agents it can reach, the instructions that decide which agent answers, and its own skills and connectors. Users don't pick an agent; the profile routes each question to the best one.

- Typical layouts: one profile for everyone (start here) or one per function (Sales, Finance, Legal, General).
- Access is controlled by granting USAGE on the profile. Users with access to only one profile see no picker; users with several pick one from the account menu.
- A profile controls routing, not data access. RBAC, row access and masking still decide what each user sees.
- Capabilities (web search, code execution, skills, MCP) are configured separately on profiles and agents; the account-level setting overrides both.
- Technically, a profile is a Cortex Agent with an agent_router tool, stored in SNOWFLAKE_INTELLIGENCE.PROFILES by default.
- Set up through CoWork Admin or SQL. Accounts currently using a single "Main Agent" can migrate.
- Evaluate routing with Cortex Agent evaluations, using tool selection accuracy (TSA) and tool execution accuracy (TEA).
- Roles: the CoWork admin owns the object and grants access; profile owners manage the contents; the account admin creates the roles, often mapped to identity provider groups through SCIM.

## 15. Mobile app (iOS)

Available on the App Store, with the same features as the web app: chat, agents, file and image attachments, voice input, citations, and role and warehouse selection.

## 16. Security and governance

- Every query runs with the user's own credentials, so RBAC, row access policies and masking policies always apply.
- Automations and skills use caller's rights, with no elevated permissions.
- Unsafe generated SQL is blocked rather than run (error 370001).
- Uploaded files are stored as governed customer data on your personal stage.
- Users can be limited to CoWork only: ALTER USER ... SET ALLOWED_INTERFACES = (SNOWFLAKE_INTELLIGENCE), or the SCIM attribute allowedInterfaces.
- Sign-in can go through your identity provider using LOGIN_IDP_REDIRECT, and AWS PrivateLink and Azure Private Link are supported.
- Admins can turn off account-wide sharing of artifacts and chats.

## 17. Administration and setup

### Customize the interface

Snowsight > AI & ML > Agents > Open settings > Snowflake CoWork section:

- Display name
- Welcome message
- Color theme (a custom hex primary color)
- Full-length logo and compact logo (the compact logo is also the browser tab icon)

### The Snowflake CoWork object

- An account-level object (one per account) that holds the curated list of agents and profiles users see.
- Created automatically when you first save CoWork settings (named SNOWFLAKE_INTELLIGENCE_OBJECT_DEFAULT), or with SQL.
- If the object exists, agents must be added to it to appear in CoWork; otherwise they're reachable only by direct link.
- Without an object, users see every agent they have access to.
- Managing visibility with the SNOWFLAKE_INTELLIGENCE.AGENTS schema is deprecated; migrate to the object.

### Privileges

| Privilege | On | Allows |
|---|---|---|
| CREATE SNOWFLAKE INTELLIGENCE | Account | Creating the CoWork object (ACCOUNTADMIN by default) |
| USAGE | CoWork object | Seeing the agent list and configuration |
| MODIFY | CoWork object | Adding or removing agents and changing settings |
| CREATE AGENT | Schema | Building agents |
| USAGE | Agent | Chatting with the agent |
| EXECUTE AGENT TASK | Account | Using automations (granted to PUBLIC by default) |

### Monitoring

Agent logs (prompts, responses, errors, traces with step timings) and user feedback are available in Snowsight agent monitoring.

## 18. Building agents for CoWork

You can build agents in Snowsight (AI & ML > Agents > Create agent), with SQL (CREATE AGENT ... FROM SPECIFICATION), or through the Agent Object REST API. An agent consists of a model (the orchestrator), instructions, tools, and the resources those tools use.

### Best practices

- Scope each agent narrowly to one high-value use case, then reuse the pattern for others.
- Give each agent only the tools it needs: Cortex Analyst for structured data, Cortex Search for unstructured data, custom tools for anything else.
- Write clear tool descriptions covering what the tool does, what data it uses, when to use it and when not to.
- Set the model to auto so you always get the best available model.
- Turn on cross-region inference (ALTER ACCOUNT SET CORTEX_ENABLED_CROSS_REGION = 'ANY_REGION') to reach the full set of models.
- Add verified queries to semantic views so common questions get fast, predictable answers.
- Add "parallelize as many tool calls as possible" to the orchestration instructions to reduce latency.
- To open cited documents, set stage_path and relative_path_column on the Cortex Search tool.

### Quick-start path (from the docs)

1. Load data and create a database and schema (sample repo: sfguide-getting-started-with-snowflake-intelligence).
2. Create a semantic view (AI & ML > Cortex Analyst > Create new Semantic View).
3. Create a Cortex Search service on your text data (AI & ML > Cortex Search).
4. Create an agent (AI & ML > Agents) and add both tools.
5. Add orchestration instructions, for example "always generate a chart when you can".
6. Add the agent to the CoWork object and grant USAGE.
7. Open CoWork and ask questions.

```sql
CREATE OR REPLACE AGENT my_db.my_schema.sales_ai
  FROM SPECIFICATION $$
  models:
    orchestration: auto
  instructions:
    orchestration: "For revenue questions use Analyst; for policy questions use Search"
  tools:
    - tool_spec: {type: cortex_analyst_text_to_sql, name: sales, description: "..."}
    - tool_spec: {type: cortex_search, name: docs, description: "..."}
  tool_resources:
    sales: {semantic_view: "my_db.my_schema.sales_sv"}
    docs:  {search_service: "my_db.my_schema.docs_search"}
  $$;
```

## 19. Cost, budgets and usage monitoring

- Credits are consumed for agent and LLM calls and for tools. SQL from Cortex Analyst runs on your warehouse, and automations are billed as tasks.
- Extended thinking and Deep Research use more tokens.
- **Resource budget:** tag the CoWork object, then create a budget with a monthly credit limit and threshold actions (for example, alert at 80% and revoke access at 100%). Enforcement can take up to 8 hours.
- **Shared resource budget:** a separate credit limit for a tagged group of users (for example a team) on the same CoWork object.
- **Per-user quotas:** per-user credit limits across AI features, with optional blocking.
- **Usage views:** SNOWFLAKE_COWORK_USAGE_HISTORY (Account Usage and Organization Usage) shows credits and tokens per request by user and agent. Direct Cortex Agent API calls appear in CORTEX_AGENT_USAGE_HISTORY instead.

## 20. Limits and known limitations

| Area | Limit or limitation |
|---|---|
| File upload | Under 50 MB per file, up to 5 files |
| Deep Research | Can take up to 10 minutes |
| Automations | At most hourly; email delivery only; verified email required; 60-day run history |
| Artifacts | Each is a single tile; no folders or labels; chart editor only for bar, line, pie and scatter |
| Maps | No PNG export; no chart editor or Vega templates; snapshot maps don't refresh |
| Skills and document generation | Need the code execution tool for scripts and files; limited to the agent's tools |
| Context | A finite context window, so long threads lose early context |
| Cortex Analyst | A 2,048-token limit on generated SQL, which may cause retries |
| CoWork object | Only one per account |
| Budgets | Enforcement may lag by up to 8 hours |

## 21. Troubleshooting and tips

| Symptom | Likely cause and fix |
|---|---|
| Inconsistent answers | Vague prompt or recent configuration change; be specific and use semantic views rather than semantic models |
| No streaming on some machines | Corporate network, security tools or browser extensions; contact IT |
| Error 370001 | Generated SQL was unsafe and was blocked |
| execution_environment not populated | User has no warehouse; set a default warehouse or a tool warehouse |
| "Table/search service/stage does not exist" | Missing privileges (USAGE, SELECT, REFERENCES, READ) |
| Slow or timing out | Enable cross-region inference, use the auto model, add verified queries, check warehouse size and the status page |
| Document generation or skill fails | Ask an admin to enable code execution on the agent |
| No automation emails | Verify your email, or ask an admin to add one |

Support: use the Support page in Snowsight or the Snowflake Forums.

## 22. CoWork vs Cortex Agent vs Cortex Code (CoCo)

These three products work together. In short, data teams use Cortex Code to build the data and the agents, the agents themselves are Cortex Agents, and business users chat with them through CoWork.

| Aspect | Cortex Agent (a "normal" agent) | Snowflake CoWork | Cortex Code (CoCo) |
|---|---|---|---|
| What it is | A Snowflake object and API: model + instructions + tools | A ready-made chat app built on Cortex Agents | An AI coding and data-engineering agent |
| Primary users | Developers who build and embed it | Business users and analysts | Data engineers, developers, analysts |
| How you use it | SQL (CREATE AGENT), REST API, Snowsight agent page, or your own app | Browser (ai.snowflake.com) or iOS app | CLI, Snowsight Agent Mode, or desktop |
| Setup needed | You configure tools, semantic views and search | Ready to use once an admin adds agents or profiles | Ready to use with a Snowflake connection |
| Main job | Answer questions with its configured tools | Chat analysis, charts, reports, automations | Write and run SQL, Python and dbt; build pipelines, apps, semantic views and agents |
| Data access | Only through its tools | Through the agents behind it | Direct SQL plus files, shell and git in a sandbox |
| UI features | None of its own (an API returns text, charts and tables) | Chat UI, artifacts, maps, documents, memory, skills, Deep Research | Workspace files, notebooks, dashboards, previews |
| Scheduling | Agent SDK automations | Automations (email reports) | CoCo automations (scheduled agent tasks) |
| Coding required | Yes, YAML spec or API | No | No, but it writes code for you |
| Governance | Runs as the caller; RBAC applies | Runs as the user; RBAC applies | Runs with your role; RBAC applies |

### When to use which

- **Use CoWork when** you want answers, charts, reports or recurring email summaries from your data without writing code.
- **Use a Cortex Agent directly when** you're embedding AI Q&A into your own app, portal or Slack bot through the API, or designing the agent CoWork will use.
- **Use Cortex Code when** you need to build something: tables, dbt models, pipelines, semantic views, the Cortex Agents themselves, Streamlit apps, or to debug SQL and code.

### Typical end-to-end flow

1. A data engineer uses Cortex Code to model the data and create semantic views and search services.
2. The engineer (or Cortex Code) creates a Cortex Agent with Analyst, Search and custom tools.
3. An admin adds the agent to the CoWork object or a profile and grants USAGE.
4. Business users ask questions in CoWork, save artifacts, generate decks and schedule automations.

**Note:** *CoWork's built-in AI is itself a Cortex Agent, so improving the agent (instructions, tool descriptions, verified queries) directly improves CoWork answers.*

## 23. Quick reference: SQL commands

```sql
-- CoWork object
SHOW SNOWFLAKE INTELLIGENCES;
CREATE SNOWFLAKE INTELLIGENCE SNOWFLAKE_INTELLIGENCE_OBJECT_DEFAULT;
DESCRIBE SNOWFLAKE INTELLIGENCE SNOWFLAKE_INTELLIGENCE_OBJECT_DEFAULT;
ALTER SNOWFLAKE INTELLIGENCE SNOWFLAKE_INTELLIGENCE_OBJECT_DEFAULT ADD AGENT <db.schema.agent>;
ALTER SNOWFLAKE INTELLIGENCE SNOWFLAKE_INTELLIGENCE_OBJECT_DEFAULT DROP AGENT <db.schema.agent>;

-- Access
GRANT USAGE  ON SNOWFLAKE INTELLIGENCE SNOWFLAKE_INTELLIGENCE_OBJECT_DEFAULT TO ROLE PUBLIC;
GRANT MODIFY ON SNOWFLAKE INTELLIGENCE SNOWFLAKE_INTELLIGENCE_OBJECT_DEFAULT TO ROLE <role>;
GRANT CREATE SNOWFLAKE INTELLIGENCE ON ACCOUNT TO ROLE <role>;
GRANT DATABASE ROLE SNOWFLAKE.CORTEX_AGENT_USER TO ROLE <role>;
ALTER USER <user> SET ALLOWED_INTERFACES = (SNOWFLAKE_INTELLIGENCE);
ALTER ACCOUNT SET LOGIN_IDP_REDIRECT = (SNOWFLAKE_INTELLIGENCE = <security_integration>);

-- Automations
REVOKE EXECUTE AGENT TASK ON ACCOUNT FROM ROLE PUBLIC;   -- disable for all
GRANT  EXECUTE AGENT TASK ON ACCOUNT TO ROLE <role>;     -- enable for a role

-- Models
ALTER ACCOUNT SET CORTEX_ENABLED_CROSS_REGION = 'ANY_REGION';

-- Agents and profiles
SHOW AGENTS IN SCHEMA SNOWFLAKE_INTELLIGENCE.PROFILES;
CREATE AGENT / DESCRIBE AGENT / SHOW AGENTS / ALTER AGENT / DROP AGENT

-- Cost
ALTER SNOWFLAKE INTELLIGENCE <name> SET TAG <db.schema.tag> = '<value>';
SELECT * FROM SNOWFLAKE.ACCOUNT_USAGE.SNOWFLAKE_COWORK_USAGE_HISTORY;
```

## 24. Glossary and documentation links

| Term | Meaning |
|---|---|
| Agent | A Cortex Agent: an AI model with instructions and tools that answers questions |
| Orchestrator | The LLM inside an agent that plans and picks tools |
| Semantic view | Business-friendly definitions of tables, metrics and relationships used by Cortex Analyst |
| Verified query / Verified Answer | A data-team-approved SQL answer for a common question |
| Artifact | A saved chart, table or map (Chart artifact) or a shared conversation snapshot (Thread artifact) |
| Profile | A per-group CoWork experience that routes questions to agents |
| Caller's rights | Runs with the user's own role and permissions |
| MCP | Model Context Protocol, used for connectors to external tools |

- Overview: https://docs.snowflake.com/en/user-guide/snowflake-cortex/snowflake-cowork
- Getting started: https://docs.snowflake.com/en/user-guide/snowflake-cortex/snowflake-cowork/getting-started
- Automations: https://docs.snowflake.com/en/user-guide/snowflake-cortex/snowflake-cowork/automations
- User skills: https://docs.snowflake.com/en/user-guide/snowflake-cortex/snowflake-cowork/user-skills
- Document generation: https://docs.snowflake.com/en/user-guide/snowflake-cortex/snowflake-cowork/document-generation
- Artifacts: https://docs.snowflake.com/en/user-guide/snowflake-cortex/snowflake-cowork/artifacts
- Maps: https://docs.snowflake.com/en/user-guide/snowflake-cortex/snowflake-cowork/maps
- Chart customization: https://docs.snowflake.com/en/user-guide/snowflake-cortex/snowflake-cowork/chart-customization
- User access and settings: https://docs.snowflake.com/en/user-guide/snowflake-cortex/snowflake-cowork/deploy-agents
- Profiles: https://docs.snowflake.com/en/user-guide/snowflake-cortex/snowflake-cowork/about-cowork-profiles
- Profile routing setup: https://docs.snowflake.com/en/user-guide/snowflake-cortex/snowflake-cowork/set-up-cowork-profile-routing
- Build agents: https://docs.snowflake.com/en/user-guide/snowflake-cortex/snowflake-cowork/build-agents
- Troubleshooting: https://docs.snowflake.com/en/user-guide/snowflake-cortex/snowflake-cowork/troubleshooting
- Resource budgets: https://docs.snowflake.com/en/user-guide/snowflake-cortex/snowflake-cowork/cowork-resource-budgets
- Shared budgets: https://docs.snowflake.com/en/user-guide/snowflake-cortex/snowflake-cowork/cowork-shared-budgets
- Reference: https://docs.snowflake.com/en/user-guide/snowflake-cortex/snowflake-cowork/reference