{% snapshot customers_snapshot %}
{{ config(
    target_schema='DEV',
    unique_key='customer_id',
    strategy='timestamp',
    updated_at='updated_at'
) }}
select * from {{ source('raw', 'customers') }}
{% endsnapshot %}
