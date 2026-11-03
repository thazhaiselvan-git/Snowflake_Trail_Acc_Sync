-- SCD Type 2 using the CHECK strategy: a new version is recorded whenever status or price changes.
{% snapshot scd_orders %}
{{ config(
    target_schema=target.schema,
    unique_key='o_orderkey',
    strategy='check',
    check_cols=['o_orderstatus', 'o_totalprice']
) }}
select * from {{ source('retail', 'orders') }}
{% endsnapshot %}
