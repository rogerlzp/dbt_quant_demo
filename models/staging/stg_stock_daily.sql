-- staging 层：把 raw seed 清洗成规范结构
-- 职责边界：只做「重命名 / 类型转换 / 基础去重 / 显式过滤」，不放业务逻辑

with source as (
    select * from {{ ref('stock_daily_seed') }}
),

cleaned as (
    select
        cast(trade_date as date)                          as trade_date,
        upper(symbol)                                    as symbol,
        cast(open  as double)                            as open_price,
        cast(high  as double)                            as high_price,
        cast(low   as double)                            as low_price,
        cast(close as double)                            as close_price,
        cast(volume as bigint)                           as volume,
        cast(amount as bigint)                           as amount,
        cast(main_net_inflow as double)                  as main_net_inflow,
        -- 派生：日内振幅，用于下游质量校验
        round((high_price - low_price) / nullif(low_price, 0), 6) as intraday_range
    from source
    -- 幂等去重：同一 symbol + trade_date 只保留一条（生产用 unique-key 语义）
    where trade_date is not null
      and symbol is not null
      and close_price > 0
    qualify row_number() over (
        partition by symbol, trade_date
        order by close_price desc
    ) = 1
)

select * from cleaned
