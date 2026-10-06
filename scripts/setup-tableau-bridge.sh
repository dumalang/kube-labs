#!/usr/bin/env bash
set -e

CLUSTER_NAME="k8s-microservices-lab"
export KIND_EXPERIMENTAL_PROVIDER=podman

echo "=================================================="
echo "🚀 Tableau Bridge HA Setup for Kubernetes (Podman + Kind)"
echo "=================================================="

BUILD_DIR="tableau-bridge"
RPM_FILE=$(ls ${BUILD_DIR}/TableauBridge-*.x86_64.rpm 2>/dev/null | head -n 1 || true)

if [ -z "$RPM_FILE" ]; then
  echo "⚠️  [WARNING] File RPM Tableau Bridge (TableauBridge-*.x86_64.rpm) tidak ditemukan di direktori '${BUILD_DIR}/'."
  echo " Silakan unduh Tableau Bridge RPM for Linux dari Tableau Support Downloads:"
  echo " 👉 https://www.tableau.com/support/downloads/bridge"
  echo " Letakkan file RPM tersebut di folder: ${BUILD_DIR}/"
  echo ""
  echo "Contoh file yang diharapkan: ${BUILD_DIR}/TableauBridge-2024.1.0-x86_64.rpm"
  exit 1
fi

RPM_BASENAME=$(basename "$RPM_FILE")

echo "🛠️  1. Building Tableau Bridge container image (linux/amd64) with Podman..."
echo "    Menggunakan RPM: ${RPM_BASENAME}"

podman build \
  --platform linux/amd64 \
  --build-arg TABLEAU_BRIDGE_RPM="${RPM_BASENAME}" \
  -t localhost/tableau-bridge:latest \
  -f ${BUILD_DIR}/Dockerfile \
  ${BUILD_DIR}

echo "📥 2. Loading image 'localhost/tableau-bridge:latest' into Kind cluster '${CLUSTER_NAME}'..."
TAR_PATH="/tmp/tableau-bridge.tar"
podman save "localhost/tableau-bridge:latest" -o "${TAR_PATH}"
kind load image-archive "${TAR_PATH}" --name "${CLUSTER_NAME}"
rm -f "${TAR_PATH}"

echo "🔐 3. Configuring Kubernetes ConfigMap & Secret from .env.tableau..."
ENV_FILE=".env.tableau"
if [ -f "${ENV_FILE}" ]; then
  echo "    Loading configuration and credentials from '${ENV_FILE}'..."
  # Source .env.tableau
  set -a
  source "${ENV_FILE}"
  set +a

  # 1. ConfigMap (non-sensitive parameters)
  echo "    Creating/updating ConfigMap 'tableau-bridge-config'..."
  kubectl create configmap tableau-bridge-config \
    --from-literal=TABLEAU_SERVER_URL="${TABLEAU_SERVER_URL}" \
    --from-literal=TABLEAU_SITE_NAME="${TABLEAU_SITE_NAME}" \
    --from-literal=TABLEAU_USER_EMAIL="${TABLEAU_USER_EMAIL:-admin@example.com}" \
    --from-literal=POOL_ID="${POOL_ID}" \
    --from-literal=CLIENT_NAME_PREFIX="${CLIENT_NAME_PREFIX:-k8s-local-mac}" \
    --from-literal=MYSQL_HOST="${MYSQL_HOST:-mysql-podman-service}" \
    --from-literal=MYSQL_PORT="${MYSQL_PORT:-3306}" \
    --dry-run=client -o yaml | kubectl apply -f -

  # 2. Secret (sensitive PAT authentication)
  echo "    Creating/updating Secret 'tableau-bridge-secret'..."
  kubectl create secret generic tableau-bridge-secret \
    --from-literal=PAT_NAME="${PAT_NAME}" \
    --from-literal=PAT_SECRET="${PAT_SECRET}" \
    --dry-run=client -o yaml | kubectl apply -f -

  # 3. Dynamic Endpoints for MySQL Podman IP
  if [ -n "${MYSQL_PODMAN_IP}" ]; then
    echo "    Configuring MySQL Podman Endpoints with IP: ${MYSQL_PODMAN_IP}..."
    cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Endpoints
metadata:
  name: mysql-podman-service
  labels:
    app: tableau-bridge
subsets:
  - addresses:
      - ip: "${MYSQL_PODMAN_IP}"
    ports:
      - name: mysql
        port: ${MYSQL_PORT:-3306}
EOF
  fi
elif kubectl get configmap tableau-bridge-config >/dev/null 2>&1 && kubectl get secret tableau-bridge-secret >/dev/null 2>&1; then
  echo "    Menggunakan 'tableau-bridge-config' dan 'tableau-bridge-secret' yang sudah ada di cluster."
else
  echo "⚠️  [ERROR] File '${ENV_FILE}' tidak ditemukan dan konfigurasi belum ada di cluster!"
  echo " Silakan buat file '${ENV_FILE}' dari template:"
  echo "   cp .env.tableau.example .env.tableau"
  echo " Lalu lengkapi variabel Tableau Cloud dan kredensial PAT Anda."
  exit 1
fi

echo "📋 4. Applying Kubernetes manifests..."
kubectl apply -f k8s/08-tableau-bridge-ha.yaml

echo "🔄 5. Restarting deployment to pick up updated configuration and image..."
kubectl rollout restart deployment/tableau-bridge

echo ""
echo "=================================================="
echo "✅ Setup Submitted! Checking Pod status..."
echo "=================================================="
kubectl get pods -l app=tableau-bridge -o wide
