
      
  
    

        create or replace transient table RETAIL_DBT.DEV.scd_customers
         as
        (
    

    select *,
        md5(coalesce(cast(c_custkey as varchar ), '')
         || '|' || coalesce(cast(updated_at as varchar ), '')
        ) as dbt_scd_id,
        updated_at as dbt_updated_at,
        updated_at as dbt_valid_from,
        
  
  coalesce(nullif(updated_at, updated_at), null)
  as dbt_valid_to
from (
        

select * from RETAIL_DBT.RAW.customers
    ) sbq



        );
      
  
  