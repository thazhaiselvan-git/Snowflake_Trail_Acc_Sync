
        

    
        create dynamic table RETAIL_DBT.PROD.dt_daily_revenue
        target_lag = '1 day'
        warehouse = DBT_WH
        refresh_mode = FULL

        initialize = ON_CREATE

        as (
            -- Snowflake dynamic table: Snowflake refreshes it on its own within target_lag.
-- refresh_mode FULL avoids needing change tracking on the RAW tables (DBT_ROLE doesn't own them).


select
    order_date,
    count(*)         as orders,
    sum(total_price) as gross_revenue
from RETAIL_DBT.PROD.stg_orders
group by order_date
        )

    


    