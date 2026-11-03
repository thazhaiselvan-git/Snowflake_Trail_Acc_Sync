
  create or replace   view RETAIL_DBT.DEV.stg_lineitems
  
   as (
    select
    l_orderkey      as order_key,
    l_linenumber    as line_number,
    l_partkey       as part_key,
    l_quantity      as quantity,
    l_extendedprice as extended_price,
    l_discount      as discount,
    l_tax           as tax,
    l_shipdate      as ship_date
from RETAIL_DBT.RAW.lineitems
  );

