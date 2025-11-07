#!/bin/bash
set -e

echo "=== Проверка текущего состояния RBAC ==="
echo ""
echo "1. ClusterRole:"
kubectl get clusterrole portainer-cluster-admin 2>/dev/null || echo "ClusterRole не найден"
echo ""
echo "2. ClusterRoleBinding:"
kubectl get clusterrolebinding portainer-cluster-admin -o yaml 2>/dev/null || echo "ClusterRoleBinding не найден"
echo ""
echo "3. ServiceAccount:"
kubectl get serviceaccount portainer-sa-clusteradmin -n management 2>/dev/null || echo "ServiceAccount не найден"
echo ""
echo "4. Проверка прав:"
kubectl auth can-i list namespaces --as=system:serviceaccount:management:portainer-sa-clusteradmin 2>/dev/null || echo "Нет прав"
echo ""

echo "=== Исправление RBAC ==="

# Удаляем старые ресурсы
echo "Удаление старых RBAC ресурсов..."
kubectl delete clusterrolebinding portainer-cluster-admin portainer 2>/dev/null || true
kubectl delete clusterrole portainer-cluster-admin portainer 2>/dev/null || true

# Создаем ClusterRole с полными правами
echo "Создание ClusterRole..."
kubectl apply -f - <<EOF
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: portainer-cluster-admin
  labels:
    app.kubernetes.io/name: portainer
rules:
  - apiGroups: [""]
    resources: ["*"]
    verbs: ["*"]
  - apiGroups: ["apps"]
    resources: ["*"]
    verbs: ["*"]
  - apiGroups: ["batch"]
    resources: ["*"]
    verbs: ["*"]
  - apiGroups: ["extensions"]
    resources: ["*"]
    verbs: ["*"]
  - apiGroups: ["networking.k8s.io"]
    resources: ["*"]
    verbs: ["*"]
  - apiGroups: ["storage.k8s.io"]
    resources: ["*"]
    verbs: ["*"]
  - apiGroups: ["rbac.authorization.k8s.io"]
    resources: ["*"]
    verbs: ["*"]
  - apiGroups: ["metrics.k8s.io"]
    resources: ["*"]
    verbs: ["*"]
  - apiGroups: ["apiextensions.k8s.io"]
    resources: ["*"]
    verbs: ["*"]
  - apiGroups: ["policy"]
    resources: ["*"]
    verbs: ["*"]
  - apiGroups: ["autoscaling"]
    resources: ["*"]
    verbs: ["*"]
  - apiGroups: ["coordination.k8s.io"]
    resources: ["*"]
    verbs: ["*"]
EOF

# Создаем ClusterRoleBinding
echo "Создание ClusterRoleBinding..."
kubectl apply -f - <<EOF
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: portainer-cluster-admin
  labels:
    app.kubernetes.io/name: portainer
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: portainer-cluster-admin
subjects:
  - kind: ServiceAccount
    name: portainer-sa-clusteradmin
    namespace: management
EOF

echo ""
echo "=== Проверка после исправления ==="
kubectl auth can-i list namespaces --as=system:serviceaccount:management:portainer-sa-clusteradmin
kubectl auth can-i list pods --all-namespaces --as=system:serviceaccount:management:portainer-sa-clusteradmin

echo ""
echo "=== Перезапуск Portainer ==="
kubectl rollout restart deployment portainer -n management
echo "Ожидание перезапуска..."
sleep 5
kubectl get pods -n management -l app.kubernetes.io/name=portainer

echo ""
echo "✅ Готово! Проверьте Portainer через несколько секунд."
