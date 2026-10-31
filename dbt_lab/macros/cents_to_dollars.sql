{% macro cents_to_dollars(col, scale=2) %}
    round({{ col }} / 100, {{ scale }})
{% endmacro %}
