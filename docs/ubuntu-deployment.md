# Развертывание на чистом Ubuntu сервере

Полная инструкция по развертыванию системы мониторинга на чистом Ubuntu сервере с нуля.

## Обзор

Эта инструкция поможет вам развернуть систему мониторинга на Ubuntu сервере, начиная с установки всех необходимых компонентов.

**Время развертывания**: ~30-60 минут

## Предварительные требования

- Ubuntu Server 20.04 LTS или выше
- Минимум 4 CPU ядра
- Минимум 8GB RAM
- Минимум 50GB свободного места на диске
- Root доступ или пользователь с sudo правами
- Статический IP адрес (рекомендуется)
- Доменное имя (для Ingress с TLS)

## Шаг 1: Подготовка сервера

### 1.1. Создание пользователя (если работаете от root)

Если вы вошли на сервер как root, рекомендуется создать отдельного пользователя:

```bash
# Создание пользователя
sudo adduser deploy
# Укажите пароль и заполните информацию (можно пропустить, нажав Enter)

# Добавление пользователя в группу sudo
sudo usermod -aG sudo deploy

# Переключение на нового пользователя
su - deploy

# Проверка прав
sudo whoami  # Должно вывести: root
```

### 1.2. Генерация SSH ключа для Git

```bash
# Генерация SSH ключа
ssh-keygen -t ed25519 -C "your_email@example.com" -f ~/.ssh/id_ed25519_deploy

# Или используйте RSA (если ed25519 не поддерживается)
# ssh-keygen -t rsa -b 4096 -C "your_email@example.com" -f ~/.ssh/id_rsa

# Настройка прав доступа
chmod 600 ~/.ssh/id_ed25519_deploy
chmod 644 ~/.ssh/id_ed25519_deploy.pub

# Добавление ключа в ssh-agent
eval "$(ssh-agent -s)" && ssh-add ~/.ssh/id_ed25519_deploy

# Вывод публичного ключа (скопируйте его)
cat ~/.ssh/id_ed25519_deploy.pub
```

**Добавление SSH ключа в Git (GitHub/GitLab/Bitbucket):**

1. **GitHub:**
   - Перейдите в Settings → SSH and GPG keys
   - Нажмите "New SSH key"
   - Вставьте содержимое `~/.ssh/id_ed25519.pub`
   - Сохраните

2. **GitLab:**
   - Перейдите в Settings → SSH Keys
   - Вставьте содержимое `~/.ssh/id_ed25519.pub`
   - Сохраните

3. **Bitbucket:**
   - Перейдите в Personal settings → SSH keys
   - Нажмите "Add key"
   - Вставьте содержимое `~/.ssh/id_ed25519.pub`
   - Сохраните

**Проверка подключения:**

```bash
# Для GitHub
ssh -T git@github.com

# Для GitLab
ssh -T git@gitlab.com

# Для Bitbucket
ssh -T git@bitbucket.org
```

Должно вывести сообщение об успешной аутентификации.

### 1.3. Настройка Git

```bash
# Настройка имени и email
git config --global user.name "Your Name"
git config --global user.email "your_email@example.com"

# Настройка редактора по умолчанию
git config --global core.editor vim

# Настройка автодополнения (опционально)
git config --global init.defaultBranch main

# Проверка настроек
git config --list
```

### 1.4. Обновление системы

```bash
sudo apt update
sudo apt upgrade -y
sudo apt install -y curl wget git vim
```

### 1.5. Настройка hostname (опционально)

Настройка hostname помогает идентифицировать сервер в сети и упрощает администрирование.
Особенно полезно при работе с несколькими серверами или в Kubernetes кластере.

**Зачем это нужно:**
- Идентификация сервера в логах и мониторинге
- Удобство при работе с несколькими серверами
- Корректная работа Kubernetes (идентификация нод)
- Правильная работа некоторых сетевых сервисов

# Установите hostname
sudo hostnamectl set-hostname monitoring-server

# Добавьте в /etc/hosts (для локального разрешения)
```bash
echo "127.0.0.1 monitoring-server" | sudo tee -a /etc/hosts**Проверка:**
hostname  # Должно вывести: monitoring-server
hostnamectl  # Покажет полную информацию
```

### 1.6. Настройка firewall (если включен)

```bash
# Разрешить необходимые порты
sudo ufw allow 22/tcp    # SSH
sudo ufw allow 80/tcp    # HTTP (для Let's Encrypt)
sudo ufw allow 443/tcp   # HTTPS
sudo ufw allow 6443/tcp  # Kubernetes API (если используете внешний доступ)
sudo ufw enable
```

## Шаг 2: Установка Kubernetes

Для развертывания на одном сервере рекомендуется использовать **k3s** (легковесный Kubernetes).

### 2.1. Установка k3s

```bash
# Установка k3s
curl -sfL https://get.k3s.io | sh -

# Проверка установки
sudo k3s kubectl get nodes
```

### 2.2. Настройка доступа к k3s

```bash
# Создайте директорию для kubeconfig
mkdir -p ~/.kube

# Скопируйте kubeconfig
sudo cp /etc/rancher/k3s/k3s.yaml ~/.kube/config
sudo chown $USER:$USER ~/.kube/config

# Установите правильный сервер (замените localhost на IP сервера, если нужно)
sed -i 's/127.0.0.1/your-server-ip/g' ~/.kube/config

# Проверка подключения
kubectl get nodes
```

**Альтернатива: kubeadm (Пропустите этот раздел, если используете k3s!)**

Если нужен полноценный Kubernetes кластер:

```bash
# Установка kubeadm, kubelet, kubectl
sudo apt-get update
sudo apt-get install -y apt-transport-https ca-certificates curl

curl -fsSL https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-archive-keyring.gpg

echo "deb [signed-by=/etc/apt/keyrings/kubernetes-archive-keyring.gpg] https://apt.kubernetes.io/ kubernetes-xenial main" | sudo tee /etc/apt/sources.list.d/kubernetes.list

sudo apt-get update
sudo apt-get install -y kubelet kubeadm kubectl
sudo apt-mark hold kubelet kubeadm kubectl

# Инициализация кластера (только на master ноде)
sudo kubeadm init --pod-network-cidr=10.244.0.0/16

# Настройка доступа
mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config

# Установка сетевого плагина (Flannel)
kubectl apply -f https://github.com/flannel-io/flannel/releases/latest/download/kube-flannel.yml
```

## Шаг 3: Установка kubectl

Если kubectl не установлен (для k3s он уже включен):

```bash
# Скачивание kubectl
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"

# Установка
sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl

# Проверка
kubectl version --client
```

## Шаг 4: Установка Helm

```bash
# Установка Helm
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# Проверка
helm version
```

## Шаг 5: Установка StorageClass (для PersistentVolumes)

### 5.1. Для k3s

k3s включает встроенный local-path-provisioner, но для production multi-node рекомендуется использовать NFS или другой сетевой storage.

**Установка local-path-provisioner (уже включен в k3s):**

```bash
# Проверка существующего StorageClass
kubectl get storageclass

# Если нужно создать новый
kubectl apply -f https://raw.githubusercontent.com/rancher/local-path-provisioner/v0.0.24/deploy/local-path-storage.yaml
```

**Установка NFS StorageClass (рекомендуется для production):**

```bash
# Установка NFS client (если используете NFS сервер)
sudo apt install -y nfs-common

# Установка NFS provisioner
helm repo add nfs-subdir-external-provisioner https://kubernetes-sigs.github.io/nfs-subdir-external-provisioner/
helm install nfs-subdir-external-provisioner nfs-subdir-external-provisioner/nfs-subdir-external-provisioner \
  --set nfs.server=your-nfs-server-ip \
  --set nfs.path=/path/to/nfs/share \
  --set storageClass.defaultClass=true
```

### 5.2. Для kubeadm

```bash
# Установка NFS provisioner (пример)
helm repo add nfs-subdir-external-provisioner https://kubernetes-sigs.github.io/nfs-subdir-external-provisioner/
helm install nfs-subdir-external-provisioner nfs-subdir-external-provisioner/nfs-subdir-external-provisioner \
  --set nfs.server=your-nfs-server-ip \
  --set nfs.path=/path/to/nfs/share \
  --set storageClass.defaultClass=true
```

**Проверка StorageClass:**

```bash
kubectl get storageclass
# Должен быть хотя бы один StorageClass с default=true
```

## Шаг 6: Установка Ingress Controller (опционально)

Если планируете использовать Ingress (`ENABLE_INGRESS=true`):

## Шаг 6: Установка Ingress Controller (опционально)

Если планируете использовать Ingress (`ENABLE_INGRESS=true`):

### 6.1. Для k3s: Использование встроенного Traefik (рекомендуется)

**k3s включает Traefik Ingress Controller по умолчанию**, поэтому дополнительная установка не требуется.

**Проверка, что Traefik работает:**
```bash
# Проверка сервиса Traefik
kubectl get svc -n kube-system | grep traefik

# Проверка подов Traefik
kubectl get pods -n kube-system | grep traefik

# Проверка IngressClass
kubectl get ingressclass
# Должен быть traefik**Настройка для использования Traefik:**

При установке мониторинга установите класс Ingress как `traefik`:

export INGRESS_CLASS=traefik**Преимущества использования Traefik в k3s:**
- ✅ Уже установлен и настроен
- ✅ Не требует дополнительных ресурсов
- ✅ Проще в управлении
- ✅ Автоматически обновляется с k3s

**Если Traefik не работает или нужно отключить:**

# Отключение Traefik (если нужно)
# Отредактируйте /etc/rancher/k3s/config.yaml
sudo nano /etc/rancher/k3s/config.yaml

# Добавьте:
# disable:
#   - traefik

# Перезапустите k3s
sudo systemctl restart k3sПосле отключения Traefik используйте NGINX (см. раздел ниже).
```

---

### 6.2. Установка NGINX Ingress Controller (альтернатива)

**Когда использовать NGINX:**
- Traefik отключен в k3s
- Нужны специфичные функции NGINX
- Используете kubeadm (нет встроенного Ingress Controller)
- Предпочитаете NGINX по опыту

**Установка NGINX Ingress Controller:**

# Добавление Helm репозитория

```bash
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo update

# Установка NGINX Ingress Controller
helm install ingress-nginx ingress-nginx/ingress-nginx \
  --namespace ingress-nginx \
  --create-namespace \
  --set controller.service.type=LoadBalancer \
  --set controller.service.externalIPs[0]=your-server-ip

# Ожидание готовности
kubectl wait --namespace ingress-nginx \
  --for=condition=ready pod \
  --selector=app.kubernetes.io/component=controller \
  --timeout=300s

# Проверка
kubectl get svc -n ingress-nginx
**Настройка для использования NGINX:**

При установке мониторинга установите класс Ingress как `nginx`:

export INGRESS_CLASS=nginx**Проверка IngressClass:**
h
kubectl get ingressclass

# Должен быть nginx (или traefik, если используете Traefik)
```

## Шаг 7: Установка cert-manager (опционально)

Если планируете использовать Ingress с TLS сертификатами:

```bash
# Добавление Helm репозитория
helm repo add jetstack https://charts.jetstack.io
helm repo update

# Проверка, не установлен ли cert-manager уже
helm list -n cert-manager
kubectl get pods -n cert-manager 2>/dev/null || echo "Namespace не существует"

# Установка cert-manager
helm install cert-manager jetstack/cert-manager \
  --namespace cert-manager \
  --create-namespace \
  --set installCRDs=true \
  --set global.leaderElection.namespace=cert-manager
```

**Если получили ошибку "exists and cannot be imported":**

Эта ошибка означает, что в кластере уже есть ресурсы cert-manager, не созданные Helm. Решение:

```bash
# Вариант 1: Полная очистка и переустановка (рекомендуется)
# 1. Удаление Helm release (если существует)
helm uninstall cert-manager -n cert-manager 2>/dev/null || true

# 2. Удаление namespace
kubectl delete namespace cert-manager 2>/dev/null || true

# 3. Удаление CRD (CustomResourceDefinition) - они существуют на уровне кластера
kubectl delete crd -l app.kubernetes.io/name=cert-manager 2>/dev/null || true

# Или удалите все CRD cert-manager вручную:
kubectl delete crd certificates.cert-manager.io \
  certificaterequests.cert-manager.io \
  challenges.acme.cert-manager.io \
  clusterissuers.cert-manager.io \
  issuers.cert-manager.io \
  orders.acme.cert-manager.io 2>/dev/null || true

# 4. Удаление ClusterRole и ClusterRoleBinding (ресурсы уровня кластера)
kubectl delete clusterrole,clusterrolebinding -l app.kubernetes.io/name=cert-manager 2>/dev/null || true

# Или удалите вручную все ресурсы cert-manager на уровне кластера:
kubectl delete clusterrole cert-manager-cainjector \
  cert-manager-controller \
  cert-manager-webhook:subjectaccessreviews 2>/dev/null || true

kubectl delete clusterrolebinding cert-manager-cainjector \
  cert-manager-controller \
  cert-manager-webhook:subjectaccessreviews 2>/dev/null || true

# 5. Удаление ServiceAccount из всех namespace (если остались)
kubectl delete serviceaccount -l app.kubernetes.io/name=cert-manager --all-namespaces 2>/dev/null || true

# 6. Удаление WebhookConfiguration (MutatingWebhookConfiguration и ValidatingWebhookConfiguration)
kubectl delete mutatingwebhookconfiguration,validatingwebhookconfiguration -l app.kubernetes.io/name=cert-manager 2>/dev/null || true

# Или удалите вручную:
kubectl delete mutatingwebhookconfiguration cert-manager-webhook 2>/dev/null || true
kubectl delete validatingwebhookconfiguration cert-manager-webhook 2>/dev/null || true

# 7. Подождите несколько секунд
sleep 5

# 8. Установка заново
helm install cert-manager jetstack/cert-manager \
  --namespace cert-manager \
  --create-namespace \
  --set installCRDs=true \
  --set global.leaderElection.namespace=cert-manager

# Вариант 2: Если cert-manager уже установлен через Helm, используйте upgrade
# helm upgrade cert-manager jetstack/cert-manager \
#   --namespace cert-manager \
#   --set installCRDs=true \
#   --set global.leaderElection.namespace=cert-manager
```

**Важно**:
- CRD (CustomResourceDefinition), ClusterRole, ClusterRoleBinding, MutatingWebhookConfiguration, ValidatingWebhookConfiguration существуют на уровне кластера, а не namespace
- Они не удаляются при удалении namespace, их нужно удалять отдельно
- Если ошибка повторяется, проверьте все ресурсы: `kubectl get all,clusterrole,clusterrolebinding,crd,mutatingwebhookconfiguration,validatingwebhookconfiguration -l app.kubernetes.io/name=cert-manager -A`

**Ожидание готовности:**

```bash
kubectl wait --namespace cert-manager \
  --for=condition=ready pod \
  --selector=app.kubernetes.io/instance=cert-manager \
  --timeout=300s

# Проверка
kubectl get pods -n cert-manager
```

### 7.1. Создание ClusterIssuer

```bash
# Клонируйте репозиторий мониторинга (если еще не сделали)
cd ~
git clone <repository-url>
cd monitoring

# Отредактируйте манифест ClusterIssuer
nano base/cert-manager-issuer.yaml

# Замените:
# - email: admin@example.com → ваш email
# - class: nginx → ваш Ingress Controller класс

# Примените
kubectl apply -f base/cert-manager-issuer.yaml

# Проверка
kubectl get clusterissuer
```

## Шаг 8: Клонирование репозитория мониторинга

```bash
cd ~

# Клонирование через SSH (рекомендуется)
git clone git@github.com:your-username/monitoring.git
# или
git clone git@gitlab.com:your-username/monitoring.git

# Или через HTTPS (если SSH не настроен)
# git clone https://github.com/your-username/monitoring.git

cd monitoring

# Проверка подключения к удаленному репозиторию
git remote -v

# Если нужно обновить репозиторий
git pull origin main  # или master, в зависимости от вашей ветки
```

## Шаг 9: Установка стека мониторинга

### 9.1. Настройка параметров

**Вариант 1: Использование .env файла (рекомендуется)**

Создайте файл `.env` в корне репозитория:

```bash
cd ~/monitoring

# Используйте готовый пример (если есть)
cp .env.example .env

# Или создайте .env файл вручную
cat > .env << 'EOF'
# Обязательные параметры
DOMAIN=example.com
GRAFANA_PASSWORD=secure_password

# Опциональные параметры
MONITORING_NAMESPACE=monitoring
PROMETHEUS_RETENTION=15d
PROMETHEUS_STORAGE=20Gi
LOKI_RETENTION=744h
LOKI_STORAGE=20Gi
INSTALL_PORTAINER=false

# Для Ingress (если настроили)
ENABLE_INGRESS=true
INGRESS_CLASS=nginx  # Или traefik для k3s
ACME_EMAIL=admin@example.com  # Email для Let's Encrypt (опционально, по умолчанию: admin@${DOMAIN})

HELM_WAIT=true
EOF

# Отредактируйте .env файл со своими значениями
nano .env

# Защита файла (содержит пароли!)
chmod 600 .env

# Загрузка переменных из .env перед запуском скрипта
set -a
source .env
set +a
```

**Вариант 2: Экспорт переменных вручную**

```bash
# Обязательные параметры
export DOMAIN=example.com                    # Ваш домен
export GRAFANA_PASSWORD=secure_password     # Сильный пароль!

# Опциональные параметры
export MONITORING_NAMESPACE=monitoring
export PROMETHEUS_RETENTION=15d
export PROMETHEUS_STORAGE=20Gi
export LOKI_RETENTION=744h
export LOKI_STORAGE=20Gi
export INSTALL_PORTAINER=false

# Для Ingress (если настроили)
export ENABLE_INGRESS=true
export INGRESS_CLASS=nginx  # Или traefik для k3s
export ACME_EMAIL=admin@example.com  # Email для Let's Encrypt (опционально, по умолчанию: admin@${DOMAIN})
export HELM_WAIT=true
```

**Рекомендация**: Используйте `.env` файл для удобства управления конфигурацией. Не забудьте добавить `.env` в `.gitignore`, чтобы не коммитить пароли!

### 9.2. Запуск установки

```bash
# Сделайте скрипт исполняемым
chmod +x scripts/setup.sh

# Если используете .env файл, загрузите переменные:
set -a
source .env
set +a

# Запуск установки
./scripts/setup.sh
```

**Примечание**: Если вы использовали `export` для переменных, просто запустите `./scripts/setup.sh` без загрузки .env.

### 9.3. Проверка установки

```bash
# Проверка подов
kubectl get pods -n monitoring

# Проверка сервисов
kubectl get svc -n monitoring

# Проверка Ingress (если включен)
kubectl get ingress -n monitoring
```

## Шаг 10: Настройка DNS (для Ingress)

Если используете Ingress, настройте DNS записи:

```bash
# Получите IP адрес Ingress Controller
kubectl get svc -n ingress-nginx  # Для NGINX
# или
kubectl get svc -n kube-system | grep traefik  # Для k3s Traefik
```

**Добавьте DNS записи:**

```
*.example.com  A  <IP_INGRESS_CONTROLLER>
```

Или отдельные записи:

```
grafana.example.com    A  <IP_INGRESS_CONTROLLER>
prometheus.example.com A  <IP_INGRESS_CONTROLLER>
portainer.example.com  A  <IP_INGRESS_CONTROLLER>
```

## Шаг 11: Первый вход в Grafana

### 11.1. Через Ingress (если настроен)

```bash
# Откройте в браузере
https://grafana.example.com
```

### 11.2. Через port-forward (для тестирования)

```bash
# Port-forward для Grafana
kubectl port-forward -n monitoring svc/kube-prometheus-stack-grafana 3000:80

# Откройте в браузере
http://localhost:3000
```

**Учетные данные:**
- Username: `admin`
- Password: значение `GRAFANA_PASSWORD` (или `admin` по умолчанию)

**ВАЖНО**: Измените пароль при первом входе!

## Проверка работоспособности

### Проверка Prometheus

```bash
# Port-forward
kubectl port-forward -n monitoring svc/prometheus-kube-prometheus-prometheus 9090:9090

# Откройте в браузере
http://localhost:9090
```

### Проверка Loki

```bash
# Port-forward
kubectl port-forward -n monitoring svc/loki 3100:3100

# Проверка через curl
curl http://localhost:3100/ready
```

### Проверка метрик

В Grafana:
1. Откройте Explore
2. Выберите datasource "Prometheus"
3. Выполните запрос: `up`

Должны быть видны метрики из всех namespace.

## Troubleshooting

### Проблема: Поды не запускаются

```bash
# Проверка событий
kubectl get events -n monitoring --sort-by='.lastTimestamp'

# Проверка логов пода
kubectl logs -n monitoring <pod-name>

# Проверка описания пода
kubectl describe pod -n monitoring <pod-name>
```

### Проблема: PersistentVolume не создается

```bash
# Проверка StorageClass
kubectl get storageclass

# Проверка PVC
kubectl get pvc -n monitoring

# Проверка PV
kubectl get pv
```

### Проблема: Ingress не работает

```bash
# Проверка Ingress Controller
kubectl get pods -n ingress-nginx  # Для NGINX
kubectl get pods -n kube-system | grep traefik  # Для k3s

# Проверка Ingress
kubectl describe ingress -n monitoring <ingress-name>

# Проверка логов Ingress Controller
kubectl logs -n ingress-nginx <ingress-controller-pod>
```

### Проблема: Ошибка при установке cert-manager

**Проблема 1**: `Error: INSTALLATION FAILED: Unable to continue with install: ServiceAccount "cert-manager-cainjector" in namespace "cert-manager" exists and cannot be imported`

**Проблема 2**: `Error: INSTALLATION FAILED: Unable to continue with install: CustomResourceDefinition "challenges.acme.cert-manager.io" in namespace "" exists and cannot be imported`

**Проблема 3**: `Error: INSTALLATION FAILED: Unable to continue with install: ClusterRole "cert-manager-cainjector" in namespace "" exists and cannot be imported`

**Проблема 4**: `Error: INSTALLATION FAILED: Unable to continue with install: MutatingWebhookConfiguration "cert-manager-webhook" in namespace "" exists and cannot be imported`

**Решение**:
Это означает, что в кластере уже есть ресурсы cert-manager, не созданные Helm. Выполните полную очистку:

```bash
# 1. Удаление Helm release (если существует)
helm uninstall cert-manager -n cert-manager 2>/dev/null || true

# 2. Удаление namespace
kubectl delete namespace cert-manager 2>/dev/null || true

# 3. Удаление CRD (CustomResourceDefinition) - они существуют на уровне кластера
kubectl delete crd -l app.kubernetes.io/name=cert-manager 2>/dev/null || true

# Или удалите все CRD cert-manager вручную:
kubectl delete crd certificates.cert-manager.io \
  certificaterequests.cert-manager.io \
  challenges.acme.cert-manager.io \
  clusterissuers.cert-manager.io \
  issuers.cert-manager.io \
  orders.acme.cert-manager.io 2>/dev/null || true

# 4. Удаление ClusterRole и ClusterRoleBinding (ресурсы уровня кластера)
kubectl delete clusterrole,clusterrolebinding -l app.kubernetes.io/name=cert-manager 2>/dev/null || true

# Или удалите вручную все ресурсы cert-manager на уровне кластера:
kubectl delete clusterrole cert-manager-cainjector \
  cert-manager-controller \
  cert-manager-webhook:subjectaccessreviews 2>/dev/null || true

kubectl delete clusterrolebinding cert-manager-cainjector \
  cert-manager-controller \
  cert-manager-webhook:subjectaccessreviews 2>/dev/null || true

# 5. Удаление ServiceAccount из всех namespace (если остались)
kubectl delete serviceaccount -l app.kubernetes.io/name=cert-manager --all-namespaces 2>/dev/null || true

# 6. Удаление WebhookConfiguration (MutatingWebhookConfiguration и ValidatingWebhookConfiguration)
kubectl delete mutatingwebhookconfiguration,validatingwebhookconfiguration -l app.kubernetes.io/name=cert-manager 2>/dev/null || true

# Или удалите вручную:
kubectl delete mutatingwebhookconfiguration cert-manager-webhook 2>/dev/null || true
kubectl delete validatingwebhookconfiguration cert-manager-webhook 2>/dev/null || true

# 7. Проверка всех оставшихся ресурсов (опционально)
# kubectl get all,clusterrole,clusterrolebinding,crd,mutatingwebhookconfiguration,validatingwebhookconfiguration -l app.kubernetes.io/name=cert-manager -A

# 8. Подождите несколько секунд
sleep 5

# 9. Установка заново
helm install cert-manager jetstack/cert-manager \
  --namespace cert-manager \
  --create-namespace \
  --set installCRDs=true \
  --set global.leaderElection.namespace=cert-manager
```

**Важно**:
- CRD (CustomResourceDefinition), ClusterRole, ClusterRoleBinding, MutatingWebhookConfiguration, ValidatingWebhookConfiguration существуют на уровне кластера, а не namespace
- Они не удаляются при удалении namespace, их нужно удалять отдельно
- Если ошибка повторяется, проверьте все ресурсы: `kubectl get all,clusterrole,clusterrolebinding,crd,mutatingwebhookconfiguration,validatingwebhookconfiguration -l app.kubernetes.io/name=cert-manager -A`

### Проблема: Сертификаты не выдаются

**Проблема**: Certificate в статусе `Pending` или `Failed`

**Решение**:
1. Проверьте cert-manager:
   ```bash
   kubectl get pods -n cert-manager
   # Все поды должны быть Running
   ```

   Если поды не запускаются, см. решение выше.

2. Проверьте ClusterIssuer:
   ```bash
   kubectl get clusterissuer
   kubectl describe clusterissuer letsencrypt-prod
   # Статус должен быть Ready
   ```

3. Проверьте события:
   ```bash
   kubectl describe certificate -n monitoring <cert-name>
   kubectl get events -n monitoring --sort-by='.lastTimestamp'
   kubectl logs -n cert-manager -l app=cert-manager
   ```

4. Проверьте Challenge ресурсы:
   ```bash
   kubectl get challenges -n monitoring
   kubectl describe challenge -n monitoring <challenge-name>
   ```

## Оптимизация для production

### 1. Настройка ресурсов

Отредактируйте `values/prometheus-values.yaml` и `values/loki-values.yaml` для настройки ресурсов:

```yaml
resources:
  requests:
    cpu: 500m
    memory: 1Gi
  limits:
    cpu: 2000m
    memory: 4Gi
```

### 2. Настройка retention

```bash
export PROMETHEUS_RETENTION=30d  # Увеличьте для production
export LOKI_RETENTION=1680h      # 70 дней
```

### 3. Настройка storage

```bash
export PROMETHEUS_STORAGE=100Gi  # Увеличьте для production
export LOKI_STORAGE=100Gi
```

### 4. Резервное копирование

Настройте регулярное резервное копирование PersistentVolumes:

```bash
# Пример скрипта бэкапа
#!/bin/bash
kubectl exec -n monitoring prometheus-kube-prometheus-prometheus-0 -- tar czf - /prometheus | \
  gzip > prometheus-backup-$(date +%Y%m%d).tar.gz
```

## Дополнительные ресурсы

- [Официальная документация k3s](https://k3s.io/)
- [Документация Kubernetes](https://kubernetes.io/docs/)
- [Документация Helm](https://helm.sh/docs/)
- [Документация cert-manager](https://cert-manager.io/docs/)

## Чеклист развертывания

- [ ] Пользователь создан и настроен (если работали от root)
- [ ] SSH ключ для Git сгенерирован
- [ ] SSH ключ добавлен в Git сервис (GitHub/GitLab/Bitbucket)
- [ ] Git настроен (имя, email)
- [ ] Подключение к Git через SSH проверено
- [ ] Ubuntu сервер обновлен
- [ ] Kubernetes установлен (k3s или kubeadm)
- [ ] kubectl настроен и работает
- [ ] Helm установлен
- [ ] StorageClass настроен
- [ ] Ingress Controller установлен (если нужен)
- [ ] cert-manager установлен (если нужен)
- [ ] ClusterIssuer создан (если нужен)
- [ ] Репозиторий мониторинга склонирован через SSH
- [ ] Параметры установки настроены
- [ ] Стек мониторинга установлен (`./scripts/setup.sh`)
- [ ] Все поды в статусе Running
- [ ] DNS записи настроены (если используете Ingress)
- [ ] Grafana доступна и пароль изменен
- [ ] Prometheus собирает метрики
- [ ] Loki собирает логи

---

**Готово!** Система мониторинга развернута и готова к использованию.
