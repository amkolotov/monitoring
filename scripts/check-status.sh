#!/bin/bash
# Проверка статуса стека мониторинга

NAMESPACE=${MONITORING_NAMESPACE:-monitoring}

echo "📊 Monitoring Stack Status"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Проверка подов
echo "Pods:"
kubectl get pods -n $NAMESPACE

# Проверка ServiceMonitor
echo ""
echo "ServiceMonitors (all namespaces):"
kubectl get servicemonitor --all-namespaces

# Проверка Prometheus targets (если доступен port-forward)
echo ""
echo "Prometheus Targets:"
kubectl port-forward -n $NAMESPACE svc/prometheus-kube-prometheus-prometheus 9090:9090 > /dev/null 2>&1 &
PF_PID=$!
sleep 2
if command -v jq &> /dev/null; then
    curl -s http://localhost:9090/api/v1/targets 2>/dev/null | jq -r '.data.activeTargets[] | "\(.labels.job) - \(.health) - \(.lastError // "OK")"' || echo "Не удалось получить targets"
else
    echo "Установите jq для детального вывода targets"
    curl -s http://localhost:9090/api/v1/targets 2>/dev/null | grep -o '"job":"[^"]*"' || echo "Не удалось получить targets"
fi
kill $PF_PID 2>/dev/null
