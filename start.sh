#!/bin/bash
set -e

# Удаляем origin только если это Git-репозиторий
if [ -d .git ]; then
    if git remote | grep -q "^origin$"; then
        echo "Removing existing Git remote 'origin'..."
        git remote remove origin
    fi
fi

# Определяем использовать 'docker-compose' или 'docker compose'
if command -v docker-compose &> /dev/null; then
    DOCKER_COMPOSE="docker-compose"
else
    DOCKER_COMPOSE="docker compose"
fi

echo "Starting Laravel Docker project..."

# Переименовываем README.md в резервную копию
if [ -f README.md ]; then
    mv README.md README.md.bak
    echo "Renamed README.md → README.md.bak"
fi

# Создаём .env из примера, если его нет

if [ ! -f src/.env ]; then
  echo "Settings new project..."

  # --- Название проекта ---
  read -p "Название проекта (используется для БД, по умолчанию: myapp): " PROJECT_NAME
  PROJECT_NAME=${PROJECT_NAME:-myapp}
  PROJECT_NAME=$(echo "$PROJECT_NAME" | tr '[:upper:]' '[:lower:]' | tr -cd 'a-z0-9_-')

  # --- БД ---
  DB_DATABASE="${PROJECT_NAME}_db"
  DB_USERNAME="${PROJECT_NAME}_user"
  DB_PASSWORD=$(openssl rand -base64 16 | tr -d '+/' | cut -c1-12)
  DB_ROOT_PASSWORD=$(openssl rand -base64 24 | cut -c1-16)

  # --- Админка (опционально) ---
    while true; do
      read -p "Email администратора (оставьте пустым, чтобы пропустить): " ADMIN_EMAIL
      if [ -z "$ADMIN_EMAIL" ]; then
        break
      elif [[ "$ADMIN_EMAIL" =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
        break
      else
        echo "Некорректный email. Попробуйте снова или оставьте пустым."
      fi
    done

    if [ -n "$ADMIN_EMAIL" ]; then
        while true; do
          read -s -p "Пароль администратора (минимум 8 символов, заглавная буква и цифра): " ADMIN_PASSWORD
          echo
          if [[ ${#ADMIN_PASSWORD} -ge 8 ]] && [[ "$ADMIN_PASSWORD" == *[A-Z]* ]] && [[ "$ADMIN_PASSWORD" == *[0-9]* ]]; then
            break
          else
            echo "Требования: 8+ символов, заглавная буква, цифра."
          fi
        done
      fi

    # --- APP_URL ---
      if command -v ipconfig >/dev/null 2>&1; then
        LOCAL_IP=$(ipconfig | grep "IPv4" | head -1 | awk '{print $NF}' 2>/dev/null || echo "localhost")
      elif command -v ip >/dev/null 2>&1; then
        LOCAL_IP=$(ip addr show 2>/dev/null | grep 'inet ' | grep -v '127.0.0.1' | head -1 | awk '{print $2}' | cut -d'/' -f1 || echo "localhost")
      else
        LOCAL_IP="localhost"
      fi
      read -p "APP_URL (default: http://localhost): " APP_URL_INPUT
      APP_URL=${APP_URL_INPUT:-http://localhost}

      cp src/.env.example src/.env

    # Подстановка базовых значений
        sed -i.bak \
          -e "s|DB_DATABASE=.*|DB_DATABASE=$DB_DATABASE|" \
          -e "s|DB_USERNAME=.*|DB_USERNAME=$DB_USERNAME|" \
          -e "s|DB_PASSWORD=.*|DB_PASSWORD=$DB_PASSWORD|" \
          -e "s|DB_ROOT_PASSWORD=.*|DB_ROOT_PASSWORD=$DB_ROOT_PASSWORD|" \
          -e "s|APP_NAME=.*|APP_NAME=$PROJECT_NAME|" \
          -e "s|APP_URL=.*|APP_URL=$APP_URL|" \
          src/.env

    # Подстановка админки (если задана)
        if [ -n "$ADMIN_EMAIL" ]; then
          sed -i.bak \
            -e "s|#*ADMIN_EMAIL=.*|ADMIN_EMAIL=$ADMIN_EMAIL|" \
            -e "s|#*ADMIN_PASSWORD=.*|ADMIN_PASSWORD=$ADMIN_PASSWORD|" \
            src/.env
        fi

    echo "Created .env from .env.example"
fi

# Запускаем контейнеры в фоне
$DOCKER_COMPOSE --env-file src/.env up -d

# Ждём готовности MySQL (максимум 60 секунд)
echo "Waiting for MySQL to be ready..."

DB_CONTAINER_NAME=$($DOCKER_COMPOSE ps -q db 2>/dev/null || echo "laravel-db")

# Загружаем все переменные из .env (если есть)
if [ -f src/.env ]; then
  while IFS='=' read -r key value; do
    if [[ "$key" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]]; then
      export "$key=$value"
    fi
  done < <(grep -E '^[A-Za-z_][A-Za-z0-9_]*=' src/.env)
fi

# Устанавливаем значения по умолчанию, если не заданы
DB_USERNAME=${DB_USERNAME:-app_user}
DB_PASSWORD=${DB_PASSWORD:-secret}

timeout=120
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

# Устанавливаем зависимости, если vendor/autoload.php отсутствует
if ! $DOCKER_COMPOSE exec -T app test -f /var/www/vendor/autoload.php; then
    echo "Installing Composer dependencies..."
    $DOCKER_COMPOSE exec -T app composer install --no-interaction --prefer-dist --optimize-autoloader
fi

# Генерируем APP_KEY (если он пустой или отсутствует)
APP_KEY_LINE=$(grep "^APP_KEY=" src/.env | head -n1)
if [ -z "$APP_KEY_LINE" ]; then
    echo "APP_KEY not found — generating..."
    $DOCKER_COMPOSE exec -T app php artisan key:generate --ansi
else
    # Удаляем 'APP_KEY=', кавычки, пробелы
    APP_KEY_CLEAN=$(echo "$APP_KEY_LINE" | sed 's/^APP_KEY=[[:space:]]*//; s/["'\'' ]*$//; s/^[[:space:]]*//')
    if [ -z "$APP_KEY_CLEAN" ]; then
        echo "APP_KEY is empty — generating..."
        $DOCKER_COMPOSE exec -T app php artisan key:generate --ansi
    else
        echo "APP_KEY already set"
    fi
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

echo "Laravel is ready! Visit: $APP_URL"
