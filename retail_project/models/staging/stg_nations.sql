select
    n.n_nationkey as nation_key,
    n.n_name      as nation_name,
    r.r_regionkey as region_key,
    r.r_name      as region_name
from {{ source('retail', 'nations') }} n
join {{ source('retail', 'regions') }} r
    on n.n_regionkey = r.r_regionkey
