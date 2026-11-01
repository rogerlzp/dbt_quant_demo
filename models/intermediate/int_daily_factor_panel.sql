-- intermediate 层：把行情与因子对齐，补齐窗口指标
-- 这是「事实表」：每 (trade_date, symbol) 一行，行情指标 + 因子值

with prices as (
    select * from {{ ref('stg_stock_daily') }}
),

factors as (
    select * from {{ ref('stg_factor_values') }}
),

-- 窗口计算：动量与波动率。语义与 panda_factor 的 MA/STD 算子一致
price_metrics as (
    select
        trade_date,
        symbol,
        close_price,
        volume,
        amount,
        main_net_inflow,
        intraday_range,

        -- 20 日移动平均
        avg(close_price) over (
            partition by symbol order by trade_date
            rows between {{ var('ma_window') - 1 }} preceding and current row
        ) as ma_{{ var('ma_window') }},

        -- 20 日收益波动率（年化，按 252 交易日）
        stddev_samp(close_price) over (
            partition by symbol order by trade_date
            rows between {{ var('ma_window') - 1 }} preceding and current row
        ) / nullif(avg(close_price) over (
            partition by symbol order by trade_date
            rows between {{ var('ma_window') - 1 }} preceding and current row
        ), 0) * sqrt(252) as volatility_annualized,

        -- 日收益率
        close_price / nullif(
            lag(close_price) over (partition by symbol order by trade_date), 0
        ) - 1 as daily_return

    from prices
)

select
    pm.*,
    f.factor_momentum_20,
    f.factor_volatility_20,
    f.factor_value_pb
from price_metrics pm
left join factors f
    on pm.trade_date = f.trade_date
   and pm.symbol = f.symbol
