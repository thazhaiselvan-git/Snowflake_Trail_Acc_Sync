select
      count(*) as failures,
      count(*) != 0 as should_warn,
      count(*) != 0 as should_error
    from (
      
    
    

select
    region_name as unique_field,
    count(*) as n_records

from RETAIL_DBT.DEV.region_managers
where region_name is not null
group by region_name
having count(*) > 1



      
    ) dbt_internal_test