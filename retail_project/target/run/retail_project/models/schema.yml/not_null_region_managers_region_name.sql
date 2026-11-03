select
      count(*) as failures,
      count(*) != 0 as should_warn,
      count(*) != 0 as should_error
    from (
      
    
    



select region_name
from RETAIL_DBT.DEV.region_managers
where region_name is null



      
    ) dbt_internal_test