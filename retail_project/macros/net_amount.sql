{% macro net_amount(price_col, discount_col, scale=2) -%}
    round({{ price_col }} * (1 - {{ discount_col }}), {{ scale }})
{%- endmacro %}
