# Инструкция для AI агента: Подключение проекта к системе мониторинга

## Цель

Эта инструкция предназначена для AI агента, который помогает пользователям интегрировать их проекты с универсальной системой мониторинга Kubernetes.

## Когда применять эту инструкцию

Применяйте эту инструкцию, когда пользователь:
- Хочет подключить свой проект к системе мониторинга
- Просит добавить мониторинг в проект
- Нужна помощь с настройкой метрик Prometheus
- Хочет видеть логи своего проекта в Grafana

## Предварительные условия

Перед началом интеграции убедитесь, что:
1. ✅ Базовый стек мониторинга установлен (namespace `monitoring` существует)
2. ✅ Проект развернут в Kubernetes
3. ✅ У проекта есть Service в Kubernetes
4. ✅ Приложение может экспортировать метрики Prometheus (или готово к добавлению)

## Шаги интеграции

### Шаг 1: Добавление метрик в приложение

**Цель**: Приложение должно экспортировать метрики Prometheus на эндпоинте `/metrics`

#### Для Django приложений

```python
# 1. Установите пакет
# pip install django-prometheus

# 2. Добавьте в settings.py
INSTALLED_APPS = [
    ...
    'django_prometheus',  # Добавьте это
]

MIDDLEWARE = [
    'django_prometheus.middleware.PrometheusBeforeMiddleware',  # В начало
    ...
    'django_prometheus.middleware.PrometheusAfterMiddleware',  # В конец
]

# 3. Добавьте в urls.py
urlpatterns = [
    path('metrics', include('django_prometheus.urls')),  # Добавьте это
    ...
]
```

#### Для Flask приложений

```python
# 1. Установите пакет
# pip install prometheus-flask-exporter

# 2. Добавьте в код
from prometheus_flask_exporter import PrometheusMetrics

app = Flask(__name__)
metrics = PrometheusMetrics(app)  # Добавьте это

# Метрики автоматически доступны на /metrics
```

#### Для Node.js приложений

```javascript
// 1. Установите пакет
// npm install prom-client

// 2. Добавьте в код
const promClient = require('prom-client');
const register = new promClient.Registry();

// 3. Добавьте эндпоинт
app.get('/metrics', async (req, res) => {
  res.set('Content-Type', register.contentType);
  res.end(await register.metrics());
});
```

#### Для Go приложений

```go
// 1. Установите пакет
// go get github.com/prometheus/client_golang/prometheus/promhttp

// 2. Добавьте в код
import (
    "github.com/prometheus/client_golang/prometheus/promhttp"
    "net/http"
)

// 3. Добавьте эндпоинт
http.Handle("/metrics", promhttp.Handler())
```

**Проверка**: После деплоя проверьте доступность метрик:
```bash
kubectl port-forward -n <namespace> svc/<service-name> 8000:80
curl http://localhost:8000/metrics
```

### Шаг 2: Обновление Service с labels

**Цель**: Добавить обязательные labels к Service для обнаружения Prometheus

**Действия**:
1. Найдите манифест Service проекта
2. Добавьте labels в `metadata.labels`:
   - `monitoring: enabled` - **ОБЯЗАТЕЛЬНО!**
   - `app: <service-name>-http` - должен совпадать с selector в ServiceMonitor
   - `project: <project-name>` - для группировки (опционально)

**Пример**:

```yaml
apiVersion: v1
kind: Service
metadata:
  name: myapp-web
  namespace: myproject
  labels:
    app: myapp-web-http        # Должен ТОЧНО совпадать с selector в ServiceMonitor
    monitoring: enabled         # ОБЯЗАТЕЛЬНО! Без этого ServiceMonitor не найдет Service
    project: myproject          # Для группировки в Grafana (рекомендуется)
spec:
  ports:
  - name: http
    port: 80
    targetPort: 8000
  selector:
    app: myapp
```

**КРИТИЧНО**:
- Label `monitoring: enabled` - **ОБЯЗАТЕЛЬНЫЙ** для обнаружения Prometheus
- Label `app` должен **ТОЧНО совпадать** с `selector.matchLabels.app` в ServiceMonitor
- Без этих labels ServiceMonitor не сможет найти Service и метрики не будут собираться

### Шаг 3: Создание ServiceMonitor

**Цель**: Создать ServiceMonitor для автоматического обнаружения метрик Prometheus

**Действия**:
1. Скопируйте шаблон из `templates/servicemonitor-template.yaml`
2. Замените плейсхолдеры:
   - `PROJECT_NAME` → имя проекта (например, `myproject`)
   - `YOUR_PROJECT_NAMESPACE` → namespace проекта (например, `myproject`)
3. Настройте `selector.matchLabels` под labels вашего Service
4. Настройте `endpoints` под ваши порты и пути

**Пример готового ServiceMonitor**:

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
      app: myproject-web-http   # Должен ТОЧНО совпадать с Service label
      monitoring: enabled       # ОБЯЗАТЕЛЬНО! Без этого ServiceMonitor не найдет Service
  namespaceSelector:
    matchNames:
      - myproject               # Явно указываем namespace (рекомендуется)
  endpoints:
  - port: http                  # Имя порта из Service
    path: /metrics              # Путь к метрикам
    interval: 30s               # Интервал сбора
    scrapeTimeout: 10s          # Таймаут
```

**КРИТИЧНО**:
- `selector.matchLabels.monitoring: enabled` - **ОБЯЗАТЕЛЬНО** для явной фильтрации
- `metadata.labels.monitoring: enabled` - рекомендуется для фильтрации ServiceMonitor
- `namespaceSelector.matchNames` - явно указывает namespace (рекомендуется вместо `any: true`)

**Применение**:
```bash
kubectl apply -f servicemonitor.yaml
```

### Шаг 4: Проверка подключения

**Цель**: Убедиться, что Prometheus видит и собирает метрики

**Действия**:

1. **Проверьте ServiceMonitor**:
   ```bash
   kubectl get servicemonitor -n <namespace>
   kubectl describe servicemonitor -n <namespace> <name>
   ```

2. **Проверьте в Prometheus UI**:
   ```bash
   kubectl port-forward -n monitoring svc/prometheus-kube-prometheus-prometheus 9090:9090
   # Откройте http://localhost:9090/targets
   ```
   Ваш сервис должен появиться в списке со статусом `UP`

3. **Проверьте метрики**:
   В Prometheus UI выполните запрос:
   ```promql
   up{job="<service-name>"}
   ```
   Должен вернуться результат `1` (сервис доступен)

### Шаг 5: Настройка логов (опционально)

**Цель**: Логи автоматически собираются, но для лучшей фильтрации добавьте labels к подам

**Действия**:
1. Найдите Deployment/StatefulSet проекта
2. Добавьте labels в `spec.template.metadata.labels`:
   - `project: <project-name>` - для фильтрации в Loki
   - `monitoring: enabled` - опционально

**Пример**:

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
        project: myproject        # Для фильтрации в Loki
        monitoring: enabled       # Опционально
    spec:
      containers:
      - name: web
        image: myapp:latest
```

**Фильтрация в Loki**:
```logql
{namespace="myproject"}
{namespace="myproject"} |= "error"
```

## Типичные сценарии

### Сценарий 1: Новый проект

**Задача**: Подключить новый проект к мониторингу

**Шаги**:
1. Добавьте метрики в приложение (Шаг 1)
2. Обновите Service с labels (Шаг 2)
3. Создайте ServiceMonitor (Шаг 3)
4. Проверьте подключение (Шаг 4)

### Сценарий 2: Проект уже имеет метрики

**Задача**: Проект уже экспортирует метрики, нужно только подключить к Prometheus

**Шаги**:
1. Обновите Service с labels (Шаг 2)
2. Создайте ServiceMonitor (Шаг 3)
3. Проверьте подключение (Шаг 4)

### Сценарий 3: Несколько сервисов в одном проекте

**Задача**: В проекте несколько сервисов (web, api, worker), нужно мониторить все

**Решение**: Создайте отдельный ServiceMonitor для каждого сервиса:

```yaml
# ServiceMonitor для web
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: myproject-web-http
  namespace: myproject
spec:
  selector:
    matchLabels:
      app: myproject-web-http
      monitoring: enabled
  endpoints:
  - port: http
    path: /metrics

---
# ServiceMonitor для api
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: myproject-api-http
  namespace: myproject
spec:
  selector:
    matchLabels:
      app: myproject-api-http
      monitoring: enabled
  endpoints:
  - port: http
    path: /metrics
```

## Troubleshooting

### Проблема: Prometheus не видит targets

**Причины и решения**:

1. **ServiceMonitor не создан**:
   ```bash
   kubectl get servicemonitor -n <namespace>
   ```
   Если нет - создайте ServiceMonitor

2. **Labels не совпадают**:
   ```bash
   kubectl get svc -n <namespace> --show-labels
   ```
   Проверьте, что labels в Service совпадают с `selector.matchLabels` в ServiceMonitor

3. **Метрики недоступны**:
   ```bash
   kubectl port-forward -n <namespace> svc/<service-name> 8000:80
   curl http://localhost:8000/metrics
   ```
   Если не работает - проверьте, что метрики добавлены в приложение

4. **Prometheus не настроен на сбор из всех namespace**:
   **КРИТИЧНО**: Проверьте values файл Prometheus (`values/prometheus-values.yaml`):
   ```yaml
   prometheus:
     prometheusSpec:
       serviceMonitorSelectorNilUsesHelmValues: false
       serviceMonitorNamespaceSelector: {}  # КРИТИЧНО! Должно быть {}
   ```
   Если `serviceMonitorNamespaceSelector` отсутствует или имеет другое значение, Prometheus не будет собирать метрики из всех namespace.

### Проблема: Метрики не появляются в Grafana

**Причины и решения**:

1. **Datasource не настроен**:
   - Войдите в Grafana → Configuration → Data Sources
   - Проверьте, что Prometheus настроен: `http://prometheus-kube-prometheus-prometheus:9090`

2. **Неправильный PromQL запрос**:
   - Используйте фильтры: `{namespace="<namespace>"}` или `{project="<project>"}`

3. **Метрики не собираются**:
   - Проверьте targets в Prometheus UI

## Чеклист для AI агента

При помощи пользователю с интеграцией, проверьте:

- [ ] Метрики добавлены в приложение и доступны на `/metrics`
- [ ] Service имеет label `monitoring: enabled`
- [ ] Service имеет label `app`, который совпадает с selector в ServiceMonitor
- [ ] ServiceMonitor создан и применен
- [ ] ServiceMonitor имеет правильный `namespaceSelector`
- [ ] ServiceMonitor имеет правильный `selector.matchLabels`
- [ ] ServiceMonitor имеет правильный `endpoints` (port, path)
- [ ] Prometheus видит target (проверка в `/targets`)
- [ ] Метрики доступны в Prometheus (проверка запросом)
- [ ] Логи собираются (опционально, проверка в Loki)

## Полезные команды для пользователя

```bash
# Проверка ServiceMonitor
kubectl get servicemonitor -n <namespace>
kubectl describe servicemonitor -n <namespace> <name>

# Проверка Service labels
kubectl get svc -n <namespace> --show-labels

# Проверка метрик
kubectl port-forward -n <namespace> svc/<service-name> 8000:80
curl http://localhost:8000/metrics

# Проверка в Prometheus
kubectl port-forward -n monitoring svc/prometheus-kube-prometheus-prometheus 9090:9090
# Откройте http://localhost:9090/targets

# Проверка статуса стека
./scripts/check-status.sh
```

## Примеры для разных типов приложений

### Django

См. примеры в `examples/project-integration/`

### Flask

Аналогично Django, используйте `prometheus-flask-exporter`

### Node.js

Используйте `prom-client` для экспорта метрик

### Go

Используйте `prometheus/client_golang`

### Java/Spring Boot

Используйте `micrometer-registry-prometheus`

## Дополнительные ресурсы

- [Шаблоны](../templates/) - Готовые шаблоны для интеграции
- [Примеры](../examples/) - Примеры интеграции
- [Документация](../docs/) - Подробная документация
- [Troubleshooting](../docs/troubleshooting.md) - Решение проблем

## Важные напоминания

1. **Всегда проверяйте labels** - они критичны для работы ServiceMonitor
2. **Проверяйте доступность метрик** - перед созданием ServiceMonitor убедитесь, что `/metrics` работает
3. **Используйте шаблоны** - не создавайте ServiceMonitor с нуля, используйте шаблоны
4. **Проверяйте namespace** - ServiceMonitor должен быть в правильном namespace
5. **Тестируйте подключение** - всегда проверяйте, что Prometheus видит targets

---

**Готово!** Следуя этой инструкции, AI агент сможет помочь пользователям интегрировать их проекты с системой мониторинга.
