-- staging 层：因子值

with source as (
    select * from {{ ref('factor_values_seed') }}
),

cleaned as (
    select
        cast(trade_date as date)  as trade_date,
        upper(symbol)             as symbol,
        cast(factor_momentum_20  as double) as factor_momentum_20,
        cast(factor_volatility_20 as double) as factor_volatility_20,
        cast(factor_value_pb      as double) as factor_value_pb
    from source
    where trade_date is not null
      and symbol is not null
    qualify row_number() over (
        partition by symbol, trade_date
        order by factor_momentum_20 desc
    ) = 1
)

select * from cleaned
