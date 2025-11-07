# Инструкция по установке

Детальная инструкция по установке универсального стека мониторинга для Kubernetes.

## Требования

### Системные требования

- Kubernetes кластер версии 1.19 или выше
- Минимум 4 CPU и 8GB RAM на нодах
- Доступ к интернету для загрузки Helm charts
- StorageClass для динамического создания PersistentVolumes

### Дополнительные требования (для Ingress)

Если планируете использовать Ingress (`ENABLE_INGRESS=true`):

- **cert-manager** - для автоматической выдачи TLS сертификатов
- **Ingress Controller** - NGINX, Traefik или другой
- **ClusterIssuer** - для Let's Encrypt сертификатов

**Инструкция по установке**: См. [Настройка Ingress](ingress-setup.md#предварительные-требования)

### Необходимые инструменты

1. **kubectl** - для работы с Kubernetes
   ```bash
   # Проверка версии
   kubectl version --client
   ```

2. **Helm 3.x** - для установки Helm charts
   ```bash
   # Установка Helm (пример для Linux)
   curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

   # Проверка версии
   helm version
   ```

3. **Доступ к кластеру**
   ```bash
   # Проверка подключения
   kubectl cluster-info
   kubectl get nodes
   ```

## Установка

> **Развертывание на чистом Ubuntu сервере?**
> См. [Полная инструкция по развертыванию на Ubuntu](ubuntu-deployment.md)

### Шаг 1: Клонирование репозитория

```bash
git clone <repository-url>
cd monitoring
```

### Шаг 2: Настройка параметров

Установите переменные окружения:

```bash
export DOMAIN=example.com                    # Обязательно!
export GRAFANA_PASSWORD=secure_password     # Рекомендуется изменить
export MONITORING_NAMESPACE=monitoring      # По умолчанию: monitoring
export PROMETHEUS_RETENTION=15d             # Время хранения метрик
export PROMETHEUS_STORAGE=20Gi              # Размер хранилища
export LOKI_RETENTION=744h                  # Время хранения логов (31 день)
export LOKI_STORAGE=20Gi                    # Размер хранилища
export INSTALL_PORTAINER=false              # Установить Portainer
```

### Шаг 3: Запуск установки

```bash
./scripts/setup.sh
```

Скрипт выполнит:
1. Проверку зависимостей (kubectl, helm)
2. Создание namespace `monitoring`
3. Добавление Helm репозиториев
4. Установку Prometheus (kube-prometheus-stack)
5. Установку Loki + Promtail
6. Установку Portainer (если `INSTALL_PORTAINER=true`)

### Шаг 4: Проверка установки

```bash
# Проверка статуса подов
kubectl get pods -n monitoring

# Ожидаемый результат: все поды в статусе Running
```

Или используйте скрипт:

```bash
./scripts/check-status.sh
```

## Настройка доступа

### Вариант A: Ingress (рекомендуется для продакшена)

**Автоматическое создание Ingress** (рекомендуется):

```bash
export ENABLE_INGRESS=true
export INGRESS_CLASS=nginx  # Или traefik, зависит от вашего Ingress Controller
export MONITORING_DOMAIN=monitoring.example.com  # Опционально, по умолчанию: monitoring.${DOMAIN}
./scripts/setup.sh
```

Скрипт автоматически:
- Создаст Ingress для Grafana, Prometheus и Portainer (если установлен)
- Настроит TLS сертификаты через cert-manager
- Применит правильные annotations

**Подробная инструкция**: См. [Настройка Ingress](ingress-setup.md)

### Вариант B: Port Forward (для тестирования)

```bash
# Grafana
kubectl port-forward -n monitoring svc/kube-prometheus-stack-grafana 3000:80

# Prometheus
kubectl port-forward -n monitoring svc/prometheus-kube-prometheus-prometheus 9090:9090

# Loki
kubectl port-forward -n monitoring svc/loki 3100:3100
```

## Первый вход в Grafana

1. Откройте Grafana в браузере (через Ingress или port-forward)
2. Войдите с учетными данными:
   - Username: `admin`
   - Password: значение `GRAFANA_PASSWORD` (или `admin` по умолчанию)
3. **ВАЖНО**: Измените пароль при первом входе!

## Настройка DNS

Если используете Ingress (`ENABLE_INGRESS=true`), настройте DNS записи:

**Вариант 1: Wildcard запись (рекомендуется)**
```
*.monitoring.example.com  A  <IP_INGRESS_CONTROLLER>
```

**Вариант 2: Отдельные записи**
```
grafana.monitoring.example.com    A  <IP_INGRESS_CONTROLLER>
prometheus.monitoring.example.com A  <IP_INGRESS_CONTROLLER>
portainer.monitoring.example.com  A  <IP_INGRESS_CONTROLLER>
```

**Подробная инструкция**: См. [Настройка Ingress](ingress-setup.md)

## Проверка работоспособности

### Prometheus

**Важно**: Убедитесь, что Prometheus настроен на сбор метрик из всех namespace. Проверьте values файл:

```yaml
prometheus:
  prometheusSpec:
    serviceMonitorSelectorNilUsesHelmValues: false
    serviceMonitorNamespaceSelector: {}  # КРИТИЧНО для мультипроектности!
```

```bash
# Проверка targets
kubectl port-forward -n monitoring svc/prometheus-kube-prometheus-prometheus 9090:9090
# Откройте http://localhost:9090/targets
# Должны быть видны ServiceMonitor из всех namespace
```

### Grafana

```bash
# Проверка datasources
# Войдите в Grafana → Configuration → Data Sources
# Должны быть настроены:
# - Prometheus (http://prometheus-kube-prometheus-prometheus:9090)
# - Loki (http://loki:3100)
```

### Loki

```bash
# Проверка готовности
kubectl port-forward -n monitoring svc/loki 3100:3100
curl http://localhost:3100/ready
```

## Обновление

Для обновления стека:

```bash
export DOMAIN=example.com
export GRAFANA_PASSWORD=secure_password
./scripts/setup.sh
```

Скрипт автоматически обнаружит существующую установку и выполнит обновление.

## Удаление

```bash
# Удаление Helm releases
helm uninstall kube-prometheus-stack -n monitoring
helm uninstall loki -n monitoring
helm uninstall portainer -n monitoring  # если установлен

# Удаление namespace (опционально, удалит все данные!)
kubectl delete namespace monitoring
```

## Решение проблем

См. [troubleshooting.md](troubleshooting.md) для решения типичных проблем.

## Следующие шаги

После установки:

1. Настройте Ingress для доступа к сервисам
2. Измените пароль Grafana
3. Интегрируйте ваши проекты (см. [project-integration.md](project-integration.md))
