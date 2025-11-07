# Универсальный стек мониторинга для Kubernetes

Универсальный репозиторий системы мониторинга, который работает с любым проектом и поддерживает несколько проектов на одном сервере одновременно.

## Возможности

- ✅ **Мультипроектность** - один стек мониторинга для всех проектов
- ✅ **Автоматический сбор метрик** - Prometheus собирает метрики из всех namespace
- ✅ **Автоматический сбор логов** - Promtail собирает логи из всех подов
- ✅ **Простая интеграция** - подключение проекта через ServiceMonitor
- ✅ **Единый стек** - Prometheus, Grafana, Loki, Promtail, Portainer

## Быстрый старт

### 1. Установка базового стека

**Базовая установка (без Ingress):**
```bash
export DOMAIN=example.com
export GRAFANA_PASSWORD=secure_password
./scripts/setup.sh
```

**Установка с Ingress (рекомендуется для продакшена):**
```bash
export DOMAIN=example.com
export GRAFANA_PASSWORD=secure_password
export ENABLE_INGRESS=true
export INGRESS_CLASS=nginx
./scripts/setup.sh
```

### 2. Интеграция проекта

1. Добавьте labels к вашему Service:
```yaml
metadata:
  labels:
    app: myapp-web-http
    monitoring: enabled
```

2. Создайте ServiceMonitor (см. `templates/servicemonitor-template.yaml`)

3. Примените манифест:
```bash
kubectl apply -f servicemonitor.yaml
```

## Структура репозитория

```
monitoring/
├── README.md                    # Эта документация
├── scripts/                     # Скрипты
│   ├── setup.sh                # Скрипт установки базового стека
│   └── check-status.sh         # Проверка статуса
├── values/                      # Helm values файлы
│   ├── prometheus-values.yaml
│   ├── loki-values.yaml
│   └── portainer-values.yaml
├── base/                        # Базовые Kubernetes манифесты
│   ├── namespace.yaml
│   └── kustomization.yaml
├── templates/                   # Шаблоны для интеграции проектов
│   ├── servicemonitor-template.yaml
│   ├── podmonitor-template.yaml
│   └── grafana-dashboard-template.yaml
├── examples/                    # Примеры интеграции
│   └── project-integration/
├── scripts/                     # Вспомогательные скрипты
│   ├── check-status.sh
│   └── open-monitoring.sh
└── docs/                        # Документация
    ├── installation.md
    ├── project-integration.md
    ├── troubleshooting.md
    └── architecture.md
```

## Документация

- [Установка](docs/installation.md) - Детальная инструкция по установке
- [Настройка Ingress](docs/ingress-setup.md) - Настройка доступа через доменные имена
- [Интеграция проектов](docs/project-integration.md) - Как подключить проект к мониторингу
- [Критические настройки](docs/CRITICAL_SETTINGS.md) - ⚠️ ОБЯЗАТЕЛЬНЫЕ настройки для мультипроектности
- [Архитектура](docs/architecture.md) - Архитектура системы
- [Решение проблем](docs/troubleshooting.md) - Типичные проблемы и решения
- [Инструкция для AI агента](AGENT_INTEGRATION_GUIDE.md) - Руководство для AI агента по подключению проектов

## Архитектура

```
┌─────────────────────────────────────────────────────────┐
│  Namespace: monitoring                                    │
│  ┌────────────┐  ┌────────────┐  ┌────────────┐        │
│  │ Prometheus │  │  Grafana   │  │    Loki    │        │
│  └─────┬──────┘  └────────────┘  └──────┬─────┘        │
│        │                                 │              │
│        │ Собирает метрики                │ Собирает логи│
│        │ из всех namespace                │ из всех подов│
└────────┼─────────────────────────────────┼──────────────┘
         │                                 │
         │                                 │
┌────────┴─────────┐            ┌─────────┴──────────┐
│ Namespace: project1           │ Namespace: project2│
│ ┌──────────────────┐          │ ┌──────────────────┐│
│ │ ServiceMonitor   │          │ │ ServiceMonitor   ││
│ │ (project1-web)   │          │ │ (project2-web)  ││
│ └──────────────────┘          │ └──────────────────┘│
│ ┌──────────────────┐          │ ┌──────────────────┐│
│ │ Service          │          │ │ Service          ││
│ │ (app: project1)  │          │ │ (app: project2)  ││
│ └──────────────────┘          │ └──────────────────┘│
└──────────────────────────────┘ └────────────────────┘
```

## Требования

- Kubernetes кластер (версия 1.19+)
- kubectl настроен и подключен к кластеру
- Helm 3.x установлен
- Доступ к интернету для загрузки Helm charts

**Для Ingress (опционально)**:
- cert-manager установлен (см. [Настройка Ingress](docs/ingress-setup.md#предварительные-требования))
- Ingress Controller установлен (NGINX, Traefik и т.д.)
- ClusterIssuer настроен для Let's Encrypt

## Параметры установки

Скрипт `scripts/setup.sh` поддерживает следующие переменные окружения:

- `DOMAIN` - базовый домен (обязательно)
- `MONITORING_NAMESPACE` - namespace для мониторинга (по умолчанию: monitoring)
- `GRAFANA_PASSWORD` - пароль Grafana (по умолчанию: admin)
- `ACME_EMAIL` - email для Let's Encrypt (по умолчанию: admin@${DOMAIN})
- `PROMETHEUS_RETENTION` - время хранения метрик (по умолчанию: 15d)
- `PROMETHEUS_STORAGE` - размер хранилища Prometheus (по умолчанию: 20Gi)
- `LOKI_RETENTION` - время хранения логов (по умолчанию: 744h = 31 день)
- `LOKI_STORAGE` - размер хранилища Loki (по умолчанию: 20Gi)
- `INSTALL_PORTAINER` - установить Portainer (по умолчанию: false)
- `ENABLE_INGRESS` - включить Ingress для сервисов (по умолчанию: false)
- `INGRESS_CLASS` - класс Ingress Controller (по умолчанию: nginx)
- `MONITORING_DOMAIN` - домен для мониторинга (по умолчанию: monitoring.${DOMAIN})

## Проверка статуса

```bash
./scripts/check-status.sh
```

## Открытие мониторинга в браузере

```bash
export DOMAIN=example.com
./scripts/open-monitoring.sh open
```

## Лицензия

MIT
