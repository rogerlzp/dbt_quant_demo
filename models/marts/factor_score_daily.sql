-- mart 层：给「分析师/投研」直接消费的宽表
-- 语义层指标：把「什么是好因子」定义成可复用指标，而不是散落在各处的口径

with panel as (
    select * from {{ ref('int_daily_factor_panel') }}
),

scored as (
    select
        trade_date,
        symbol,
        close_price,
        volume,
        amount,
        main_net_inflow,
        ma_{{ var('ma_window') }},
        volatility_annualized,
        daily_return,
        factor_momentum_20,
        factor_volatility_20,
        factor_value_pb,

        -- 横截面排名：把绝对因子值转成当日全市场分位
        percent_rank() over (
            partition by trade_date order by factor_momentum_20
        ) as momentum_pct_rank,

        percent_rank() over (
            partition by trade_date order by factor_value_pb
        ) as value_pct_rank,

        -- 资金流强度：标准化到横截面
        percent_rank() over (
            partition by trade_date order by main_net_inflow
        ) as moneyflow_pct_rank

    from panel
    where factor_momentum_20 is not null
)

select
    *,

    -- 综合评分：动量 40% + 价值 30% + 资金流 30%
    round(
        momentum_pct_rank * 0.4
      + value_pct_rank     * 0.3
      + moneyflow_pct_rank * 0.3
    , 6) as composite_score,

    -- 组合分组：按综合评分分 5 档（等价于量化选股的分组逻辑）
    ntile(5) over (
        partition by trade_date order by momentum_pct_rank * 0.4
                                 + value_pct_rank     * 0.3
                                 + moneyflow_pct_rank * 0.3
    ) as score_bucket

from scored
