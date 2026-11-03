-- materialized: ephemeral (from dbt_project.yml). Inlined as a CTE, never created in Snowflake.
select
    order_key,
    count(*)                                                        as line_count,
    sum(quantity)                                                   as total_quantity,
    sum(round(extended_price * (1 - discount), 2))             as net_revenue
from RETAIL_DBT.DEV.stg_lineitems
group by order_key