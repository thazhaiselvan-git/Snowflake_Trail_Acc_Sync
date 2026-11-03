select
      count(*) as failures,
      count(*) != 0 as should_warn,
      count(*) != 0 as should_error
    from (
      
    
    



select region_manager
from RETAIL_DBT.PROD.dim_customers
where region_manager is null



      
    ) dbt_internal_test