#!/bin/bash
# Скрипт для диагностики проблем с установкой Prometheus

NAMESPACE=${MONITORING_NAMESPACE:-monitoring}

echo "🔍 Диагностика Prometheus"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

echo -e "\n1. Статус Helm релиза:"
helm status kube-prometheus-stack -n "${NAMESPACE}" 2>/dev/null || echo "Релиз не найден"

echo -e "\n2. Поды Prometheus:"
kubectl get pods -n "${NAMESPACE}" -l app.kubernetes.io/name=prometheus

echo -e "\n3. Поды Grafana:"
kubectl get pods -n "${NAMESPACE}" -l app.kubernetes.io/name=grafana

echo -e "\n4. PVC (PersistentVolumeClaims):"
kubectl get pvc -n "${NAMESPACE}"

echo -e "\n5. События (последние 20):"
kubectl get events -n "${NAMESPACE}" --sort-by='.lastTimestamp' | tail -20

echo -e "\n6. Проблемные поды (если есть):"
kubectl get pods -n "${NAMESPACE}" | grep -v Running | grep -v Completed

echo -e "\n7. Логи Prometheus Operator (если есть проблемы):"
PROM_OP_POD=$(kubectl get pods -n "${NAMESPACE}" -l app.kubernetes.io/name=prometheus-operator -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
if [ -n "$PROM_OP_POD" ]; then
    echo "Логи ${PROM_OP_POD}:"
    kubectl logs -n "${NAMESPACE}" "${PROM_OP_POD}" --tail=50
fi

echo -e "\n8. StorageClass:"
kubectl get storageclass

echo -e "\n9. Ресурсы нод:"
kubectl top nodes 2>/dev/null || echo "metrics-server не установлен"

