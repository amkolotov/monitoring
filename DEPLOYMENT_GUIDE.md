# Подробная инструкция по развертыванию и подключению проектов

Полное руководство по установке универсального стека мониторинга и подключению ваших проектов.

## Часть 1: Развертывание базового стека мониторинга

> **Развертывание на чистом Ubuntu сервере?**
> См. [Полная инструкция по развертыванию на Ubuntu](docs/ubuntu-deployment.md)

### Шаг 1: Подготовка окружения

#### 1.1. Проверка требований

```bash
# Проверка Kubernetes
kubectl version --client
kubectl cluster-info
kubectl get nodes

# Проверка Helm
helm version

# Проверка StorageClass (для PersistentVolumes)
kubectl get storageclass

# Проверка cert-manager (если планируете использовать Ingress)
kubectl get pods -n cert-manager
kubectl get clusterissuer

# Проверка Ingress Controller (если планируете использовать Ingress)
kubectl get ingressclass
kubectl get pods -n ingress-nginx  # Для nginx
```

**Если cert-manager не установлен**, см. [Установка cert-manager](docs/ingress-setup.md#установка-cert-manager)

#### 1.2. Клонирование репозитория

```bash
git clone <repository-url>
cd monitoring
```

### Шаг 2: Настройка параметров

Создайте файл с переменными окружения или экспортируйте их:

```bash
# Обязательные параметры
export DOMAIN=example.com                    # Ваш домен
export GRAFANA_PASSWORD=secure_password     # Сильный пароль!

# Опциональные параметры
export MONITORING_NAMESPACE=monitoring       # По умолчанию: monitoring
export PROMETHEUS_RETENTION=15d             # Время хранения метрик
export PROMETHEUS_STORAGE=20Gi               # Размер хранилища
export LOKI_RETENTION=744h                  # Время хранения логов (31 день)
export LOKI_STORAGE=20Gi                    # Размер хранилища
export INSTALL_PORTAINER=false             # Установить Portainer
export ENABLE_INGRESS=true                  # Включить Ingress (рекомендуется)
export INGRESS_CLASS=nginx                  # Класс Ingress Controller
export ACME_EMAIL=admin@example.com         # Email для Let's Encrypt (опционально)
```
<｜tool▁calls▁begin｜><｜tool▁call▁begin｜>
read_file

**Важно**:
- `DOMAIN` - обязательный параметр
- `GRAFANA_PASSWORD` - измените пароль по умолчанию!

### Шаг 3: Установка стека

```bash
./scripts/setup.sh
```

Скрипт выполнит:
1. ✅ Проверку зависимостей (kubectl, helm)
2. ✅ Создание namespace `monitoring`
3. ✅ Добавление Helm репозиториев
4. ✅ Установку Prometheus (kube-prometheus-stack)
5. ✅ Установку Loki + Promtail
6. ✅ Установку Portainer (если `INSTALL_PORTAINER=true`)

**Время установки**: 5-10 минут

### Шаг 4: Проверка установки

```bash
# Проверка статуса
./scripts/check-status.sh

# Или вручную
kubectl get pods -n monitoring
kubectl get servicemonitor --all-namespaces
```

Все поды должны быть в статусе `Running`.

### Шаг 5: Настройка доступа

#### Вариант A: Ingress (рекомендуется для продакшена)

**Автоматическое создание Ingress** (если `ENABLE_INGRESS=true`):

Ingress создаются автоматически при установке. После установки:

1. **Проверьте Ingress**:
   ```bash
   kubectl get ingress -n monitoring
   ```

2. **Настройте DNS записи**:
   ```
   *.example.com  A  <IP_INGRESS_CONTROLLER>
   ```
   Или отдельные записи:
   ```
   grafana.example.com    A  <IP_INGRESS_CONTROLLER>
   prometheus.example.com A  <IP_INGRESS_CONTROLLER>
   portainer.example.com  A  <IP_INGRESS_CONTROLLER>
   ```

3. **Проверьте доступность**:
   ```bash
   curl -I https://grafana.example.com
   ```

**Подробная инструкция**: См. [Настройка Ingress](docs/ingress-setup.md)

#### Вариант B: Port Forward (для тестирования)

```bash
# Grafana
kubectl port-forward -n monitoring svc/kube-prometheus-stack-grafana 3000:80

# Prometheus
kubectl port-forward -n monitoring svc/prometheus-kube-prometheus-prometheus 9090:9090

# Loki
kubectl port-forward -n monitoring svc/loki 3100:3100
```

### Шаг 6: Первый вход в Grafana

1. Откройте Grafana в браузере:
   - Через Ingress (если `ENABLE_INGRESS=true`): `https://grafana.${DOMAIN}`
   - Через port-forward: `http://localhost:3000`

2. Войдите с учетными данными:
   - Username: `admin`
   - Password: значение `GRAFANA_PASSWORD` (или `admin` по умолчанию)

3. **ВАЖНО**: Измените пароль при первом входе!

4. Проверьте datasources:
   - Configuration → Data Sources
   - Должны быть настроены:
     - Prometheus: `http://prometheus-kube-prometheus-prometheus:9090`
     - Loki: `http://loki:3100`

## Часть 2: Подключение проекта к мониторингу

### Шаг 1: Подготовка приложения

#### 1.1. Добавление метрик в приложение

**Django (django-prometheus)**:

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

**Flask (prometheus-flask-exporter)**:

```python
from prometheus_flask_exporter import PrometheusMetrics

app = Flask(__name__)
metrics = PrometheusMetrics(app)
```

**Node.js (prom-client)**:

```javascript
const promClient = require('prom-client');
const register = new promClient.Registry();

app.get('/metrics', async (req, res) => {
  res.set('Content-Type', register.contentType);
  res.end(await register.metrics());
});
```

#### 1.2. Проверка метрик

```bash
# После деплоя приложения
kubectl port-forward -n <namespace> svc/<service-name> 8000:80
curl http://localhost:8000/metrics
```

Должны появиться метрики в формате Prometheus.

### Шаг 2: Настройка Service

Добавьте обязательные labels к вашему Service:

```yaml
apiVersion: v1
kind: Service
metadata:
  name: myapp-web
  namespace: myproject
  labels:
    app: myapp-web-http        # Должен совпадать с selector в ServiceMonitor
    monitoring: enabled         # ОБЯЗАТЕЛЬНО!
    project: myproject          # Для группировки (опционально)
spec:
  ports:
  - name: http
    port: 80
    targetPort: 8000
  selector:
    app: myapp
```

**Важно**:
- Label `monitoring: enabled` обязателен!
- Label `app` должен совпадать с `selector.matchLabels` в ServiceMonitor

### Шаг 3: Создание ServiceMonitor

#### 3.1. Копирование шаблона

```bash
cp templates/servicemonitor-template.yaml myproject-servicemonitor.yaml
```

#### 3.2. Редактирование шаблона

Откройте файл и замените:
- `PROJECT_NAME` → `myproject`
- `YOUR_PROJECT_NAMESPACE` → `myproject`

Пример готового файла:

```yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: myproject-web-http
  namespace: myproject
  labels:
    app: myproject
    monitoring: enabled
    project: myproject
spec:
  selector:
    matchLabels:
      app: myproject-web-http
      monitoring: enabled
  namespaceSelector:
    matchNames:
      - myproject
  endpoints:
  - port: http
    path: /metrics
    interval: 30s
    scrapeTimeout: 10s
```

#### 3.3. Применение манифеста

```bash
kubectl apply -f myproject-servicemonitor.yaml
```

### Шаг 4: Проверка подключения

#### 4.1. Проверка ServiceMonitor

```bash
kubectl get servicemonitor -n myproject
kubectl describe servicemonitor -n myproject myproject-web-http
```

#### 4.2. Проверка в Prometheus

```bash
# Port-forward к Prometheus
kubectl port-forward -n monitoring svc/prometheus-kube-prometheus-prometheus 9090:9090

# Откройте в браузере
# http://localhost:9090/targets
```

Ваш сервис должен появиться в списке targets со статусом `UP`.

#### 4.3. Проверка метрик

В Prometheus UI выполните запрос:

```promql
up{job="myproject-web-http"}
```

Должен вернуться результат `1` (сервис доступен).

### Шаг 5: Настройка логов (опционально)

Логи собираются автоматически, но для лучшей фильтрации добавьте labels к подам:

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

### Шаг 6: Создание дашбордов в Grafana

#### 6.1. Через UI

1. Войдите в Grafana
2. Создайте новый дашборд: Dashboards → New Dashboard
3. Добавьте панели с метриками вашего проекта
4. Используйте фильтры:
   - `namespace="myproject"` или
   - `project="myproject"`

#### 6.2. Через ConfigMap

См. шаблон `templates/grafana-dashboard-template.yaml`

## Часть 3: Работа с несколькими проектами

### Добавление второго проекта

Просто повторите шаги из Части 2 для каждого нового проекта:

1. Добавьте метрики в приложение
2. Настройте Service с labels
3. Создайте ServiceMonitor
4. Примените манифест

**Prometheus автоматически обнаружит все ServiceMonitor!**

### Фильтрация в Grafana

#### По namespace

```promql
# Метрики конкретного проекта
rate(http_requests_total{namespace="myproject"}[5m])

# Метрики всех проектов
rate(http_requests_total[5m])

# Группировка по проектам
sum by (project) (rate(http_requests_total[5m]))
```

#### По project label

```promql
# Метрики конкретного проекта
rate(http_requests_total{project="myproject"}[5m])
```

### Фильтрация логов в Loki

```logql
# Логи конкретного проекта
{namespace="myproject"}

# Логи с ошибками
{namespace="myproject"} |= "error"

# Логи конкретного контейнера
{namespace="myproject", container="web"}
```

## Часть 4: Типичные сценарии

### Сценарий 1: Новый проект

1. Деплой приложения в Kubernetes
2. Добавление метрик в приложение
3. Настройка Service с labels
4. Создание ServiceMonitor
5. Проверка в Prometheus

### Сценарий 2: Миграция существующего проекта

1. Добавление метрик в приложение
2. Обновление Service с labels
3. Создание ServiceMonitor
4. Проверка работы

### Сценарий 3: Отключение проекта

```bash
# Удаление ServiceMonitor
kubectl delete servicemonitor -n myproject myproject-web-http

# Метрики перестанут собираться автоматически
```

## Часть 5: Troubleshooting

### Проблема: Prometheus не видит targets

**Решение**:
1. Проверьте ServiceMonitor: `kubectl get servicemonitor -n myproject`
2. Проверьте labels в Service: `kubectl get svc -n myproject --show-labels`
3. Проверьте доступность метрик: `curl http://<service>/metrics`

### Проблема: Метрики не появляются в Grafana

**Решение**:
1. Проверьте datasource Prometheus в Grafana
2. Проверьте PromQL запросы
3. Убедитесь, что метрики собираются в Prometheus

### Проблема: Логи не появляются в Loki

**Решение**:
1. Проверьте статус Promtail: `kubectl get pods -n monitoring | grep promtail`
2. Проверьте labels подов: `kubectl get pods -n myproject --show-labels`

Подробнее см. [docs/troubleshooting.md](docs/troubleshooting.md)

## Полезные команды

```bash
# Проверка статуса
./scripts/check-status.sh

# Открытие мониторинга в браузере
export DOMAIN=example.com
./scripts/open-monitoring.sh open

# Просмотр метрик в Prometheus
kubectl port-forward -n monitoring svc/prometheus-kube-prometheus-prometheus 9090:9090

# Просмотр логов Promtail
kubectl logs -n monitoring -l app=promtail -f
```

## Дополнительные ресурсы

- [Установка](docs/installation.md) - Детальная инструкция по установке
- [Интеграция проектов](docs/project-integration.md) - Подробности интеграции
- [Архитектура](docs/architecture.md) - Архитектура системы
- [Решение проблем](docs/troubleshooting.md) - Troubleshooting
- [Примеры](examples/) - Примеры интеграции

## Чеклист развертывания

- [ ] Kubernetes кластер настроен
- [ ] kubectl и helm установлены
- [ ] Репозиторий склонирован
- [ ] Параметры установки настроены
- [ ] Базовый стек установлен (`./scripts/setup.sh`)
- [ ] Все поды в статусе Running
- [ ] Grafana доступна и пароль изменен
- [ ] Ingress настроен (опционально)
- [ ] Приложение экспортирует метрики
- [ ] ServiceMonitor создан и применен
- [ ] Метрики видны в Prometheus
- [ ] Дашборды созданы в Grafana

---

**Готово!** Ваша система мониторинга развернута и готова к работе. 🎉
