#!/bin/bash
set -e

# Удаляем origin только если это Git-репозиторий
if [ -d .git ]; then
    if git remote | grep -q "^origin$"; then
        echo "Removing existing Git remote 'origin'..."
        git remote remove origin
    fi
fi

echo "Starting Laravel Docker project..."

# Определяем использовать 'docker-compose' или 'docker compose'
if command -v docker-compose &> /dev/null; then
    DOCKER_COMPOSE="docker-compose"
else
    DOCKER_COMPOSE="docker compose"
fi

# Переименовываем README.md в резервную копию
#if [ -f README.md ]; then
#    mv README.md README.md.bak
#    echo "Renamed README.md → README.md.bak"
#fi

# Создаём .env из примера, если его нет
if [ ! -f .env ]; then
    cp src/.env.example src/.env
    echo "Created .env from .env.example"
fi

# Запускаем контейнеры в фоне
$DOCKER_COMPOSE up -d

# Ждём готовности MySQL (максимум 30 секунд)
echo "Waiting for MySQL to be ready..."

# Загружаем переменные из .env
if [ -f src/.env ]; then
    export $(grep -v '^#' src/.env | xargs)
fi

DB_USERNAME=${DB_USERNAME:-laravel}
DB_PASSWORD=${DB_PASSWORD:-password}

timeout=30
counter=0
until $DOCKER_COMPOSE exec -T db mysql -u "$DB_USERNAME" -p"$DB_PASSWORD" -e "SELECT 1;" > /dev/null 2>&1; do
    counter=$((counter+1))
    if [ $counter -ge $timeout ]; then
        echo "MySQL did not start in time"
        exit 1
    fi
    sleep 1
done
echo "MySQL is ready"

# Устанавливаем зависимости (если vendor/ отсутствует)
if [ ! -d "src/vendor" ]; then
    echo "Installing Composer dependencies..."
    $DOCKER_COMPOSE exec -T app composer install --no-interaction --prefer-dist --optimize-autoloader
fi

# Генерируем APP_KEY (если он пустой или отсутствует)
if grep -q "APP_KEY=" src/.env && [ -z "$(grep "APP_KEY=" src/.env | cut -d '=' -f2)" ]; then
    echo "Generating APP_KEY..."
    $DOCKER_COMPOSE exec -T app php artisan key:generate --ansi
elif ! grep -q "APP_KEY=" src/.env; then
    echo "APP_KEY not found in .env — generating..."
    $DOCKER_COMPOSE exec -T app php artisan key:generate --ansi
else
    echo "APP_KEY already set"
fi

# Запускаем миграции и сиды
echo "Running migrations..."
$DOCKER_COMPOSE exec -T app php artisan migrate --force

echo "Running seeders..."
$DOCKER_COMPOSE exec -T app php artisan db:seed --force

# Создаем симлинк на storage
echo "Linking storage..."
$DOCKER_COMPOSE exec -T app php artisan storage:link

# Настраиваем права (на всякий случай)
echo "Setting permissions..."
$DOCKER_COMPOSE exec -T app chmod -R 777 storage bootstrap/cache

echo "Laravel is ready! Visit http://localhost"
