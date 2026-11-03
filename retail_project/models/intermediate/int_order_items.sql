-- materialized: ephemeral (from dbt_project.yml). Inlined as a CTE, never created in Snowflake.
select
    order_key,
    count(*)                                                        as line_count,
    sum(quantity)                                                   as total_quantity,
    sum({{ net_amount('extended_price', 'discount') }})             as net_revenue
from {{ ref('stg_lineitems') }}
group by order_key
