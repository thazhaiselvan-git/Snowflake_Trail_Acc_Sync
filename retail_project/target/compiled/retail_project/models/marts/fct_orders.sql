

with __dbt__cte__int_order_items as (
-- materialized: ephemeral (from dbt_project.yml). Inlined as a CTE, never created in Snowflake.
select
    order_key,
    count(*)                                                        as line_count,
    sum(quantity)                                                   as total_quantity,
    sum(round(extended_price * (1 - discount), 2))             as net_revenue
from RETAIL_DBT.DEV.stg_lineitems
group by order_key
) select
    o.order_key,
    o.customer_key,
    o.order_date,
    o.order_status,
    s.status_description,
    o.order_priority,
    o.total_price,
    i.line_count,
    i.total_quantity,
    i.net_revenue
from RETAIL_DBT.DEV.stg_orders o
left join __dbt__cte__int_order_items i
    on o.order_key = i.order_key
left join RETAIL_DBT.DEV.order_status_lookup s
    on o.order_status = s.status_code

