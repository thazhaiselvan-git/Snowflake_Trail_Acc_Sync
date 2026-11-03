-- Singular test: returns rows that FAIL. Passes when no order has negative revenue.
select order_key, net_revenue
from {{ ref('fct_orders') }}
where net_revenue < 0
