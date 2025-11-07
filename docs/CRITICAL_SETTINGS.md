# Критические настройки для мультипроектности

Этот документ описывает критические настройки, которые **ОБЯЗАТЕЛЬНЫ** для работы универсальной системы мониторинга с несколькими проектами.

## ⚠️ ВАЖНО: Без этих настроек система не будет работать правильно!

## 1. Prometheus: serviceMonitorNamespaceSelector

**Файл**: `values/prometheus-values.yaml`

**Критическая настройка**:
```yaml
prometheus:
  prometheusSpec:
    serviceMonitorSelectorNilUsesHelmValues: false
    serviceMonitorNamespaceSelector: {}  # КРИТИЧНО! Должно быть {}
```

**Почему это важно**:
- Без `serviceMonitorNamespaceSelector: {}` Prometheus будет собирать метрики **только** из namespace `monitoring`
- С этой настройкой Prometheus собирает метрики из **всех** namespace
- Это основа мультипроектности системы

**Проверка**:
```bash
kubectl get prometheus -n monitoring -o yaml | grep serviceMonitorNamespaceSelector
# Должно быть: serviceMonitorNamespaceSelector: {}
```

## 2. Service: label `monitoring: enabled`

**Критический label**:
```yaml
apiVersion: v1
kind: Service
metadata:
  labels:
    app: myapp-web-http
    monitoring: enabled  # ОБЯЗАТЕЛЬНО!
    project: myproject   # Рекомендуется
```

**Почему это важно**:
- ServiceMonitor ищет Service по labels
- Без `monitoring: enabled` ServiceMonitor не найдет Service
- Это принцип явной фильтрации - только Service с этим label мониторятся

**Проверка**:
```bash
kubectl get svc -n <namespace> --show-labels | grep monitoring
# Должно быть: monitoring=enabled
```

## 3. ServiceMonitor: selector с `monitoring: enabled`

**Критическая настройка**:
```yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
spec:
  selector:
    matchLabels:
      app: myapp-web-http
      monitoring: enabled  # ОБЯЗАТЕЛЬНО!
```

**Почему это важно**:
- ServiceMonitor должен явно требовать label `monitoring: enabled`
- Это обеспечивает принцип явной фильтрации
- Без этого ServiceMonitor может найти неправильные Service

**Проверка**:
```bash
kubectl get servicemonitor -n <namespace> -o yaml | grep -A 5 "matchLabels"
# Должно быть: monitoring: enabled
```

## 4. ServiceMonitor: metadata label `monitoring: enabled`

**Рекомендуемая настройка**:
```yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  labels:
    app: myproject
    monitoring: enabled  # Рекомендуется
    project: myproject
```

**Почему это важно**:
- Позволяет фильтровать ServiceMonitor по label
- Обеспечивает единообразие с другими ресурсами
- Упрощает управление и отладку

## 5. ServiceMonitor: namespaceSelector с matchNames

**Рекомендуемая настройка**:
```yaml
spec:
  namespaceSelector:
    matchNames:
      - myproject  # Явно указываем namespace
```

**Альтернатива** (менее явная):
```yaml
spec:
  namespaceSelector:
    any: true  # Работает, но менее явно
```

**Почему это важно**:
- `matchNames` явно указывает namespace - более понятно
- `any: true` работает, но может быть менее понятно для новых пользователей
- Рекомендуется использовать `matchNames` для явности

## Чеклист критических настроек

Перед использованием системы мониторинга проверьте:

- [ ] `serviceMonitorNamespaceSelector: {}` в prometheus-values.yaml
- [ ] Все Service имеют label `monitoring: enabled`
- [ ] Все ServiceMonitor требуют `monitoring: enabled` в selector
- [ ] Все ServiceMonitor имеют label `monitoring: enabled` в metadata
- [ ] Labels в Service совпадают с selector в ServiceMonitor

## Последствия отсутствия критических настроек

### Без `serviceMonitorNamespaceSelector: {}`:
- ❌ Prometheus не будет собирать метрики из namespace проектов
- ❌ Новые проекты не подключатся к мониторингу
- ❌ Система не будет мультипроектной

### Без `monitoring: enabled` в Service:
- ❌ ServiceMonitor не найдет Service
- ❌ Метрики не будут собираться
- ❌ Нарушается принцип явной фильтрации

### Без `monitoring: enabled` в selector ServiceMonitor:
- ❌ ServiceMonitor может найти неправильные Service
- ❌ Нарушается принцип явной фильтрации
- ❌ Могут собираться метрики нежелательных сервисов

## Проверка всех критических настроек

```bash
# 1. Проверка Prometheus
kubectl get prometheus -n monitoring -o yaml | grep -A 2 serviceMonitorNamespaceSelector

# 2. Проверка Service labels
kubectl get svc --all-namespaces --show-labels | grep monitoring

# 3. Проверка ServiceMonitor selector
kubectl get servicemonitor --all-namespaces -o yaml | grep -A 5 "matchLabels"

# 4. Проверка ServiceMonitor metadata
kubectl get servicemonitor --all-namespaces --show-labels | grep monitoring
```

## Дополнительные ресурсы

- [Установка](installation.md) - Как установить систему
- [Интеграция проектов](project-integration.md) - Как подключить проект
- [Troubleshooting](troubleshooting.md) - Решение проблем
- [Архитектура](architecture.md) - Архитектура системы

---

**Помните**: Эти настройки критичны для работы системы. Без них мультипроектность не будет работать!
