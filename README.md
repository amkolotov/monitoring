# Monitoring Stack - Подробная документация

## Содержание

1. [Обзор](#обзор)
2. [Архитектура](#архитектура)
3. [Сервисы](#сервисы)
   - [Prometheus](#prometheus)
   - [Grafana](#grafana)
   - [Alertmanager](#alertmanager)
   - [Loki](#loki)
   - [Promtail](#promtail)
   - [Node Exporter](#node-exporter)
   - [cAdvisor](#cadvisor)
   - [Postgres Exporter](#postgres-exporter)
   - [Redis Exporter](#redis-exporter)
   - [Celery Exporter](#celery-exporter)
   - [Blackbox Exporter](#blackbox-exporter)
   - [Flower](#flower)
   - [Portainer](#portainer)
   - [Watchtower](#watchtower)
4. [Настройка и конфигурация](#настройка-и-конфигурация)
5. [Интеграция с внешними проектами](#интеграция-с-внешними-проектами)

---

## Обзор

Monitoring Stack представляет собой комплексную систему мониторинга, собранную на базе популярных open-source инструментов. Стек обеспечивает:

- **Метрики** - сбор и хранение метрик приложений и инфраструктуры (Prometheus)
- **Визуализацию** - дашборды и графики (Grafana)
- **Логирование** - централизованный сбор и анализ логов (Loki + Promtail)
- **Алертинг** - уведомления о проблемах (Alertmanager)
- **Мониторинг инфраструктуры** - CPU, память, диск, сеть (Node Exporter, cAdvisor)
- **Мониторинг приложений** - специфичные метрики для PostgreSQL, Redis, Celery
- **Blackbox мониторинг** - проверка доступности внешних сервисов

---

## Архитектура

```
┌─────────────────┐
│   External      │
│   Projects      │───┐
└─────────────────┘   │
                      │
┌─────────────────┐   │     ┌──────────────┐
│  Node Exporter  │───┼────>│              │
└─────────────────┘   │     │              │
                      │     │  Prometheus  │<───┐
┌─────────────────┐   │     │              │    │
│    cAdvisor     │───┼────>│              │    │
└─────────────────┘   │     └──────────────┘    │
                      │            │            │
┌─────────────────┐   │            │            │
│ Postgres Exporter│───┼────────────┘            │
└─────────────────┘   │                         │
                      │            ┌─────────────┘
┌─────────────────┐   │            │
│  Redis Exporter │───┼────────────┘
└─────────────────┘   │
                      │
┌─────────────────┐   │     ┌──────────────┐
│ Celery Exporter │───┼────>│              │
└─────────────────┘   │     │   Grafana    │
                      │     │              │
┌─────────────────┐   │     │              │
│ Blackbox Exporter│───┼────>│              │
└─────────────────┘   │     └──────────────┘
                      │            │
┌─────────────────┐   │            │
│   Promtail      │───┼─────────────┼─────>┌──────────┐
└─────────────────┘   │            │      │  Loki   │
                      │            │      └──────────┘
┌─────────────────┐   │            │
│  Django /metrics│───┼────────────┘
└─────────────────┘   │
                      │
┌─────────────────┐   │     ┌──────────────┐
│   Portainer     │───┼────>│              │
└─────────────────┘   │     │ Alertmanager │
                      │     │              │
                      │     └──────────────┘
                      │            │
                      │            ▼
                      │     ┌──────────────┐
                      └────>│  Telegram    │
                            │  Slack       │
                            └──────────────┘
```

---

## Сервисы

### Prometheus

**Назначение**: Система мониторинга и временных рядов для сбора и хранения метрик.

**Что делает**:
- Регулярно опрашивает (scrape) целевые сервисы через HTTP эндпоинт `/metrics`
- Сохраняет метрики во внутреннем временном БД (TSDB)
- Выполняет правила алертинга и отправляет уведомления в Alertmanager
- Предоставляет PromQL для запросов к метрикам

**Какие данные использует**:
- **Входящие данные**:
  - Метрики из Node Exporter (CPU, память, диск, сеть хоста)
  - Метрики из cAdvisor (метрики контейнеров Docker)
  - Метрики из Postgres Exporter (статистика PostgreSQL)
  - Метрики из Redis Exporter (статистика Redis)
  - Метрики из Celery Exporter (статистика задач Celery)
  - Метрики из Blackbox Exporter (результаты HTTP/TCP проверок)
  - Метрики из Django приложений через `/metrics` эндпоинт (django-prometheus)
  - Собственные метрики Prometheus (внутренние метрики сервиса)

- **Исходящие данные**:
  - Отправляет алерты в Alertmanager (порт 9093)
  - Отдает метрики через API для Grafana (порт 9090)
  - Хранит метрики в volume `prometheus-data`

**Конфигурация**:
- Файл: `prometheus/prometheus.yml`
- Основные параметры:
  - `scrape_interval: 15s` - интервал сбора метрик
  - `evaluation_interval: 30s` - интервал оценки правил алертинга
  - `rule_files` - путь к файлам с правилами алертинга
  - `scrape_configs` - конфигурация целевых сервисов для сбора метрик

**Переменные окружения** (из `.env`):
- `PROMETHEUS_RETENTION=15d` - время хранения метрик
- `PROMETHEUS_RETENTION_SIZE=5GB` - максимальный размер хранилища
- `PROMETHEUS_EXTERNAL_URL` - внешний URL для генерации ссылок
- `PROMETHEUS_PATH=/prometheus` - путь в URL (для Traefik)

**Порты**:
- `9090` - веб-интерфейс и API

**Настройка для внешних проектов**:

1. **Django приложения** (django-prometheus):
```python
# settings.py
INSTALLED_APPS = [
    ...
    'django_prometheus',
]

MIDDLEWARE = [
    'django_prometheus.middleware.PrometheusBeforeMiddleware',
    ...
    'django_prometheus.middleware.PrometheusAfterMiddleware',
]

# urls.py
urlpatterns = [
    path('metrics', include('django_prometheus.urls')),
    ...
]
```

2. **Добавление в Prometheus** (`prometheus/prometheus.yml`):
```yaml
- job_name: django_projects
  metrics_path: /metrics
  scheme: http
  static_configs:
    - targets: ["your_project_web:8000"]
      labels:
        project: your_project
        env: prod
```

3. **Доступ к метрикам**: Prometheus автоматически опрашивает указанные цели каждые 15 секунд

**Полезные метрики**:
- `up` - доступность целевого сервиса (1 = доступен, 0 = недоступен)
- `http_requests_total` - общее количество HTTP запросов
- `http_request_duration_seconds` - длительность HTTP запросов
- `django_db_connections` - количество подключений к БД

---

### Grafana

**Назначение**: Платформа для визуализации и анализа метрик, логов и трейсов.

**Что делает**:
- Создает дашборды с графиками и визуализацией
- Подключается к Prometheus как источнику данных для метрик
- Подключается к Loki как источнику данных для логов
- Позволяет создавать алерты на основе запросов
- Хранит конфигурацию дашбордов и настроек

**Какие данные использует**:
- **Входящие данные**:
  - Метрики из Prometheus (HTTP запросы через PromQL)
  - Логи из Loki (через LogQL запросы)
  - Собственные настройки дашбордов (JSON файлы)

- **Исходящие данные**:
  - Визуализация через веб-интерфейс (порт 3000)
  - Хранит дашборды и настройки в volume `grafana-data`
  - Provisioning конфигурация из `grafana/provisioning/`

**Конфигурация**:
- Автоматическое provisioning:
  - `grafana/provisioning/datasources/` - источники данных
  - `grafana/provisioning/dashboards/` - дашборды
- Дашборды: `grafana/dashboards/`

**Переменные окружения**:
- `GRAFANA_ADMIN_USER=admin` - администратор
- `GRAFANA_ADMIN_PASSWORD` - пароль администратора
- `GRAFANA_ROOT_URL` - полный URL для доступа
- `GRAFANA_INSTALL_PLUGINS` - список плагинов для установки

**Порты**:
- `3000` - веб-интерфейс

**Настройка для внешних проектов**:

1. **Создание дашборда**:
   - Через веб-интерфейс: `/grafana` → Dashboards → New Dashboard
   - Или через файлы: создайте JSON файл в `grafana/dashboards/`

2. **Пример запроса PromQL в Grafana**:
```
rate(http_requests_total{project="your_project"}[5m])
```

3. **Подключение к метрикам проекта**:
   - Prometheus уже настроен и доступен в Grafana
   - Используйте метрики с лейблами `project="your_project"`

4. **Просмотр логов проекта**:
   - Используйте LogQL в Loki datasource:
   ```
   {compose_service="your_project_web"}
   ```

**Типичные дашборды**:
- Обзор системы (CPU, память, диск)
- Метрики приложения (requests, errors, latency)
- Метрики БД (connections, queries, slow queries)
- Метрики очередей (Celery tasks)

---

### Alertmanager

**Назначение**: Управление и маршрутизация алертов от Prometheus.

**Что делает**:
- Получает алерты от Prometheus
- Группирует похожие алерты
- Дедуплицирует повторяющиеся алерты
- Маршрутизирует алерты в различные каналы (Telegram, Slack, Email)
- Подавляет (silence) алерты для плановых работ

**Какие данные использует**:
- **Входящие данные**:
  - Алерты от Prometheus (порт 9093)

- **Исходящие данные**:
  - Уведомления в Telegram (через bot token)
  - Уведомления в Slack (через webhook)
  - Уведомления в Email (через SMTP)
  - Хранит состояние в volume `alertmanager-data`

**Конфигурация**:
- Файл: `alertmanager/alertmanager.yml`
- Шаблоны: `alertmanager/templates/`

**Основные настройки**:
```yaml
route:
  receiver: default
  group_by: ['alertname', 'project']  # Группировка алертов
  group_wait: 30s                     # Ждать перед отправкой группы
  group_interval: 5m                  # Интервал между группами
  repeat_interval: 2h                 # Интервал повтора для одного алерта
```

**Переменные окружения**:
- `ALERTMANAGER_EXTERNAL_URL` - внешний URL
- `ALERTMANAGER_PATH=/alertmanager` - путь в URL
- `TELEGRAM_BOT_TOKEN` - токен Telegram бота
- `TELEGRAM_CHAT_ID` - ID чата для уведомлений

**Порты**:
- `9093` - веб-интерфейс и API

**Настройка для внешних проектов**:

1. **Создание правил алертинга** (`prometheus/rules/your_project.yml`):
```yaml
groups:
  - name: your_project_alerts
    interval: 30s
    rules:
      - alert: HighErrorRate
        expr: rate(http_requests_total{project="your_project",status=~"5.."}[5m]) > 0.05
        for: 5m
        labels:
          severity: critical
          project: your_project
        annotations:
          summary: "High error rate detected"
          description: "Error rate is {{ $value }} errors/sec"
```

2. **Настройка Telegram уведомлений**:
   - Создайте бота через @BotFather
   - Получите `TELEGRAM_BOT_TOKEN`
   - Получите `TELEGRAM_CHAT_ID` через бота @userinfobot
   - Обновите `.env` файл

3. **Настройка Slack уведомлений**:
```yaml
receivers:
  - name: slack
    slack_configs:
      - api_url: 'https://hooks.slack.com/services/YOUR/WEBHOOK/URL'
        channel: '#alerts'
        send_resolved: true
```

**Типичные алерты**:
- High error rate (много ошибок 5xx)
- High latency (медленные запросы)
- Service down (сервис недоступен)
- High CPU/Memory usage
- Disk space low

---

### Loki

**Назначение**: Система агрегации логов, разработанная для работы с высокими объемами.

**Что делает**:
- Принимает логи от Promtail и других агентов
- Индексирует логи по меткам (labels)
- Хранит логи в chunks (файлы)
- Предоставляет LogQL для запросов к логам
- Автоматически удаляет старые логи (retention)

**Какие данные использует**:
- **Входящие данные**:
  - Логи от Promtail (HTTP API `/loki/api/v1/push`)
  - Логи от других агентов через Loki Push API

- **Исходящие данные**:
  - Отдает логи через Query API для Grafana
  - Хранит логи в volume `loki-data`
  - Индекс в `index_` файлах
  - Chunks в `chunks/` директории

**Конфигурация**:
- Файл: `loki/config.yml`

**Основные настройки**:
```yaml
limits_config:
  retention_period: 30d          # Хранение логов 30 дней
  ingestion_rate_mb: 16          # Лимит скорости приема
  ingestion_burst_size_mb: 32    # Максимальный burst
```

**Порты**:
- `3100` - HTTP API и веб-интерфейс

**Настройка для внешних проектов**:

1. **Автоматический сбор логов Docker**:
   - Promtail автоматически собирает логи всех контейнеров
   - Логи помечаются лейблами из Docker labels

2. **Добавление лейблов к контейнерам проекта**:
```yaml
# docker-compose.yml вашего проекта
services:
  web:
    labels:
      project: your_project
      env: prod
      service: web
```

3. **Запрос логов в Grafana**:
```
{compose_service="your_project_web"}
{project="your_project"}
```

4. **Отправка логов напрямую в Loki** (для приложений вне Docker):
```python
import requests

log_entry = {
    "streams": [{
        "stream": {"project": "your_project", "env": "prod"},
        "values": [[str(int(time.time() * 1e9)), "Log message here"]]
    }]
}

requests.post('http://loki:3100/loki/api/v1/push', json=log_entry)
```

**Типичные запросы LogQL**:
- `{project="your_project"}` - все логи проекта
- `{project="your_project"} |= "error"` - логи с ошибками
- `rate({project="your_project"}[5m])` - скорость логирования

---

### Promtail

**Назначение**: Агент для сбора логов и отправки их в Loki.

**Что делает**:
- Автоматически обнаруживает Docker контейнеры
- Читает логи контейнеров из `/var/lib/docker/containers/`
- Добавляет метки из Docker labels
- Отправляет логи в Loki через HTTP API

**Какие данные использует**:
- **Входящие данные**:
  - Логи Docker контейнеров из файловой системы
  - Метаданные контейнеров из Docker socket

- **Исходящие данные**:
  - Отправляет логи в Loki (`http://loki:3100/loki/api/v1/push`)

**Конфигурация**:
- Файл: `promtail/config.yml`

**Основные настройки**:
```yaml
clients:
  - url: http://loki:3100/loki/api/v1/push

scrape_configs:
  - job_name: docker-logs
    docker_sd_configs:
      - host: unix:///var/run/docker.sock
        refresh_interval: 30s  # Интервал обновления списка контейнеров
```

**Метки, которые добавляются автоматически**:
- `container` - имя контейнера
- `compose_service` - название сервиса в docker-compose
- `compose_project` - название проекта
- `project` - из Docker label `project`
- `env` - из Docker label `env`
- `stream` - stdout или stderr

**Настройка для внешних проектов**:

1. **Автоматический сбор**:
   - Promtail автоматически собирает логи всех контейнеров на хосте
   - Никакой дополнительной настройки не требуется

2. **Добавление меток к контейнерам**:
```yaml
# docker-compose.yml вашего проекта
services:
  web:
    labels:
      project: your_project
      env: prod
      service: web
```

3. **Фильтрация логов** (опционально, в `promtail/config.yml`):
```yaml
scrape_configs:
  - job_name: docker-logs
    relabel_configs:
      # Собирать только логи с label project=your_project
      - source_labels: ['__meta_docker_container_label_project']
        regex: 'your_project'
        action: keep
```

**Важно**:
- Promtail должен иметь доступ к `/var/lib/docker/containers/` и Docker socket
- Логи собираются в реальном времени по мере их появления

---

### Node Exporter

**Назначение**: Экспорт метрик хоста (CPU, память, диск, сеть).

**Что делает**:
- Собирает системные метрики Linux хоста
- Предоставляет метрики через HTTP эндпоинт `/metrics`
- Работает на хосте, вне контейнеров

**Какие данные использует**:
- **Входящие данные**:
  - Системные файлы: `/proc`, `/sys`
  - Информация о файловой системе

- **Исходящие данные**:
  - Метрики через порт `9100` для Prometheus

**Важные метрики**:
- `node_cpu_seconds_total` - использование CPU
- `node_memory_MemTotal_bytes` - общая память
- `node_memory_MemAvailable_bytes` - доступная память
- `node_filesystem_size_bytes` - размер файловых систем
- `node_filesystem_avail_bytes` - доступное место
- `node_network_receive_bytes_total` - входящий сетевой трафик
- `node_network_transmit_bytes_total` - исходящий сетевой трафик

**Конфигурация в Prometheus**:
```yaml
- job_name: node_exporter
  static_configs:
    - targets: ["172.17.0.1:9100"]  # IP хоста в Docker сети
```

**Настройка для внешних проектов**:

1. **Установка на хосте** (если еще не установлен):
```bash
# Скачать binary
wget https://github.com/prometheus/node_exporter/releases/download/v1.7.0/node_exporter-1.7.0.linux-amd64.tar.gz
tar xvfz node_exporter-1.7.0.linux-amd64.tar.gz
sudo mv node_exporter-1.7.0.linux-amd64/node_exporter /usr/local/bin/

# Запустить как сервис
sudo systemctl enable node_exporter
sudo systemctl start node_exporter
```

2. **Мониторинг метрик**:
   - Node Exporter уже настроен в Prometheus
   - Метрики доступны в Grafana для создания дашбордов

3. **Пример запроса в Prometheus/Grafana**:
```
100 - (avg by (instance) (irate(node_cpu_seconds_total{mode="idle"}[5m])) * 100)
```

---

### cAdvisor

**Назначение**: Сбор метрик контейнеров Docker.

**Что делает**:
- Мониторит использование ресурсов каждого контейнера
- Собирает метрики CPU, памяти, диска, сети для каждого контейнера
- Предоставляет метрики через HTTP эндпоинт `/metrics`

**Какие данные использует**:
- **Входящие данные**:
  - Информация о контейнерах через Docker API
  - Системные метрики через cgroup

- **Исходящие данные**:
  - Метрики через порт `8080` для Prometheus

**Важные метрики**:
- `container_cpu_usage_seconds_total` - использование CPU контейнером
- `container_memory_usage_bytes` - использование памяти
- `container_memory_cache` - кеш памяти
- `container_network_receive_bytes_total` - входящий трафик контейнера
- `container_network_transmit_bytes_total` - исходящий трафик контейнера

**Настройка для внешних проектов**:

1. **Автоматический мониторинг**:
   - cAdvisor автоматически отслеживает все контейнеры на хосте
   - Метрики доступны в Prometheus

2. **Фильтрация метрик по проекту**:
```
container_memory_usage_bytes{name=~".*your_project.*"}
```

3. **Создание дашборда в Grafana**:
   - Используйте метрики с фильтром по имени контейнера или лейблам

**Важно**:
- cAdvisor требует privileged доступ для чтения cgroup информации
- Метрики доступны для всех контейнеров, включая ваши проекты

---

### Postgres Exporter

**Назначение**: Экспорт метрик PostgreSQL базы данных.

**Что делает**:
- Подключается к PostgreSQL и собирает статистику
- Экспортирует метрики через HTTP эндпоинт `/metrics`
- Собирает метрики о подключениях, запросах, репликации, таблицах

**Какие данные использует**:
- **Входящие данные**:
  - Статистика из PostgreSQL через SQL запросы к системным представлениям
  - DSN подключения из переменной окружения

- **Исходящие данные**:
  - Метрики через порт `9187` для Prometheus

**Важные метрики**:
- `pg_stat_database_numbackends` - количество активных подключений
- `pg_stat_database_xact_commit` - количество коммитов
- `pg_stat_database_xact_rollback` - количество откатов
- `pg_stat_database_blks_hit` - попадания в кеш
- `pg_stat_database_blks_read` - чтения с диска
- `pg_stat_activity_count` - активные запросы

**Конфигурация**:
- Переменная окружения: `POSTGRES_EXPORTER_DSN`
- Формат: `postgresql://USER:PASSWORD@HOST:5432/DB?sslmode=disable`

**Настройка для внешних проектов**:

1. **Создание пользователя для мониторинга**:
```sql
CREATE USER postgres_exporter WITH PASSWORD 'password';
GRANT pg_monitor TO postgres_exporter;
```

2. **Обновление `.env` файла**:
```env
POSTGRES_EXPORTER_DSN=postgresql://postgres_exporter:password@your_postgres_host:5432/your_db?sslmode=disable
```

3. **Добавление в Prometheus** (если нужно несколько БД):
```yaml
- job_name: postgres_exporter_your_project
  static_configs:
    - targets: ["postgres_exporter:9187"]
      labels:
        project: your_project
```

**Важно**:
- Пользователь должен иметь права `pg_monitor` (PostgreSQL 10+)
- Для старых версий нужны права на системные таблицы

---

### Redis Exporter

**Назначение**: Экспорт метрик Redis.

**Что делает**:
- Подключается к Redis и собирает статистику
- Экспортирует метрики через HTTP эндпоинт `/metrics`
- Собирает метрики о памяти, ключах, командах, репликации

**Какие данные использует**:
- **Входящие данные**:
  - Статистика Redis через команду `INFO`
  - Команды `CONFIG`, `CLIENT LIST`

- **Исходящие данные**:
  - Метрики через порт `9121` для Prometheus

**Важные метрики**:
- `redis_memory_used_bytes` - используемая память
- `redis_memory_max_bytes` - максимальная память
- `redis_keyspace_keys` - количество ключей
- `redis_commands_total` - количество выполненных команд
- `redis_connected_clients` - подключенные клиенты
- `redis_expired_keys_total` - истекшие ключи

**Конфигурация**:
- Переменные окружения:
  - `REDIS_EXPORTER_ADDR` - адрес Redis (например: `redis://redis:6379`)
  - `REDIS_EXPORTER_PASSWORD` - пароль (если используется)

**Настройка для внешних проектов**:

1. **Обновление `.env` файла**:
```env
REDIS_EXPORTER_ADDR=redis://your_redis_host:6379
REDIS_EXPORTER_PASSWORD=your_redis_password  # если используется
```

2. **Добавление в Prometheus** (если нужно несколько Redis):
```yaml
- job_name: redis_exporter_your_project
  static_configs:
    - targets: ["redis_exporter:9121"]
      labels:
        project: your_project
```

**Важно**:
- Redis должен быть доступен из сети Docker
- Если используется пароль, необходимо указать его в переменной окружения

---

### Celery Exporter

**Назначение**: Экспорт метрик Celery (асинхронные задачи).

**Что делает**:
- Подключается к брокеру сообщений Celery (Redis/RabbitMQ)
- Собирает статистику о задачах, воркерах, очередях
- Экспортирует метрики через HTTP эндпоинт `/metrics`

**Какие данные использует**:
- **Входящие данные**:
  - Статистика из брокера сообщений (Redis)
  - Информация о задачах из результатов

- **Исходящие данные**:
  - Метрики через порт `9808` для Prometheus

**Важные метрики**:
- `celery_tasks_total` - общее количество задач
- `celery_active_tasks` - активные задачи
- `celery_workers` - количество воркеров
- `celery_task_duration_seconds` - длительность выполнения задач
- `celery_task_sent_total` - отправленные задачи

**Конфигурация**:
- Переменная окружения: `CELERY_BROKER_URL`
- Формат: `redis://redis:6379/0` или `amqp://user:pass@rabbitmq:5672//`

**Настройка для внешних проектов**:

1. **Обновление `.env` файла**:
```env
CELERY_BROKER_URL=redis://your_redis_host:6379/0
```

2. **Добавление в Prometheus**:
```yaml
- job_name: celery_exporter_your_project
  static_configs:
    - targets: ["celery_exporter:9808"]
      labels:
        project: your_project
```

3. **Интеграция с вашим проектом**:
   - Celery Exporter автоматически обнаруживает задачи из брокера
   - Никаких изменений в коде не требуется

**Важно**:
- Экспортер должен иметь доступ к тому же брокеру, что и ваши Celery воркеры
- Метрики собираются на основе информации из брокера

---

### Blackbox Exporter

**Назначение**: Мониторинг доступности внешних сервисов через HTTP, HTTPS, TCP, ICMP.

**Что делает**:
- Проверяет доступность URL и сервисов
- Измеряет время отклика
- Проверяет содержимое ответа (HTTP статус, заголовки, тело)
- Экспортирует результаты через HTTP эндпоинт `/probe`

**Какие данные использует**:
- **Входящие данные**:
  - Целевые URL и адреса из конфигурации Prometheus

- **Исходящие данные**:
  - Результаты проверок через порт `9115` для Prometheus

**Важные метрики**:
- `probe_http_status_code` - HTTP статус код
- `probe_http_duration_seconds` - время ответа
- `probe_success` - успешность проверки (1 = успешно, 0 = неудача)
- `probe_http_ssl` - использование SSL

**Конфигурация**:
- Файл: `blackbox/config.yml`
- Модули проверок:
  - `http_2xx` - проверка HTTP с ожиданием статуса 2xx
  - `tcp_connect` - проверка TCP подключения

**Настройка для внешних проектов**:

1. **Добавление проверок в Prometheus**:
```yaml
- job_name: blackbox_http
  metrics_path: /probe
  params:
    module: [http_2xx]
  static_configs:
    - targets:
        - https://your-project.com/health
        - https://api.your-project.com/status
      labels:
        project: your_project
        env: prod
  relabel_configs:
    - source_labels: [__address__]
      target_label: __param_target
    - source_labels: [__param_target]
      target_label: instance
    - target_label: __address__
      replacement: blackbox_exporter:9115
```

2. **Создание health check эндпоинта** в вашем проекте:
```python
# Django example
from django.http import JsonResponse

def health(request):
    return JsonResponse({
        'status': 'ok',
        'database': check_database(),
        'cache': check_cache()
    })
```

3. **Создание алерта на недоступность**:
```yaml
- alert: ServiceDown
  expr: probe_success{project="your_project"} == 0
  for: 5m
  labels:
    severity: critical
  annotations:
    summary: "Service {{ $labels.instance }} is down"
```

**Важно**:
- Blackbox Exporter делает проверки из сети Docker, убедитесь в доступности целей
- Для проверки внутренних сервисов используйте Docker hostname

---

### Flower

**Назначение**: Веб-интерфейс для мониторинга и управления Celery.

**Что делает**:
- Отображает статистику по задачам Celery
- Показывает активных воркеров и очереди
- Позволяет отменять и перезапускать задачи
- Показывает историю выполнения задач
- Мониторит производительность воркеров

**Какие данные использует**:
- **Входящие данные**:
  - Подключение к брокеру Celery (Redis/RabbitMQ)
  - Переменная: `CELERY_BROKER_URL`

- **Исходящие данные**:
  - Веб-интерфейс через порт `5555`

**Конфигурация**:
- Переменные окружения:
  - `CELERY_BROKER_URL` - адрес брокера
  - `FLOWER_BASIC_AUTH` - базовая аутентификация (user:password)
  - `FLOWER_URL_PREFIX` - префикс URL (для Traefik)

**Настройка для внешних проектов**:

1. **Обновление `.env` файла**:
```env
CELERY_BROKER_URL=redis://your_redis_host:6379/0
FLOWER_BASIC_AUTH=admin:password
```

2. **Доступ к интерфейсу**:
   - Через Traefik: `https://monitoring.example.com/flower`
   - Локально: `http://localhost:5555`

3. **Использование**:
   - Просмотр задач в реальном времени
   - Мониторинг производительности
   - Управление задачами (revoke, retry)

**Важно**:
- Flower должен иметь доступ к тому же брокеру, что и ваши Celery воркеры
- Рекомендуется настроить базовую аутентификацию для продакшена

---

### Portainer

**Назначение**: Веб-интерфейс для управления Docker.

**Что делает**:
- Управление контейнерами, образами, сетями, volumes
- Просмотр статистики использования ресурсов
- Управление Docker Compose стеками
- Мониторинг контейнеров

**Какие данные использует**:
- **Входящие данные**:
  - Docker API через `/var/run/docker.sock`

- **Исходящие данные**:
  - Веб-интерфейс через порт `9000`

**Настройка для внешних проектов**:

1. **Доступ к интерфейсу**:
   - Через Traefik: `https://portainer.example.com`

2. **Использование**:
   - Мониторинг контейнеров ваших проектов
   - Просмотр логов в реальном времени
   - Управление ресурсами

**Важно**:
- Portainer имеет доступ ко всем Docker ресурсам
- Используйте с осторожностью в продакшене

---

### Watchtower

**Назначение**: Автоматическое обновление Docker образов.

**Что делает**:
- Периодически проверяет обновления образов
- Автоматически перезапускает контейнеры с новыми образами
- Удаляет старые образы (опция `--cleanup`)

**Какие данные использует**:
- **Входящие данные**:
  - Docker API через `/var/run/docker.sock`
  - Docker Hub Registry для проверки обновлений

- **Исходящие данные**:
  - Обновляет контейнеры автоматически

**Конфигурация**:
- `--cleanup` - удалять старые образы
- `--interval 3600` - проверять обновления каждый час

**Настройка для внешних проектов**:

1. **Автоматическое обновление**:
   - Watchtower автоматически обновляет все контейнеры
   - Для исключения контейнера добавьте label: `com.centurylinklabs.watchtower.enable=false`

2. **Исключение контейнеров из автообновления**:
```yaml
services:
  your_service:
    labels:
      - "com.centurylinklabs.watchtower.enable=false"
```

**Важно**:
- Watchtower может прервать работу ваших сервисов при обновлении
- Используйте с осторожностью в продакшене
- Рекомендуется настроить health checks для безопасного обновления

---

## Настройка и конфигурация

### Первоначальная настройка

1. **Скопируйте файлы конфигурации**:
```bash
cp .env.example .env
```

2. **Обновите переменные окружения** в `.env`:
   - Домены (`MON_DOMAIN`, `PORTAINER_HOST`)
   - Пароли (`GRAFANA_ADMIN_PASSWORD`, `TRAEFIK_BASIC_AUTH`)
   - URLs и пути

3. **Настройте Prometheus**:
   - Отредактируйте `prometheus/prometheus.yml`
   - Добавьте целевые сервисы для сбора метрик

4. **Настройте Alertmanager**:
   - Отредактируйте `alertmanager/alertmanager.yml`
   - Укажите каналы уведомлений (Telegram, Slack)

5. **Создайте правила алертинга**:
   - Добавьте файлы `.yml` в `prometheus/rules/`

6. **Запустите стек**:
```bash
docker compose up -d
```

### Проверка работоспособности

1. **Prometheus**: `https://monitoring.example.com/prometheus`
2. **Grafana**: `https://monitoring.example.com/grafana` (admin/пароль)
3. **Alertmanager**: `https://monitoring.example.com/alertmanager`
4. **Flower**: `https://monitoring.example.com/flower`
5. **Portainer**: `https://portainer.example.com`

---

## Интеграция с внешними проектами

### Шаг 1: Добавление метрик в проект

**Для Django**:
```python
# settings.py
INSTALLED_APPS = ['django_prometheus', ...]
MIDDLEWARE = ['django_prometheus.middleware.PrometheusBeforeMiddleware', ...]

# urls.py
urlpatterns = [path('metrics', include('django_prometheus.urls')), ...]
```

**Для Flask**:
```python
from prometheus_flask_exporter import PrometheusMetrics

app = Flask(__name__)
metrics = PrometheusMetrics(app)
```

### Шаг 2: Настройка Prometheus

Добавьте в `prometheus/prometheus.yml`:
```yaml
- job_name: your_project
  metrics_path: /metrics
  static_configs:
    - targets: ["your_project_web:8000"]
      labels:
        project: your_project
        env: prod
```

### Шаг 3: Настройка сбора логов

Добавьте labels в `docker-compose.yml` вашего проекта:
```yaml
services:
  web:
    labels:
      project: your_project
      env: prod
```

### Шаг 4: Создание дашбордов в Grafana

1. Войдите в Grafana
2. Создайте новый дашборд
3. Добавьте панели с метриками вашего проекта
4. Используйте лейблы для фильтрации: `project="your_project"`

### Шаг 5: Настройка алертов

Создайте файл `prometheus/rules/your_project.yml`:
```yaml
groups:
  - name: your_project_alerts
    rules:
      - alert: HighErrorRate
        expr: rate(http_requests_total{project="your_project",status=~"5.."}[5m]) > 0.05
        for: 5m
        labels:
          severity: critical
        annotations:
          summary: "High error rate in your_project"
```

---

## Рекомендации по безопасности

1. **Всегда используйте HTTPS** через Traefik
2. **Настройте базовую аутентификацию** для Prometheus, Grafana, Alertmanager
3. **Используйте сильные пароли** в `.env`
4. **Ограничьте доступ** к веб-интерфейсам через firewall
5. **Регулярно обновляйте** образы Docker
6. **Не храните секреты** в репозитории

---

## Резервное копирование

**Важные данные для бэкапа**:
- `prometheus-data` - метрики
- `grafana-data` - дашборды и настройки
- `loki-data` - логи
- `alertmanager-data` - состояние алертов
- Конфигурационные файлы в папках `prometheus/`, `grafana/`, `alertmanager/`, `loki/`, `promtail/`

**Команда бэкапа**:
```bash
docker run --rm -v monitoring_prometheus-data:/data -v $(pwd):/backup alpine tar czf /backup/prometheus-backup.tar.gz -C /data .
```

---

## Устранение проблем

### Prometheus не собирает метрики
- Проверьте доступность целевых сервисов: `curl http://target:port/metrics`
- Проверьте конфигурацию в `prometheus/prometheus.yml`
- Проверьте логи: `docker logs prometheus`

### Grafana не показывает данные
- Проверьте подключение к Prometheus в datasources
- Проверьте правильность PromQL запросов
- Убедитесь, что метрики собираются в Prometheus

### Логи не собираются в Loki
- Проверьте доступность Loki: `curl http://loki:3100/ready`
- Проверьте логи Promtail: `docker logs promtail`
- Убедитесь, что контейнеры имеют правильные labels

### Алерты не отправляются
- Проверьте конфигурацию Alertmanager: `docker logs alertmanager`
- Проверьте правильность Telegram/Slack токенов
- Проверьте правила алертинга в Prometheus

---

## Дополнительные ресурсы

- [Prometheus Documentation](https://prometheus.io/docs/)
- [Grafana Documentation](https://grafana.com/docs/)
- [Loki Documentation](https://grafana.com/docs/loki/)
- [Alertmanager Documentation](https://prometheus.io/docs/alerting/latest/alertmanager/)
