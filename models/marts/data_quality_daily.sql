-- mart 层：数据质量看板
-- 真实生产里，「数据质量」本身就是交付物；这里用 dbt test + 一张可查询的覆盖度表来表达

with panel as (
    select * from {{ ref('int_daily_factor_panel') }}
),

coverage as (
    select
        trade_date,
        count(distinct symbol)                              as symbols_present,
        count(*) filter (where factor_momentum_20 is null)  as missing_factor_rows,
        count(*) filter (where close_price is null)         as missing_price_rows,
        count(*) filter (where main_net_inflow is null)      as missing_moneyflow_rows
    from panel
    group by trade_date
),

scored as (
    select * from {{ ref('factor_score_daily') }}
)

select
    c.trade_date,
    c.symbols_present,
    c.missing_factor_rows,
    c.missing_price_rows,
    c.missing_moneyflow_rows,
    -- 因子覆盖率：非空因子行 / 总行数
    round(
        1.0 - (c.missing_factor_rows::double / nullif(c.symbols_present, 0))
    , 4) as factor_coverage_ratio,
    count(s.symbol) as scored_rows,
    round(avg(s.composite_score), 4) as avg_composite_score
from coverage c
left join scored s on c.trade_date = s.trade_date
group by all
