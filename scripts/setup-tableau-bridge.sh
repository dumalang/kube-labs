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

echo "📋 3. Applying Kubernetes manifests..."
kubectl apply -f k8s/08-tableau-bridge-ha.yaml

echo "🔄 4. Restarting deployment to pick up loaded image..."
kubectl rollout restart deployment/tableau-bridge

echo ""
echo "=================================================="
echo "✅ Setup Submitted! Checking Pod status..."
echo "=================================================="
kubectl get pods -l app=tableau-bridge -o wide
