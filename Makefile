# Makefile для проекта Laravel Docker

# Переменные
ifneq (,$(shell command -v docker-compose 2> /dev/null))
	DOCKER_COMPOSE := docker-compose
else
	DOCKER_COMPOSE := docker compose
endif
CONTAINER_NAME=app

# Команды
.PHONY: install up migrate refresh down fulldown update pull shell test help tinker

help:
	@echo "Commands:"
	@echo "  make install  - Run bash-script first settings (start.sh)"
	@echo "  make up       - Run containers"
	@echo "  make migrate  - Run migrate and seed"
	@echo "  make refresh  - Run refresh and seed"
	@echo "  make down     - Stop and delete containers"
	@echo "  make fulldown - Stop and delete containers, volumes, images"
	@echo "  make tinker   - Run artisan Tinker"
	@echo "  make update   - Soft update app"
	@echo "  make pull     - Hard update app"
	@echo "  make shell    - Enter console containers"
	@echo "  make test     - Run tests"

up:
	$(DOCKER_COMPOSE) up -d --build

down:
	$(DOCKER_COMPOSE) down

fulldown:
	$(DOCKER_COMPOSE) down -v --rmi all

tinker:
	$(DOCKER_COMPOSE) exec $(CONTAINER_NAME) php artisan tinker

pull:
	git pull
	$(DOCKER_COMPOSE) exec -T $(CONTAINER_NAME) composer install
	$(MAKE) refresh
	$(DOCKER_COMPOSE) exec -T $(CONTAINER_NAME) php artisan config:clear
	$(DOCKER_COMPOSE) exec -T $(CONTAINER_NAME) php artisan route:clear
	$(DOCKER_COMPOSE) exec -T $(CONTAINER_NAME) php artisan view:clear

update:
	git pull
	$(DOCKER_COMPOSE) exec -T $(CONTAINER_NAME) composer install
	$(MAKE) migrate
	$(DOCKER_COMPOSE) exec -T $(CONTAINER_NAME) php artisan config:clear
	$(DOCKER_COMPOSE) exec -T $(CONTAINER_NAME) php artisan route:clear
	$(DOCKER_COMPOSE) exec -T $(CONTAINER_NAME) php artisan view:clear

shell:
	$(DOCKER_COMPOSE) exec $(CONTAINER_NAME) bash

install:
	./start.sh

migrate:
	$(DOCKER_COMPOSE) exec -T $(CONTAINER_NAME) php artisan migrate --force
	$(DOCKER_COMPOSE) exec -T $(CONTAINER_NAME) php artisan db:seed --force

refresh:
	$(DOCKER_COMPOSE) exec -T $(CONTAINER_NAME) php artisan migrate:fresh --seed --force

test:
	$(DOCKER_COMPOSE) exec -T $(CONTAINER_NAME) php artisan test
