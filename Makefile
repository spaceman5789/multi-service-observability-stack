.PHONY: up down restart logs build backup restore clean status

# --- Основные команды ---
up:
	docker compose up -d
	@echo "Stack is up. Grafana: http://localhost:3000 | App: http://localhost/"

down:
	docker compose down

restart:
	docker compose restart

build:
	docker compose build --no-cache

# --- Логи ---
logs:
	docker compose logs -f

logs-app:
	docker compose logs -f app

# --- Бэкап ---
backup:
	./scripts/backup.sh

restore:
	@echo "Usage: make restore FILE=path/to/backup.sql.gz"
	@test -n "$(FILE)" || (echo "Error: FILE is required" && exit 1)
	gunzip -c $(FILE) | docker compose exec -T postgres psql -U appuser -d appdb

# --- Статус ---
status:
	@echo "=== Containers ==="
	@docker compose ps
	@echo ""
	@echo "=== Volumes ==="
	@docker volume ls | grep multi-container
	@echo ""
	@echo "=== Networks ==="
	@docker network ls | grep multi-container

# --- Очистка ---
clean:
	docker compose down -v --rmi local
	@echo "Cleaned up containers, volumes, and local images."

# --- Быстрый тест ---
test:
	@echo "Testing endpoints..."
	@curl -sf http://localhost/ | python3 -m json.tool
	@curl -sf http://localhost/health | python3 -m json.tool
	@echo "\nAll tests passed!"
