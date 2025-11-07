# Интеграция проекта с системой мониторинга

Подробная инструкция по подключению вашего проекта к универсальному стеку мониторинга.

## Предварительные требования

1. ✅ Базовый стек мониторинга установлен (см. [installation.md](installation.md))
2. ✅ Ваше приложение экспортирует метрики Prometheus на эндпоинте `/metrics`
3. ✅ У вас есть доступ к кластеру Kubernetes

## Быстрый старт

### 1. Добавьте метрики в ваше приложение

#### Django (django-prometheus)

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

#### Flask (prometheus-flask-exporter)

```python
from prometheus_flask_exporter import PrometheusMetrics

app = Flask(__name__)
metrics = PrometheusMetrics(app)
```

#### Node.js (prom-client)

```javascript
const promClient = require('prom-client');
const register = new promClient.Registry();

app.get('/metrics', async (req, res) => {
  res.set('Content-Type', register.contentType);
  res.end(await register.metrics());
});
```

### 2. Добавьте labels к вашему Service

**КРИТИЧНО**: В манифесте вашего Service добавьте обязательные labels. Без них ServiceMonitor не сможет найти Service.

```yaml
apiVersion: v1
kind: Service
metadata:
  name: myapp-web
  namespace: myproject
  labels:
    app: myapp-web-http        # Должен совпадать с selector в ServiceMonitor
    monitoring: enabled         # ОБЯЗАТЕЛЬНО! Без этого label ServiceMonitor не найдет Service
    project: myproject          # Для группировки в Grafana (опционально)
spec:
  ports:
  - name: http
    port: 80
    targetPort: 8000
  selector:
    app: myapp
```

**Важно**:
- Label `monitoring: enabled` - **ОБЯЗАТЕЛЬНЫЙ** для работы ServiceMonitor
- Label `app` должен **точно совпадать** с `selector.matchLabels.app` в ServiceMonitor
- Label `project` используется для группировки метрик в Grafana (рекомендуется)

### 3. Создайте ServiceMonitor

**КРИТИЧНО**: ServiceMonitor должен требовать label `monitoring: enabled` в selector для соблюдения принципа явной фильтрации.

Скопируйте шаблон из `templates/servicemonitor-template.yaml`:

```bash
cp templates/servicemonitor-template.yaml myproject-servicemonitor.yaml
```

Отредактируйте файл, заменив:
- `PROJECT_NAME` → `myproject`
- `YOUR_PROJECT_NAMESPACE` → `myproject`

Пример готового ServiceMonitor:

```yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: myproject-web-http
  namespace: myproject
  labels:
    app: myproject
    monitoring: enabled         # ОБЯЗАТЕЛЬНО! Для фильтрации ServiceMonitor
    project: myproject          # Для группировки в Grafana
spec:
  selector:
    matchLabels:
      app: myproject-web-http  # Должен совпадать с Service label
      monitoring: enabled       # ОБЯЗАТЕЛЬНО! Без этого ServiceMonitor не найдет Service
  namespaceSelector:
    matchNames:
      - myproject               # Явно указываем namespace (рекомендуется)
  endpoints:
  - port: http
    path: /metrics
    interval: 30s
    scrapeTimeout: 10s
```

**Важно**:
- `selector.matchLabels.monitoring: enabled` - **ОБЯЗАТЕЛЬНО** для явной фильтрации
- `metadata.labels.monitoring: enabled` - рекомендуется для фильтрации ServiceMonitor
- `namespaceSelector.matchNames` - явно указывает namespace (рекомендуется вместо `any: true`)

### 4. Примените манифест

```bash
kubectl apply -f myproject-servicemonitor.yaml
```

### 5. Проверка

```bash
# Проверьте что ServiceMonitor создан
kubectl get servicemonitor -n myproject

# Проверьте что Prometheus видит targets
kubectl port-forward -n monitoring svc/prometheus-kube-prometheus-prometheus 9090:9090
# Откройте http://localhost:9090/targets
# Должен появиться ваш сервис в списке со статусом "UP"
```

## Несколько проектов

Система автоматически собирает метрики из всех namespace, где есть ServiceMonitor с label `monitoring: enabled`.

**Просто создайте ServiceMonitor в каждом проекте по шаблону выше.**

Prometheus автоматически обнаружит все ServiceMonitor во всех namespace.

## Фильтрация в Grafana

### По namespace

```promql
# Метрики конкретного проекта
rate(http_requests_total{namespace="myproject"}[5m])

# Метрики всех проектов
rate(http_requests_total[5m])
```

### По project label

```promql
# Метрики конкретного проекта
rate(http_requests_total{project="myproject"}[5m])

# Группировка по проектам
sum by (project) (rate(http_requests_total[5m]))
```

## Логи

Логи собираются автоматически из всех подов во всех namespace.

### Фильтрация в Loki

```logql
# Логи конкретного проекта
{namespace="myproject"}

# Логи с ошибками
{namespace="myproject"} |= "error"

# Логи конкретного контейнера
{namespace="myproject", container="web"}
```

### Добавление labels к подам

Для лучшей фильтрации добавьте labels к вашим Pods:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: myapp
  namespace: myproject
spec:
  template:
    metadata:
      labels:
        app: myapp
        project: myproject
        monitoring: enabled
    spec:
      containers:
      - name: web
        image: myapp:latest
```

## Создание дашбордов

### Через Grafana UI

1. Войдите в Grafana
2. Создайте новый дашборд
3. Добавьте панели с метриками вашего проекта
4. Используйте фильтры по `namespace` или `project`

### Через ConfigMap

См. шаблон `templates/grafana-dashboard-template.yaml`

## Примеры для разных типов приложений

### Django приложение

См. `examples/project-integration/servicemonitor-example.yaml`

### Flask приложение

Аналогично Django, используйте `prometheus-flask-exporter`.

### Node.js приложение

Используйте `prom-client` для экспорта метрик.

### Go приложение

Используйте `prometheus/client_golang`.

## Troubleshooting

### Prometheus не видит targets

1. Проверьте что ServiceMonitor создан:
   ```bash
   kubectl get servicemonitor -n myproject
   ```

2. Проверьте labels в Service:
   ```bash
   kubectl get svc -n myproject --show-labels
   ```

3. Проверьте что метрики доступны:
   ```bash
   kubectl port-forward -n myproject svc/myapp-web 8000:80
   curl http://localhost:8000/metrics
   ```

### Метрики не появляются в Grafana

1. Проверьте подключение к Prometheus в Grafana:
   - Configuration → Data Sources → Prometheus
   - URL: `http://prometheus-kube-prometheus-prometheus:9090`

2. Проверьте PromQL запросы в Grafana

### Логи не появляются в Loki

1. Проверьте что Promtail работает:
   ```bash
   kubectl get pods -n monitoring | grep promtail
   ```

2. Проверьте labels подов:
   ```bash
   kubectl get pods -n myproject --show-labels
   ```

## Дополнительные ресурсы

- [Шаблоны](../templates/) - Готовые шаблоны для интеграции
- [Примеры](../examples/) - Примеры интеграции
- [Troubleshooting](troubleshooting.md) - Решение проблем
