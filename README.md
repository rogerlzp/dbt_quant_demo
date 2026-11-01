# dbt_quant_demo

A runnable **dbt** project that turns raw market data into a scored, quality-gated analytics mart — on **DuckDB**, so it costs nothing and runs in seconds.

This is the analytics-engineering counterpart to [`panda_factor`](https://github.com/rogerlzp/panda_factor): the same factor panel, expressed as a **transformation layer** instead of Python functions.

```
dbt_quant_demo/
├── dbt_project.yml            # 项目配置：materialization / tags / vars
├── profiles.yml               # DuckDB 连接（本地文件，零外部依赖）
├── packages.yml               # dbt_utils
├── seeds/                     # 原始数据（模拟生产 stock_daily / factor_values）
│   ├── stock_daily_seed.csv
│   ├── factor_values_seed.csv
│   └── seeds.yml
├── models/
│   ├── staging/               # 清洗层：重命名 / 类型转换 / 去重
│   │   ├── stg_stock_daily.sql
│   │   └── stg_factor_values.sql
│   ├── intermediate/          # 中间层：窗口计算 + 事实表对齐
│   │   └── int_daily_factor_panel.sql
│   ├── marts/                 # 消费层：语义指标 + 数据质量表
│   │   ├── factor_score_daily.sql
│   │   └── data_quality_daily.sql
│   └── schema.yml             # 全部模型的唯一权威描述
├── macros/
│   └── quality_tests.sql      # 自定义 generic test
└── tests/                     # 单例测试（singular tests）
    ├── assert_factor_coverage_above_threshold.yml
    ├── assert_scored_rows_match_symbols.yml
    └── assert_composite_score_bounds.yml
```

---

## The three-layer convention

| Layer | Materialization | Responsibility | Rule |
|---|---|---|---|
| **staging** | view | rename, cast, dedupe, explicit filters | **no business logic** |
| **intermediate** | view | window metrics, joins, one row per grain | **one grain, clearly named** |
| **marts** | table | semantic metrics, consumption-ready | **the only layer analysts touch** |

This is not decoration. When every model is a view, nobody can tell where a number came from. When staging holds only cleanup, a bug in a mart is unambiguously a modelling bug.

---

## Run it

```bash
python -m venv .venv && source .venv/bin/activate
pip install "dbt-duckdb>=1.7,<1.8"

cd dbt_quant_demo
export DBT_PROFILES_DIR="$PWD"

dbt deps        # pull dbt_utils
dbt seed --full-refresh
dbt build       # models + tests
dbt docs generate && dbt docs serve   # browsable docs site
```

Verified on **dbt-core 1.7.20 + dbt-duckdb 1.7.5** (Python 3.12, macOS arm64): `PASS=32 WARN=0 ERROR=0`.

> **Version note:** dbt-core ≥ 1.8 pulls `dbt-core-experimental-parser`, a Rust extension published **as sdist only** — on macOS arm64 it must be built from source, and the build backend downloads a prebuilt wheel from GitHub Releases, which fails on restricted networks. dbt-core 1.7.x has **pure-Python wheels for every dependency** and installs cleanly. If you need dbt ≥ 1.8, pre-install the parser wheel from the [dbt releases page](https://github.com/dbt-labs/dbt/releases) or use `pip install "dbt-core>=1.8" --no-build-isolation`.

---

## What the models actually do

**`stg_stock_daily`** — cleans the raw feed. Note the idempotency guard:

```sql
qualify row_number() over (
    partition by symbol, trade_date
    order by close_price desc
) = 1
```

**`int_daily_factor_panel`** — the fact table. One row per `(trade_date, symbol)`. Window functions mirror `panda_factor`'s operator semantics:

```sql
avg(close_price) over (
    partition by symbol order by trade_date
    rows between {{ var('ma_window') - 1 }} preceding and current row
) as ma_{{ var('ma_window') }},

stddev_samp(close_price) over (...) / nullif(avg(close_price) over (...), 0)
  * sqrt(252) as volatility_annualized
```

**`factor_score_daily`** — the semantic layer. Raw factor values become cross-sectional percent ranks, then one defined metric:

```sql
round(
    momentum_pct_rank * 0.4
  + value_pct_rank     * 0.3
  + moneyflow_pct_rank * 0.3
, 6) as composite_score,

ntile(5) over (partition by trade_date order by ...) as score_bucket
```

The point of a mart like this: *"what is a good factor?"* is defined **once**, in SQL, with a weight. Not re-derived in every dashboard, notebook, and ad-hoc query.

**`data_quality_daily`** — data quality as a **model**, not a spreadsheet. Missing-row counts and coverage ratios per day, ready to be alerted on.

---

## Data quality as a first-class citizen

### Model-level generic tests

```yaml
- name: factor_score_daily
  tests:
    - unique_combination_of_columns:
        combination_of_columns: ['trade_date', 'symbol']
  columns:
    - name: composite_score
      tests:
        - ratio_between: { min_value: 0.0, max_value: 1.0 }
```

### Custom generic tests (`macros/quality_tests.sql`)

`unique_combination_of_columns`, `positive_values`, `ratio_between` — written locally instead of pulled from `dbt_utils`, because `dbt_utils` changed its generic-test call syntax between versions and a CI that breaks on every dbt upgrade is a bad trade.

### Singular tests (`tests/`)

Cross-row business invariants that a column-level test cannot express:

| Test | Asserts |
|---|---|
| `assert_factor_coverage_above_threshold` | no day's factor coverage falls below `var('min_coverage_ratio')` |
| `assert_scored_rows_match_symbols` | scored row count == symbol count per day (catches **silent join drops**) |
| `assert_composite_score_bounds` | `composite_score ∈ [0,1]` and `score_bucket ∈ [1,5]` |

The second one is the important one. A join that drops rows does not error — it just returns fewer rows and quietly changes every downstream number. This test is the difference between "the pipeline ran" and "the pipeline ran correctly".

---

## Docs are generated from the code

`schema.yml` is the single source of truth for every model and column. `dbt docs generate` produces a browsable site with the lineage graph — models, their tests, and their column-level documentation.

That means the documentation cannot drift from the code: change a model, regenerate, and the docs are correct by construction.

---

## Why DuckDB

Zero cost, zero infrastructure, and fast enough to run in CI.

- The same project runs against Snowflake / BigQuery / Postgres by changing `profiles.yml` — the models are warehouse-agnostic SQL
- dbt-duckdb is a local adapter: no warehouse account, no billing, no waiting

That matters for a portfolio project: a reviewer can clone and run it in one minute.

---

## Related

- [`panda_factor`](https://github.com/rogerlzp/panda_factor) — the same factor computation in Python (operators, strategies, backtest metrics)
- [`mcp_quant_server`](https://github.com/rogerlzp/mcp_quant_server) — an MCP server that lets an LLM agent query the mart this project builds, read-only

The three together tell one story: **compute (pandas) → transform (dbt) → serve to agents (MCP)**, which is exactly the shape of a modern data platform.

---

## License

MIT

---

## Verified build

```
dbt seed --full-refresh   →  PASS=2  WARN=0  ERROR=0
dbt build                 →  PASS=32 WARN=0  ERROR=0
```

Run on dbt-core 1.7.20 + dbt-duckdb 1.7.5, Python 3.12, macOS arm64.
