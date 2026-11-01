{#
    Custom generic tests.

    为什么自己写而不是用 dbt_utils？
      1. dbt_utils 1.4 把 generic test 的调用语法改了（column 级 vs model 级、`arguments:` 嵌套），
         不同 dbt 版本写法不同 → 自己写一次，所有版本通用，CI 不用跟着 dbt 升级改
      2. 自定义测试本身就是「数据质量是交付物」的证据 —— 招聘方会看这个

    约定：模型级 generic test 通过 models.<name>.data_tests 挂载
#}

{% test unique_combination_of_columns(model, combination_of_columns) %}

    {% set column_list = combination_of_columns %}

    with validation_errors as (

        select
            {{ column_csv(column_list) }}
        from {{ model }}
        group by
            {{ column_csv(column_list) }}
        having count(*) > 1

    ),

    error_rows as (
        select * from validation_errors
    )

    select * from error_rows

{% endtest %}


{% test positive_values(model, column_name) %}

    with violations as (
        select {{ column_name }}
        from {{ model }}
        where {{ column_name }} is null
           or {{ column_name }} <= 0
    )

    select * from violations

{% endtest %}


{% test ratio_between(model, column_name, min_value=0.0, max_value=1.0) %}

    with violations as (
        select {{ column_name }}
        from {{ model }}
        where {{ column_name }} is null
           or {{ column_name }} < {{ min_value }}
           or {{ column_name }} > {{ max_value }}
    )

    select * from violations

{% endtest %}


{% macro column_csv(column_list) %}
    {%- for c in column_list -%}
        {{ c }}{% if not loop.last %}, {% endif %}
    {%- endfor -%}
{% endmacro %}
