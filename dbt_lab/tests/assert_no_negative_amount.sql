-- Singular test: any returned row = failure
select * from {{ ref('fct_orders') }} where amount < 0
