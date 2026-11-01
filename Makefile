# dbt_quant_demo —— 常用命令
DBT ?= dbt
export DBT_PROFILES_DIR = $(CURDIR)

.PHONY: deps seed build test docs clean all

all: deps build          # 完整跑
deps:                    ## 拉取 dbt_utils
	$(DBT) deps
seed:                    ## 载入原始数据
	$(DBT) seed --full-refresh
build:                   ## 跑模型 + 测试
	$(DBT) build
test:                    ## 只跑测试
	$(DBT) test
docs:                    ## 生成文档站
	$(DBT) docs generate
	$(DBT) docs serve
clean:                   ## 清理产物
	$(DBT) clean
