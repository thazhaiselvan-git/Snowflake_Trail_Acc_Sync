select
      count(*) as failures,
      count(*) != 0 as should_warn,
      count(*) != 0 as should_error
    from (
      -- Singular test: returns rows that FAIL. Passes when no order has negative revenue.
select order_key, net_revenue
from RETAIL_DBT.PROD.fct_orders
where net_revenue < 0
      
    ) dbt_internal_test