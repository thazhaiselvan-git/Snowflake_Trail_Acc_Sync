{{ config(
    materialized='incremental',
    unique_key='order_id',
    incremental_strategy='merge'
) }}

select
    o.order_id,
    o.customer_id,
    c.region,
    o.status,
    o.amount,
    o.updated_at
from {{ ref('stg_orders') }} o
join {{ ref('stg_customers') }} c using (customer_id)

{% if is_incremental() %}
  -- 3-day lookback catches late-arriving / updated rows
  where o.updated_at > (select dateadd('day', -3, max(updated_at)) from {{ this }})
{% endif %}
