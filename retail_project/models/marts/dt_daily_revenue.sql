-- Snowflake dynamic table: Snowflake refreshes it on its own within target_lag.
-- refresh_mode FULL avoids needing change tracking on the RAW tables (DBT_ROLE doesn't own them).
{{ config(
    materialized='dynamic_table',
    snowflake_warehouse=target.warehouse,
    target_lag='1 day',
    refresh_mode='FULL'
) }}

select
    order_date,
    count(*)         as orders,
    sum(total_price) as gross_revenue
from {{ ref('stg_orders') }}
group by order_date
