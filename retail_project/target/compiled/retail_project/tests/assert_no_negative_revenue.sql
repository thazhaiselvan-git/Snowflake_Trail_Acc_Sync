-- Singular test: returns rows that FAIL. Passes when no order has negative revenue.
select order_key, net_revenue
from RETAIL_DBT.DEV.fct_orders
where net_revenue < 0