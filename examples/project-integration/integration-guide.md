# Интеграция проекта с системой мониторинга

## Предварительные требования

1. На сервере установлен базовый стек мониторинга (выполнен `./scripts/setup.sh`)
2. В вашем проекте есть сервисы с метриками Prometheus
3. У вас есть доступ к кластеру Kubernetes

## Шаги интеграции

### 1. Добавьте labels к вашим Service

В вашем Service добавьте обязательные labels:

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
```

### 2. Создайте ServiceMonitor

Скопируйте шаблон из `monitoring-stack/templates/servicemonitor-template.yaml`
и настройте под ваш проект:

```yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: myapp-web-http
  namespace: myproject  # Или monitoring для централизованного управления
  labels:
    app: myapp
    monitoring: enabled
    project: myproject
spec:
  selector:
    matchLabels:
      app: myapp-web-http
      monitoring: enabled
  namespaceSelector:
    matchNames:
      - myproject
  endpoints:
  - port: http
    path: /metrics
    interval: 30s
```

### 3. Примените манифест

```bash
kubectl apply -f servicemonitor.yaml
```

### 4. Проверка

```bash
# Проверьте что ServiceMonitor создан
kubectl get servicemonitor -n myproject

# Проверьте что Prometheus видит targets
kubectl port-forward -n monitoring svc/prometheus-kube-prometheus-prometheus 9090:9090
# Откройте http://localhost:9090/targets
# Должен появиться ваш сервис в списке
```

## Несколько проектов на одном сервере

Система мониторинга автоматически собирает метрики из всех namespace,
где есть ServiceMonitor с label `monitoring: enabled`.

**Просто создайте ServiceMonitor в каждом проекте по шаблону выше.**

Prometheus автоматически обнаружит все ServiceMonitor во всех namespace
(благодаря настройке `serviceMonitorNamespaceSelector: {}`).

## Фильтрация в Grafana

Используйте label `namespace` или `project` в запросах PromQL:

```promql
# Метрики конкретного проекта
rate(http_requests_total{namespace="myproject"}[5m])

# Метрики всех проектов
rate(http_requests_total[5m])

# Группировка по проектам
sum by (project) (rate(http_requests_total[5m]))
```

## Логи

Логи собираются автоматически из всех подов во всех namespace.
Фильтруйте по label `namespace` в Loki:

```logql
{namespace="myproject"}
```
