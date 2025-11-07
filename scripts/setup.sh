#!/bin/bash
set -euo pipefail

# ============================================
# Скрипт установки универсального стека мониторинга
# ============================================
#
# Этот скрипт устанавливает базовый стек мониторинга для Kubernetes:
# - Prometheus (kube-prometheus-stack)
# - Loki + Promtail
# - Portainer (опционально)
#
# Использование:
#   export DOMAIN=example.com
#   export GRAFANA_PASSWORD=secure_password
#   ./scripts/setup.sh
#
# Параметры (через переменные окружения):
#   DOMAIN                  - базовый домен (обязательно)
#   MONITORING_NAMESPACE   - namespace для мониторинга (по умолчанию: monitoring)
#   GRAFANA_PASSWORD       - пароль Grafana (по умолчанию: admin)
#   ACME_EMAIL            - email для Let's Encrypt (по умолчанию: admin@${DOMAIN})
#   PROMETHEUS_RETENTION  - время хранения метрик (по умолчанию: 15d)
#   PROMETHEUS_STORAGE    - размер хранилища Prometheus (по умолчанию: 20Gi)
#   LOKI_RETENTION        - время хранения логов (по умолчанию: 744h = 31 день)
#   LOKI_STORAGE          - размер хранилища Loki (по умолчанию: 20Gi)
#   INSTALL_PORTAINER     - установить Portainer (по умолчанию: false)
#   ENABLE_INGRESS        - включить Ingress для сервисов (по умолчанию: false)
#   INGRESS_CLASS         - класс Ingress Controller (по умолчанию: nginx)
#   ACME_EMAIL           - email для Let's Encrypt (опционально, по умолчанию: admin@${DOMAIN})

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Функция для вывода сообщений
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Проверка зависимостей
check_dependencies() {
    log_info "Проверка зависимостей..."

    local missing_deps=()

    if ! command -v kubectl &> /dev/null; then
        missing_deps+=("kubectl")
    fi

    if ! command -v helm &> /dev/null; then
        missing_deps+=("helm")
    fi

    if [ ${#missing_deps[@]} -ne 0 ]; then
        log_error "Отсутствуют необходимые зависимости: ${missing_deps[*]}"
        log_info "Установите их перед продолжением:"
        log_info "  kubectl: https://kubernetes.io/docs/tasks/tools/"
        log_info "  helm: https://helm.sh/docs/intro/install/"
        exit 1
    fi

    # Проверка подключения к кластеру
    if ! kubectl cluster-info &> /dev/null; then
        log_error "Не удается подключиться к Kubernetes кластеру"
        log_info "Убедитесь, что kubectl настроен правильно"
        exit 1
    fi

    log_info "Все зависимости установлены ✓"
}

# Параметры по умолчанию
DOMAIN=${DOMAIN:-}
MONITORING_NAMESPACE=${MONITORING_NAMESPACE:-monitoring}
GRAFANA_PASSWORD=${GRAFANA_PASSWORD:-admin}
ACME_EMAIL=${ACME_EMAIL:-}
PROMETHEUS_RETENTION=${PROMETHEUS_RETENTION:-15d}
PROMETHEUS_STORAGE=${PROMETHEUS_STORAGE:-20Gi}
LOKI_RETENTION=${LOKI_RETENTION:-744h}
LOKI_STORAGE=${LOKI_STORAGE:-20Gi}
INSTALL_PORTAINER=${INSTALL_PORTAINER:-false}
ENABLE_INGRESS=${ENABLE_INGRESS:-false}
INGRESS_CLASS=${INGRESS_CLASS:-nginx}

# Проверка обязательных параметров
if [ -z "$DOMAIN" ]; then
    log_error "DOMAIN не установлен (обязательный параметр)"
    log_info "Установите DOMAIN перед запуском:"
    log_info "  export DOMAIN=example.com"
    exit 1
fi

# Установка ACME_EMAIL по умолчанию (если не указан)
if [ -z "$ACME_EMAIL" ]; then
    ACME_EMAIL="admin@${DOMAIN}"
    log_warn "ACME_EMAIL не установлен, используется: ${ACME_EMAIL}"
    log_warn "Рекомендуется указать ACME_EMAIL явно для получения уведомлений от Let's Encrypt"
fi

# Предупреждение о пароле Grafana
if [ "$GRAFANA_PASSWORD" == "admin" ]; then
    log_warn "Используется пароль по умолчанию для Grafana (admin)"
    log_warn "ВНИМАНИЕ: Измените пароль после установки!"
fi

log_info "Параметры установки:"
log_info "  DOMAIN: ${DOMAIN}"
log_info "  MONITORING_NAMESPACE: ${MONITORING_NAMESPACE}"
log_info "  GRAFANA_PASSWORD: ${GRAFANA_PASSWORD:0:3}***"
log_info "  ACME_EMAIL: ${ACME_EMAIL}"
log_info "  PROMETHEUS_RETENTION: ${PROMETHEUS_RETENTION}"
log_info "  PROMETHEUS_STORAGE: ${PROMETHEUS_STORAGE}"
log_info "  LOKI_RETENTION: ${LOKI_RETENTION}"
log_info "  LOKI_STORAGE: ${LOKI_STORAGE}"
log_info "  INSTALL_PORTAINER: ${INSTALL_PORTAINER}"
log_info "  ENABLE_INGRESS: ${ENABLE_INGRESS}"
if [ "$ENABLE_INGRESS" == "true" ]; then
  log_info "  INGRESS_CLASS: ${INGRESS_CLASS}"
fi

# Проверка зависимостей
check_dependencies

# Получаем директорию скрипта и корень проекта
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Создание namespace (idempotent)
log_info "Создание namespace ${MONITORING_NAMESPACE}..."
kubectl apply -f "${PROJECT_ROOT}/base/namespace.yaml" || true
kubectl label namespace "${MONITORING_NAMESPACE}" monitoring=enabled --overwrite || true

# Добавление Helm репозиториев
log_info "Добавление Helm репозиториев..."
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts || true
helm repo add grafana https://grafana.github.io/helm-charts || true
helm repo add portainer https://portainer.github.io/k8s/ || true
helm repo update

# Подготовка values файлов с подстановкой переменных
log_info "Подготовка конфигурации..."

# Prometheus values
PROMETHEUS_VALUES="${PROJECT_ROOT}/values/prometheus-values.yaml"
PROMETHEUS_VALUES_TMP=$(mktemp)

# Базовые замены
sed -e "s|retention: 15d|retention: ${PROMETHEUS_RETENTION}|g" \
    -e "s|storage: 20Gi|storage: ${PROMETHEUS_STORAGE}|g" \
    -e "s|adminPassword: admin|adminPassword: ${GRAFANA_PASSWORD}|g" \
    "${PROMETHEUS_VALUES}" > "${PROMETHEUS_VALUES_TMP}"

# Замена для Ingress (если включен)
if [ "$ENABLE_INGRESS" == "true" ]; then
  log_info "Настройка Ingress для Prometheus и Grafana..."
  sed -i \
    -e "s|PLACEHOLDER_DOMAIN|${DOMAIN}|g" \
    -e "s|ingressClassName: nginx|ingressClassName: ${INGRESS_CLASS}|g" \
    -e "s|enabled: false  # Включается через переменную ENABLE_INGRESS|enabled: true|g" \
    "${PROMETHEUS_VALUES_TMP}"
fi

# Loki values
LOKI_VALUES="${PROJECT_ROOT}/values/loki-values.yaml"
LOKI_VALUES_TMP=$(mktemp)
sed -e "s|retention_period: 744h|retention_period: ${LOKI_RETENTION}|g" \
    -e "s|size: 20Gi|size: ${LOKI_STORAGE}|g" \
    "${LOKI_VALUES}" > "${LOKI_VALUES_TMP}"

# Установка Prometheus (kube-prometheus-stack)
log_info "Установка Prometheus (kube-prometheus-stack)..."
if helm list -n "${MONITORING_NAMESPACE}" | grep -q "kube-prometheus-stack"; then
    log_warn "Prometheus уже установлен, выполняется обновление..."
    helm upgrade kube-prometheus-stack prometheus-community/kube-prometheus-stack \
        -n "${MONITORING_NAMESPACE}" \
        -f "${PROMETHEUS_VALUES_TMP}" \
        --wait \
        --timeout 10m
else
    helm install kube-prometheus-stack prometheus-community/kube-prometheus-stack \
        -n "${MONITORING_NAMESPACE}" \
        -f "${PROMETHEUS_VALUES_TMP}" \
        --create-namespace \
        --wait \
        --timeout 10m
fi

# Установка Loki
log_info "Установка Loki..."
if helm list -n "${MONITORING_NAMESPACE}" | grep -q "loki"; then
    log_warn "Loki уже установлен, выполняется обновление..."
    helm upgrade loki grafana/loki-stack \
        -n "${MONITORING_NAMESPACE}" \
        -f "${LOKI_VALUES_TMP}" \
        --wait \
        --timeout 10m
else
    helm install loki grafana/loki-stack \
        -n "${MONITORING_NAMESPACE}" \
        -f "${LOKI_VALUES_TMP}" \
        --create-namespace \
        --wait \
        --timeout 10m
fi

# Установка Portainer (опционально)
if [ "$INSTALL_PORTAINER" == "true" ]; then
    log_info "Установка Portainer..."
    PORTAINER_VALUES="${PROJECT_ROOT}/values/portainer-values.yaml"
    PORTAINER_VALUES_TMP=$(mktemp)

    # Копируем values
    cp "${PORTAINER_VALUES}" "${PORTAINER_VALUES_TMP}"

    # Замена для Ingress (если включен)
    if [ "$ENABLE_INGRESS" == "true" ]; then
      log_info "Настройка Ingress для Portainer..."
      sed -i \
        -e "s|PLACEHOLDER_DOMAIN|${DOMAIN}|g" \
        -e "s|ingressClassName: nginx|ingressClassName: ${INGRESS_CLASS}|g" \
        -e "s|enabled: false  # Включается через переменную ENABLE_INGRESS|enabled: true|g" \
        "${PORTAINER_VALUES_TMP}"
    fi

    if helm list -n "${MONITORING_NAMESPACE}" | grep -q "portainer"; then
        log_warn "Portainer уже установлен, выполняется обновление..."
        helm upgrade portainer portainer/portainer \
            -n "${MONITORING_NAMESPACE}" \
            -f "${PORTAINER_VALUES_TMP}" \
            --wait \
            --timeout 10m
    else
        helm install portainer portainer/portainer \
            -n "${MONITORING_NAMESPACE}" \
            -f "${PORTAINER_VALUES_TMP}" \
            --create-namespace \
            --wait \
            --timeout 10m
    fi

    rm -f "${PORTAINER_VALUES_TMP}"
else
    log_info "Portainer пропущен (INSTALL_PORTAINER=false)"
fi

# Очистка временных файлов
rm -f "${PROMETHEUS_VALUES_TMP}" "${LOKI_VALUES_TMP}"

# Проверка статуса
log_info "Проверка статуса установки..."
kubectl get pods -n "${MONITORING_NAMESPACE}"

# Проверка Ingress (если включен)
if [ "$ENABLE_INGRESS" == "true" ]; then
  log_info ""
  log_info "Проверка Ingress..."
  kubectl get ingress -n "${MONITORING_NAMESPACE}" || log_warn "Ingress еще не созданы (может потребоваться время для cert-manager)"

  log_info ""
  log_info "URL сервисов мониторинга:"
  log_info "  Grafana:    https://grafana.${DOMAIN}"
  log_info "  Prometheus: https://prometheus.${DOMAIN}"
  if [ "$INSTALL_PORTAINER" == "true" ]; then
    log_info "  Portainer:  https://portainer.${DOMAIN}"
  fi
  log_info ""
  log_info "ВАЖНО: Настройте DNS записи:"
  log_info "  *.${DOMAIN} → IP вашего Ingress Controller"
  log_info "  Или отдельные A-записи для каждого поддомена"
fi

log_info ""
log_info "✅ Установка завершена успешно!"
log_info ""
log_info "Следующие шаги:"
if [ "$ENABLE_INGRESS" != "true" ]; then
  log_info "  1. Настройте Ingress для доступа к сервисам (ENABLE_INGRESS=true)"
fi
log_info "  2. Измените пароль Grafana (текущий: ${GRAFANA_PASSWORD})"
log_info "  3. Создайте ServiceMonitor для ваших проектов"
log_info ""
log_info "Документация:"
log_info "  - Установка: docs/installation.md"
log_info "  - Интеграция проектов: docs/project-integration.md"
if [ "$ENABLE_INGRESS" == "true" ]; then
  log_info "  - Настройка Ingress: docs/ingress-setup.md"
fi
log_info ""
