
    
    

select
    status_code as unique_field,
    count(*) as n_records

from RETAIL_DBT.DEV.order_status_lookup
where status_code is not null
group by status_code
having count(*) > 1


