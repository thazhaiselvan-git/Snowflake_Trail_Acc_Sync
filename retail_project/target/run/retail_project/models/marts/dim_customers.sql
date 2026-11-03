
  
    

        create or replace transient table RETAIL_DBT.DEV.dim_customers
         as
        (

select
    c.customer_key,
    c.customer_name,
    c.market_segment,
    c.account_balance,
    n.nation_name,
    n.region_name,
    rm.manager_name as region_manager
from RETAIL_DBT.DEV.stg_customers c
left join RETAIL_DBT.DEV.stg_nations n
    on c.nation_key = n.nation_key
left join RETAIL_DBT.DEV.region_managers rm
    on n.region_name = rm.region_name
        );
      
  