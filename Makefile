# BrandGuard — one documented way to do every common thing.
DB_URL ?= postgresql://brandguard:brandguard@localhost:5432/brandguard

.PHONY: help setup up down logs db db-test api app app-web apk test lint clean

help:
	@grep -hE '^[a-zA-Z-]+:.*##' $(MAKEFILE_LIST) | awk 'BEGIN{FS=":.*## "}{printf "  \033[36m%-10s\033[0m %s\n",$$1,$$2}'

setup: ## install everything (python deps + flutter packages)
	cd backend && pip install -r requirements.txt
	cd frontend && flutter pub get

up: ## start PostgreSQL and wait until it accepts connections
	docker compose up -d
	@printf "waiting for postgres"; \
	for i in $$(seq 1 60); do \
	  if docker compose exec -T db pg_isready -U brandguard -d brandguard >/dev/null 2>&1; then echo " ready"; exit 0; fi; \
	  printf "."; sleep 1; \
	done; echo " timed out"; exit 1

down: ## stop PostgreSQL (keeps data)
	docker compose down

logs: ## follow database logs
	docker compose logs -f db

db: ## apply schema, functions and seed in order
	psql "$(DB_URL)" -v ON_ERROR_STOP=1 -q -f database/001_schema.sql
	psql "$(DB_URL)" -v ON_ERROR_STOP=1 -q -f database/002_functions.sql
	psql "$(DB_URL)" -v ON_ERROR_STOP=1 -q -f database/003_seed.sql
	@echo "database ready"

db-test: ## run the schema assertions (nothing is left behind)
	psql "$(DB_URL)" -v ON_ERROR_STOP=1 -q -f database/tests/001_assertions.sql

api: ## run the API on http://localhost:8000
	cd backend && python -m uvicorn app.main:app --reload --port 8000

app: ## run the Flutter app on a connected device or emulator
	cd frontend && flutter run

app-web: ## run the same app in Chrome
	cd frontend && flutter run -d chrome

apk: ## build a release APK
	cd frontend && flutter build apk --release

test: ## backend tests + flutter analyze
	cd backend && python -m pytest -q
	cd frontend && flutter analyze

lint: ## formatting and analysis
	cd backend && python -m compileall -q app
	cd frontend && dart format --set-exit-if-changed lib && flutter analyze

clean: ## remove build output
	rm -rf frontend/build frontend/.dart_tool
	find . -name __pycache__ -type d -prune -exec rm -rf {} +
