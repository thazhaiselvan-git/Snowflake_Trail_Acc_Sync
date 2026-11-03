{{ config(
    materialized='incremental',
    incremental_strategy='merge',
    unique_key='order_key',
    on_schema_change='append_new_columns'
) }}

select
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
from {{ ref('stg_orders') }} o
left join {{ ref('int_order_items') }} i
    on o.order_key = i.order_key
left join {{ ref('order_status_lookup') }} s
    on o.order_status = s.status_code

{% if is_incremental() %}
where o.order_date >= (select max(order_date) from {{ this }})
{% endif %}
