select
    customer_id,
    initcap(name)  as customer_name,
    region,
    tier,
    updated_at
from {{ source('raw', 'customers') }}
