
    
    

select
    customer_key as unique_field,
    count(*) as n_records

from RETAIL_DBT.DEV.dim_customers
where customer_key is not null
group by customer_key
having count(*) > 1


