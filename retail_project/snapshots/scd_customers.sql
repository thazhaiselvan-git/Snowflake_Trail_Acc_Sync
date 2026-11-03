-- SCD Type 2 using the TIMESTAMP strategy: a new version is recorded when updated_at moves forward.
{% snapshot scd_customers %}
{{ config(
    target_schema=target.schema,
    unique_key='c_custkey',
    strategy='timestamp',
    updated_at='updated_at',
    invalidate_hard_deletes=True
) }}
select * from {{ source('retail', 'customers') }}
{% endsnapshot %}
