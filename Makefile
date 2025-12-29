# Makefile для проекта Laravel Docker

# Переменные
ifneq (,$(shell command -v docker-compose 2> /dev/null))
	DOCKER_COMPOSE := docker-compose
else
	DOCKER_COMPOSE := docker compose
endif

# Команды
.PHONY: install up migrate refresh down fulldown  build shell test help

help:
	@echo "Commands:"
	@echo "  make install  - Run bash-script first settings (start.sh)"
	@echo "  make up       - Run containers"
	@echo "  make migrate  - Run migrate and seed"
	@echo "  make refresh  - Run refresh and seed"
	@echo "  make down     - Stop and delete containers"
	@echo "  make fulldown - Stop and delete containers, volumes, images"
	@echo "  make build    - Build containers"
	@echo "  make shell    - Enter console containers"
	@echo "  make test     - Run tests"

up:
	$(DOCKER_COMPOSE) up -d

down:
	$(DOCKER_COMPOSE) down

fulldown:
	$(DOCKER_COMPOSE) down -v --rmi all

build:
	$(DOCKER_COMPOSE) build

shell:
	$(DOCKER_COMPOSE) exec app bash

install:
	./start.sh

migrate:
	$(DOCKER_COMPOSE) exec app php artisan migrate --force
	$(DOCKER_COMPOSE) exec -T app php artisan db:seed --force

refresh:
	$(DOCKER_COMPOSE) exec -T app php artisan migrate:fresh --seed --force

test:
	$(DOCKER_COMPOSE) exec app php artisan test
