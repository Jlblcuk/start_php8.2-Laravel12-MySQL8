# Установка и запуск проекта

```bash
git clone https://github.com/Jlblcuk/start_php8.2-Laravel12-MySQL8
```
```bash
cd start_php8.2-Laravel12-MySQL8
```
```bash
make install
```
или
```bash
./start.sh
```
---
Скрипт start.sh:
1. Удалит ссылку на удалённый репозиторий
2. Создаст .env файл из .env.example
3. Запустит контейнеры Docker
4. По готовности MySQL запустит установку зависимостей
5. Сгенерирует APP_KEY
6. Запустит миграции и сиды
7. По готовности приложения выведет сообщение: "Laravel is ready! Visit http://localhost"
