
  
    

        create or replace transient table RETAIL_DBT.PROD.mart_sales_by_region
         as
        (

select
    c.region_name,
    c.region_manager,
    year(f.order_date)       as order_year,
    count(distinct f.order_key)    as orders,
    count(distinct f.customer_key) as customers,
    sum(f.net_revenue)       as net_revenue
from RETAIL_DBT.PROD.fct_orders f
join RETAIL_DBT.PROD.dim_customers c
    on f.customer_key = c.customer_key
group by 1, 2, 3
        );
      
  