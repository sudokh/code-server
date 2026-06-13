SHELL := /bin/bash

# .env があれば読み込む（make init 前は存在しなくてもエラーにしない）
-include .env

.DEFAULT_GOAL := help

help: ## このヘルプを表示
	@echo "Usage: make <target>"
	@echo
	@awk 'BEGIN{FS=":.*##"} /^[a-zA-Z_-]+:.*##/{printf "  %-10s %s\n", $$1, $$2}' $(MAKEFILE_LIST)

init: ## 初回セットアップ（鍵生成・.env作成・ホストへ公開鍵登録）※ホスト上で実行
	@bash scripts/init.sh

check: ## 事前点検（docker / compose / sshd / init済みか）
	@bash scripts/check.sh

up: ## 起動（ビルド込み）
	docker compose up -d --build

down: ## 停止して削除
	docker compose down

restart: ## 再起動
	$(MAKE) down && $(MAKE) up

logs: ## ログを追従表示
	docker compose logs -f --tail=100 code-server

ps: ## 稼働状況
	docker compose ps

exec: ## コンテナ内の bash に入る（ホストではなくコンテナ側）
	docker compose exec code-server bash

pull: ## code-server を最新イメージへ更新
	docker compose build --pull && docker compose up -d
