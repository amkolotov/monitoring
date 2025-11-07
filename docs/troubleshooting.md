# Решение проблем

Типичные проблемы при работе с системой мониторинга и способы их решения.

## Prometheus не видит targets

### Симптомы

- В Prometheus UI (`/targets`) нет ваших сервисов
- ServiceMonitor создан, но targets не появляются

### Решение

1. **Проверьте ServiceMonitor**:
   ```bash
   kubectl get servicemonitor -n <namespace> -o yaml
   ```

2. **Проверьте labels в Service**:
   ```bash
   kubectl get svc -n <namespace> --show-labels
   ```
   **КРИТИЧНО**: Убедитесь, что:
   - Service имеет label `monitoring: enabled` - **ОБЯЗАТЕЛЬНО!**
   - Service имеет label `app`, который **ТОЧНО совпадает** с `selector.matchLabels.app` в ServiceMonitor
   - Без этих labels ServiceMonitor не сможет найти Service.

3. **Проверьте настройки Prometheus**:
   ```bash
   kubectl get prometheus -n monitoring -o yaml
   ```
   **КРИТИЧНО**: Убедитесь, что:
   - `serviceMonitorSelectorNilUsesHelmValues: false` - должно быть `false`
   - `serviceMonitorNamespaceSelector: {}` - **ОБЯЗАТЕЛЬНО** должно быть `{}` для мультипроектности

   Если `serviceMonitorNamespaceSelector` отсутствует или имеет другое значение, Prometheus не будет собирать метрики из всех namespace.

4. **Проверьте логи Prometheus Operator**:
   ```bash
   kubectl logs -n monitoring -l app.kubernetes.io/name=prometheus-operator
   ```

## Метрики не собираются

### Симптомы

- Targets показывают статус "DOWN"
- Метрики не появляются в Prometheus

### Решение

1. **Проверьте доступность эндпоинта метрик**:
   ```bash
   kubectl port-forward -n <namespace> svc/<service-name> 8000:80
   curl http://localhost:8000/metrics
   ```

2. **Проверьте путь к метрикам**:
   Убедитесь, что в ServiceMonitor указан правильный `path` (обычно `/metrics`).

3. **Проверьте имя порта**:
   Убедитесь, что в ServiceMonitor указано правильное имя порта из Service.

4. **Проверьте сетевую доступность**:
   ```bash
   # Из пода Prometheus
   kubectl exec -n monitoring -it <prometheus-pod> -- wget -O- http://<service>.<namespace>.svc.cluster.local/metrics
   ```

## Логи не появляются в Loki

### Симптомы

- Логи не отображаются в Grafana
- Promtail не собирает логи

### Решение

1. **Проверьте статус Promtail**:
   ```bash
   kubectl get pods -n monitoring | grep promtail
   kubectl logs -n monitoring -l app=promtail
   ```

2. **Проверьте labels подов**:
   ```bash
   kubectl get pods -n <namespace> --show-labels
   ```
   Promtail автоматически собирает логи всех подов, но labels помогают в фильтрации.

3. **Проверьте доступность Loki**:
   ```bash
   kubectl port-forward -n monitoring svc/loki 3100:3100
   curl http://localhost:3100/ready
   ```

4. **Проверьте конфигурацию Promtail**:
   ```bash
   kubectl get configmap -n monitoring promtail -o yaml
   ```

## Grafana не может подключиться к Prometheus

### Симптомы

- В Grafana нет данных
- Ошибка "Data source is not working"

### Решение

1. **Проверьте URL в datasource**:
   - Configuration → Data Sources → Prometheus
   - URL должен быть: `http://prometheus-kube-prometheus-prometheus:9090`

2. **Проверьте доступность Prometheus**:
   ```bash
   kubectl port-forward -n monitoring svc/prometheus-kube-prometheus-prometheus 9090:9090
   curl http://localhost:9090/api/v1/status/config
   ```

3. **Проверьте сетевую доступность**:
   ```bash
   # Из пода Grafana
   kubectl exec -n monitoring -it <grafana-pod> -- wget -O- http://prometheus-kube-prometheus-prometheus:9090/api/v1/status/config
   ```

## Grafana не может подключиться к Loki

### Симптомы

- Логи не отображаются в Grafana
- Ошибка при запросах к Loki

### Решение

1. **Проверьте URL в datasource**:
   - Configuration → Data Sources → Loki
   - URL должен быть: `http://loki:3100`

2. **Проверьте доступность Loki**:
   ```bash
   kubectl port-forward -n monitoring svc/loki 3100:3100
   curl http://localhost:3100/ready
   ```

## Проблемы с сертификатами (Ingress)

### Симптомы

- Ошибки SSL/TLS при доступе через Ingress
- Сертификаты не выдаются

### Решение

1. **Проверьте cert-manager**:
   ```bash
   kubectl get pods -n cert-manager
   ```

2. **Проверьте ClusterIssuer**:
   ```bash
   kubectl get clusterissuer
   ```

3. **Проверьте Certificate ресурсы**:
   ```bash
   kubectl get certificate -n monitoring
   kubectl describe certificate -n monitoring <cert-name>
   ```

## Проблемы с хранилищем

### Симптомы

- Под не может запуститься (Pending)
- Ошибки "PersistentVolumeClaim is not bound"

### Решение

1. **Проверьте StorageClass**:
   ```bash
   kubectl get storageclass
   ```

2. **Проверьте PVC**:
   ```bash
   kubectl get pvc -n monitoring
   kubectl describe pvc -n monitoring <pvc-name>
   ```

3. **Проверьте доступное место на нодах**:
   ```bash
   kubectl top nodes
   ```

## Высокое использование ресурсов

### Симптомы

- Поды перезапускаются
- OOMKilled ошибки

### Решение

1. **Проверьте использование ресурсов**:
   ```bash
   kubectl top pods -n monitoring
   ```

2. **Увеличьте лимиты** в values файлах:
   ```yaml
   resources:
     limits:
       cpu: 2000m
       memory: 4Gi
     requests:
       cpu: 1000m
       memory: 2Gi
   ```

3. **Уменьшите retention** для экономии места:
   ```yaml
   retention: 7d  # вместо 15d
   ```

## Проблемы с обновлением

### Симптомы

- Helm upgrade не работает
- Конфликты при обновлении

### Решение

1. **Проверьте текущие values**:
   ```bash
   helm get values kube-prometheus-stack -n monitoring
   ```

2. **Выполните dry-run**:
   ```bash
   helm upgrade kube-prometheus-stack prometheus-community/kube-prometheus-stack \
     -n monitoring \
     -f values/prometheus-values.yaml \
     --dry-run
   ```

3. **Проверьте версии charts**:
   ```bash
   helm search repo prometheus-community/kube-prometheus-stack
   ```

## Полезные команды

### Проверка статуса

```bash
# Статус всех компонентов
./scripts/check-status.sh

# Статус подов
kubectl get pods -n monitoring

# Статус ServiceMonitor
kubectl get servicemonitor --all-namespaces

# Логи Prometheus
kubectl logs -n monitoring -l app.kubernetes.io/name=prometheus

# Логи Promtail
kubectl logs -n monitoring -l app=promtail
```

### Отладка

```bash
# Port-forward для доступа к UI
kubectl port-forward -n monitoring svc/prometheus-kube-prometheus-prometheus 9090:9090
kubectl port-forward -n monitoring svc/kube-prometheus-stack-grafana 3000:80
kubectl port-forward -n monitoring svc/loki 3100:3100

# Проверка сетевой доступности
kubectl exec -n monitoring -it <pod-name> -- sh
# Внутри пода:
wget -O- http://prometheus-kube-prometheus-prometheus:9090/api/v1/status/config
```

## Получение помощи

Если проблема не решена:

1. Проверьте логи всех компонентов
2. Проверьте события Kubernetes:
   ```bash
   kubectl get events -n monitoring --sort-by='.lastTimestamp'
   ```
3. Создайте issue в репозитории с:
   - Описанием проблемы
   - Логами компонентов
   - Версиями Kubernetes и Helm
   - Конфигурацией (без секретов)
