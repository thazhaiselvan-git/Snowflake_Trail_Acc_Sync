select
    c.customer_id,
    c.customer_name,
    c.region,
    c.tier,
    count(o.order_id)            as total_orders,
    coalesce(sum(o.amount), 0)   as lifetime_value
from {{ ref('stg_customers') }} c
left join {{ ref('stg_orders') }} o using (customer_id)
group by all
