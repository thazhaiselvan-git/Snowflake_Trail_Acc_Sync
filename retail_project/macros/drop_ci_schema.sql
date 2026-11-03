{% macro drop_ci_schema(schema) %}
    {% if not schema.upper().startswith('CI_') %}
        {{ exceptions.raise_compiler_error("Refusing to drop non-CI schema: " ~ schema) }}
    {% endif %}
    {% do run_query("DROP SCHEMA IF EXISTS " ~ target.database ~ "." ~ schema ~ " CASCADE") %}
    {{ log("Dropped " ~ target.database ~ "." ~ schema, info=True) }}
{% endmacro %}
