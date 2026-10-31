select
    order_id,
    customer_id,
    upper(status)                           as status,
    {{ cents_to_dollars('amount_cents') }}  as amount,
    updated_at
from {{ source('raw', 'orders') }}
