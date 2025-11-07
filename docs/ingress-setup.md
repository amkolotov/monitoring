# Настройка Ingress для сервисов мониторинга

Инструкция по настройке Ingress для доступа к сервисам мониторинга через доменные имена.

## Обзор

Система мониторинга поддерживает автоматическое создание Ingress для:
- **Grafana** - визуализация метрик и логов
- **Prometheus** - сбор и хранение метрик
- **Portainer** - управление Kubernetes (опционально)

## Принципы архитектуры

### Централизованное управление

**КРИТИЧНО**: Все Ingress для сервисов мониторинга:
- ✅ Находятся в namespace `monitoring`
- ✅ Управляются системой мониторинга, а не проектами
- ✅ Создаются автоматически при установке (если `ENABLE_INGRESS=true`)

**Проекты НЕ должны**:
- ❌ Создавать Ingress для сервисов мониторинга
- ❌ Управлять доступом к мониторингу
- ❌ Использовать домены проектов для мониторинга

## Доменная структура

### Рекомендуемый вариант: Поддомены

**Структура:**
```
grafana.<domain>      → Grafana UI
prometheus.<domain>   → Prometheus UI
portainer.<domain>    → Portainer UI
```

**Пример:**
```
grafana.example.com
prometheus.example.com
portainer.example.com
```

**Преимущества:**
- Понятная и логичная структура
- Легко настраивать DNS (одна A-запись для `*.example.com`)
- Можно выдавать отдельные сертификаты для каждого сервиса
- Удобно для разных уровней доступа

## Предварительные требования

### Установка cert-manager

**КРИТИЧНО**: Перед использованием Ingress необходимо установить cert-manager для автоматической выдачи TLS сертификатов.

#### Установка cert-manager

```bash
# Добавление Helm репозитория
helm repo add jetstack https://charts.jetstack.io
helm repo update

# Установка cert-manager
helm install cert-manager jetstack/cert-manager \
  --namespace cert-manager \
  --create-namespace \
  --set installCRDs=true \
  --set global.leaderElection.namespace=cert-manager

# Проверка установки
kubectl get pods -n cert-manager
```

Все поды должны быть в статусе `Running`.

#### Создание ClusterIssuer

Создайте ClusterIssuer для автоматической выдачи сертификатов Let's Encrypt.

**Вариант 1: Использовать готовый манифест** (рекомендуется):

```bash
# Отредактируйте манифест
nano base/cert-manager-issuer.yaml

# Замените:
# - email: admin@example.com → ваш email
# - class: nginx → ваш Ingress Controller класс (если отличается)

# Примените
kubectl apply -f base/cert-manager-issuer.yaml
```

**Вариант 2: Создать вручную**:

```yaml
# letsencrypt-issuer.yaml
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-prod
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    email: admin@example.com  # ЗАМЕНИТЕ на ваш email!
    privateKeySecretRef:
      name: letsencrypt-prod
    solvers:
    - http01:
        ingress:
          class: nginx  # ЗАМЕНИТЕ на ваш Ingress Controller класс!
```

Примените манифест:

```bash
kubectl apply -f letsencrypt-issuer.yaml
```

**Проверка**:
```bash
kubectl get clusterissuer
kubectl describe clusterissuer letsencrypt-prod
```

Статус должен быть `Ready`.

**Важно**:
- ✅ Замените `email` на ваш реальный email (обязательно!)
- ✅ Замените `class: nginx` на класс вашего Ingress Controller (если отличается)
- ⚠️ Для тестирования можно использовать `letsencrypt-staging` (сервер: `https://acme-staging-v02.api.letsencrypt.org/directory`), но он выдает невалидные сертификаты

### Установка Ingress Controller

Убедитесь, что Ingress Controller установлен:

```bash
# Проверка Ingress Controller
kubectl get ingressclass
kubectl get pods -n ingress-nginx  # Для nginx
```

Если не установлен, установите:

**NGINX Ingress Controller**:
```bash
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm install ingress-nginx ingress-nginx/ingress-nginx \
  --namespace ingress-nginx \
  --create-namespace
```

**Traefik** (альтернатива):
```bash
helm repo add traefik https://traefik.github.io/charts
helm install traefik traefik/traefik \
  --namespace traefik \
  --create-namespace
```

## Установка с Ingress

**ВАЖНО**: Перед запуском установки убедитесь, что:
1. ✅ cert-manager установлен (см. раздел выше)
2. ✅ ClusterIssuer создан (см. раздел выше)
3. ✅ Ingress Controller установлен (см. раздел выше)

### Шаг 1: Настройка параметров

```bash
export DOMAIN=example.com
export GRAFANA_PASSWORD=secure_password
export ENABLE_INGRESS=true
export INGRESS_CLASS=nginx  # Или traefik, зависит от вашего Ingress Controller
export ACME_EMAIL=admin@example.com  # Email для Let's Encrypt (опционально, по умолчанию: admin@${DOMAIN})
```

### Шаг 2: Запуск установки

```bash
./scripts/setup.sh
```

Скрипт автоматически:
- Создаст Ingress для Grafana, Prometheus и Portainer (если установлен)
- Настроит TLS сертификаты через cert-manager
- Применит правильные annotations

### Шаг 3: Настройка DNS

Добавьте DNS записи:

**Вариант 1: Wildcard запись (рекомендуется)**
```
*.example.com  A  <IP_INGRESS_CONTROLLER>
```

**Вариант 2: Отдельные записи**
```
grafana.example.com    A  <IP_INGRESS_CONTROLLER>
prometheus.example.com A  <IP_INGRESS_CONTROLLER>
portainer.example.com  A  <IP_INGRESS_CONTROLLER>
```

### Шаг 4: Проверка

```bash
# Проверка Ingress
kubectl get ingress -n monitoring

# Проверка сертификатов
kubectl get certificate -n monitoring

# Проверка доступности
curl -I https://grafana.example.com
curl -I https://prometheus.example.com
```

## Параметры установки

### ENABLE_INGRESS

Включает создание Ingress для всех сервисов мониторинга.

```bash
export ENABLE_INGRESS=true
```

**По умолчанию**: `false` (Ingress не создаются)

### INGRESS_CLASS

Класс Ingress Controller для использования.

```bash
export INGRESS_CLASS=nginx  # Или traefik, istio, и т.д.
```

**По умолчанию**: `nginx`

**Поддерживаемые значения:**
- `nginx` - NGINX Ingress Controller
- `traefik` - Traefik Ingress Controller
- `istio` - Istio Gateway
- Другие классы, установленные в кластере

### ACME_EMAIL

Email для Let's Encrypt сертификатов.

```bash
export ACME_EMAIL=admin@example.com
```

**По умолчанию**: `admin@${DOMAIN}`

**Важно**: Рекомендуется указать явно для получения уведомлений от Let's Encrypt.

## Безопасность

### Prometheus (критично защитить)

Prometheus содержит чувствительные данные и должен быть защищен:

**Вариант 1: Whitelist IP (рекомендуется)**

Отредактируйте `values/prometheus-values.yaml`:

```yaml
prometheus:
  ingress:
    annotations:
      nginx.ingress.kubernetes.io/whitelist-source-range: "10.0.0.0/8,172.16.0.0/12,192.168.0.0/16"
```

**Вариант 2: Базовая аутентификация**

1. Создайте Secret:
```bash
htpasswd -c auth prometheus
kubectl create secret generic prometheus-auth \
  --from-file=auth \
  -n monitoring
```

2. Отредактируйте `values/prometheus-values.yaml`:
```yaml
prometheus:
  ingress:
    annotations:
      nginx.ingress.kubernetes.io/auth-type: basic
      nginx.ingress.kubernetes.io/auth-secret: prometheus-auth
```

**Вариант 3: VPN/SSH туннель**

Не создавайте публичный Ingress для Prometheus, используйте port-forward:
```bash
kubectl port-forward -n monitoring svc/prometheus-kube-prometheus-prometheus 9090:9090
```

### Grafana

Grafana имеет встроенную аутентификацию:
- Настройте OAuth, LDAP или используйте встроенную аутентификацию
- Ограничьте доступ по IP (опционально)

### Portainer

Рекомендуется ограничить доступ:
- Whitelist IP для администраторов
- Настроить аутентификацию в Portainer

## Проверка после установки

### 1. Проверка Ingress

```bash
kubectl get ingress -n monitoring
```

Должны быть созданы:
- `kube-prometheus-stack-grafana`
- `kube-prometheus-stack-prometheus`
- `portainer` (если установлен)

### 2. Проверка сертификатов

```bash
kubectl get certificate -n monitoring
kubectl describe certificate -n monitoring
```

Сертификаты должны быть выданы cert-manager.

### 3. Проверка доступности

```bash
# Grafana
curl -I https://grafana.${DOMAIN}

# Prometheus
curl -I https://prometheus.${DOMAIN}

# Portainer (если установлен)
curl -I https://portainer.${DOMAIN}
```

### 4. Проверка DNS

```bash
# Проверка разрешения DNS
nslookup grafana.${DOMAIN}
nslookup prometheus.${DOMAIN}
```

## Troubleshooting

### Ingress не создаются

**Проблема**: После установки Ingress не появляются

**Решение**:
1. Проверьте, что `ENABLE_INGRESS=true`
2. Проверьте логи Helm:
   ```bash
   helm get manifest kube-prometheus-stack -n monitoring | grep ingress
   ```
3. Проверьте, что Ingress Controller установлен:
   ```bash
   kubectl get ingressclass
   ```

### Сертификаты не выдаются

**Проблема**: Certificate в статусе `Pending` или `Failed`

**Решение**:
1. **Проверьте, что cert-manager установлен**:
   ```bash
   kubectl get pods -n cert-manager
   # Все поды должны быть Running
   ```

   Если не установлен, см. раздел [Установка cert-manager](#установка-cert-manager)

2. **Проверьте ClusterIssuer**:
   ```bash
   kubectl get clusterissuer
   kubectl describe clusterissuer letsencrypt-prod
   ```

   Если ClusterIssuer отсутствует, создайте его (см. раздел [Создание ClusterIssuer](#создание-clusterissuer))

3. **Проверьте события**:
   ```bash
   kubectl describe certificate -n monitoring <cert-name>
   kubectl get events -n monitoring --sort-by='.lastTimestamp'
   kubectl logs -n cert-manager -l app=cert-manager
   ```

4. **Проверьте Challenge ресурсы**:
   ```bash
   kubectl get challenges -n monitoring
   kubectl describe challenge -n monitoring <challenge-name>
   ```

5. **Проверьте DNS**:
   - DNS записи должны указывать на IP Ingress Controller
   - Домены должны быть доступны из интернета (для Let's Encrypt)

### DNS не разрешается

**Проблема**: Домены не доступны

**Решение**:
1. Проверьте DNS записи:
   ```bash
   nslookup grafana.${DOMAIN}
   ```
2. Проверьте IP Ingress Controller:
   ```bash
   kubectl get svc -n ingress-nginx  # Для nginx
   ```
3. Убедитесь, что DNS записи указывают на правильный IP

### 502 Bad Gateway

**Проблема**: Ingress доступен, но сервис не отвечает

**Решение**:
1. Проверьте поды:
   ```bash
   kubectl get pods -n monitoring
   ```
2. Проверьте Service:
   ```bash
   kubectl get svc -n monitoring
   ```
3. Проверьте логи Ingress Controller:
   ```bash
   kubectl logs -n ingress-nginx <ingress-controller-pod>
   ```

## Обновление Ingress

Для обновления Ingress (например, изменение домена):

1. Обновите переменные окружения
2. Запустите scripts/setup.sh снова:
   ```bash
   export ENABLE_INGRESS=true
   export DOMAIN=new-domain.example.com
   ./scripts/setup.sh
   ```

Helm автоматически обновит Ingress.

## Отключение Ingress

Для отключения Ingress:

1. Установите `ENABLE_INGRESS=false`
2. Запустите scripts/setup.sh:
   ```bash
   export ENABLE_INGRESS=false
   ./scripts/setup.sh
   ```

Или удалите Ingress вручную:
```bash
kubectl delete ingress -n monitoring --all
```

## Дополнительные настройки

### Кастомные annotations

Для добавления кастомных annotations отредактируйте values файлы:

```yaml
prometheus:
  ingress:
    annotations:
      cert-manager.io/cluster-issuer: letsencrypt-prod
      nginx.ingress.kubernetes.io/rate-limit: "100"
      # Ваши кастомные annotations
```

### Path-based routing

Если нужен path-based routing вместо поддоменов, отредактируйте values:

```yaml
grafana:
  ingress:
    hosts:
      - example.com
    paths:
      - path: /grafana
        pathType: Prefix
```

**Не рекомендуется** - используйте поддомены для лучшей изоляции.

## Документация

- [Установка](installation.md) - Общая инструкция по установке
- [Интеграция проектов](project-integration.md) - Подключение проектов
- [Troubleshooting](troubleshooting.md) - Решение проблем

---

**Важно**: Все Ingress управляются системой мониторинга. Проекты не должны создавать Ingress для сервисов мониторинга!
