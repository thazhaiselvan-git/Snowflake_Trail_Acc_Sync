
  create or replace   view RETAIL_DBT.DEV.stg_nations
  
   as (
    select
    n.n_nationkey as nation_key,
    n.n_name      as nation_name,
    r.r_regionkey as region_key,
    r.r_name      as region_name
from RETAIL_DBT.RAW.nations n
join RETAIL_DBT.RAW.regions r
    on n.n_regionkey = r.r_regionkey
  );

