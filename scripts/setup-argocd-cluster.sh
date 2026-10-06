#!/usr/bin/env bash
set -e

CLUSTER_NAME="k8s-argocd-lab"
export KIND_EXPERIMENTAL_PROVIDER=podman

echo "=========================================================="
echo "🐙 Argo CD GitOps Cluster Setup (Podman + Kind)"
echo "   Cluster Pembanding: ${CLUSTER_NAME}"
echo "=========================================================="

# 1. Buat Kind cluster jika belum ada
if kind get clusters 2>/dev/null | grep -q "^${CLUSTER_NAME}$"; then
  echo "ℹ️  Cluster '${CLUSTER_NAME}' sudah ada. Menggunakan cluster yang sudah ada..."
else
  echo "📦 Membuat Kind cluster '${CLUSTER_NAME}' menggunakan Podman..."
  kind create cluster --config argocd/kind-argocd-config.yaml
fi

# Pastikan konteks kubectl aktif ke cluster baru
kubectl config use-context "kind-${CLUSTER_NAME}"

# 2. Build service images dengan Podman jika belum ada
echo "🛠️  Memeriksa / membangun container image microservices..."

buildImageIfNeeded() {
  local img_name=$1
  local context_dir=$2
  if podman image exists "${img_name}:latest"; then
    echo "  ✅ Image '${img_name}:latest' sudah tersedia di Podman."
  else
    echo "  🔨 Membangun '${img_name}:latest'..."
    podman build -t "${img_name}:latest" -f "${context_dir}/Containerfile" "${context_dir}"
  fi
}

buildImageIfNeeded "service-a-nodejs" "service-a-nodejs"
buildImageIfNeeded "service-b-golang" "service-b-golang"
buildImageIfNeeded "service-c-java" "service-c-java"

# 3. Load images ke dalam Kind cluster
echo "📥 Loading images ke dalam Kind cluster '${CLUSTER_NAME}'..."
loadImage() {
  local img_name=$1
  local tar_path="/tmp/${img_name}-argocd.tar"
  echo " -> Loading ${img_name}:latest..."
  podman save "${img_name}:latest" -o "${tar_path}"
  kind load image-archive "${tar_path}" --name "${CLUSTER_NAME}"
  rm -f "${tar_path}"
}

loadImage "service-a-nodejs"
loadImage "service-b-golang"
loadImage "service-c-java"

# Load tableau-bridge jika di-request dan ada (karena image ~3.2GB memerlukan ruang disk besar)
if [ "${LOAD_TABLEAU:-false}" = "true" ] && podman image exists "localhost/tableau-bridge:latest"; then
  echo " -> Loading localhost/tableau-bridge:latest (LOAD_TABLEAU=true)..."
  TAR_PATH="/tmp/tableau-bridge-argocd.tar"
  if podman save "localhost/tableau-bridge:latest" -o "${TAR_PATH}"; then
    kind load image-archive "${TAR_PATH}" --name "${CLUSTER_NAME}" || echo "⚠️  Gagal memuat tableau-bridge ke kind (kapasitas disk)"
    rm -f "${TAR_PATH}"
  fi
fi

# 4. Install NGINX Ingress Controller untuk Kind
echo "🌐 Menginstal NGINX Ingress Controller..."
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/kind/deploy.yaml

echo "⏳ Menunggu NGINX Ingress Controller ready..."
kubectl wait --namespace ingress-nginx \
  --for=condition=ready pod \
  --selector=app.kubernetes.io/component=controller \
  --timeout=180s || echo "⚠️  Ingress deployment memakan waktu lebih lama..."

# 5. Install Argo CD
echo "🐙 Menginstal Argo CD..."
kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
kubectl apply --server-side --force-conflicts -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

echo "⚙️  Mengonfigurasi Argo CD Server (Insecure HTTP mode & NodePort 30085)..."
# Konfigurasi insecure HTTP agar UI bisa diakses langsung via http://localhost:8085 tanpa error TLS
kubectl -n argocd patch configmap argocd-cmd-params-cm --type merge -p '{"data":{"server.insecure":"true"}}'

# Patch Service argocd-server ke NodePort 30085 (terhubung ke host port 8085)
kubectl -n argocd patch svc argocd-server -p '{
  "spec": {
    "type": "NodePort",
    "ports": [
      {
        "name": "http",
        "port": 80,
        "targetPort": 8080,
        "nodePort": 30085,
        "protocol": "TCP"
      }
    ]
  }
}'

echo "⏳ Menunggu pod Argo CD server ready..."
kubectl -n argocd rollout status deployment/argocd-server --timeout=180s || true

# 6. Setup rahasia Tableau Bridge dari .env.tableau (jika ada)
if [ -f ".env.tableau" ]; then
  echo "🔐 Menyiapkan ConfigMap & Secret Tableau Bridge dari .env.tableau..."
  set -a
  source .env.tableau
  set +a
  kubectl create configmap tableau-bridge-config \
    --from-literal=TABLEAU_SERVER_URL="${TABLEAU_SERVER_URL}" \
    --from-literal=TABLEAU_SITE_NAME="${TABLEAU_SITE_NAME}" \
    --from-literal=TABLEAU_USER_EMAIL="${TABLEAU_USER_EMAIL:-admin@example.com}" \
    --from-literal=POOL_ID="${POOL_ID}" \
    --from-literal=CLIENT_NAME_PREFIX="${CLIENT_NAME_PREFIX:-k8s-local-mac}" \
    --from-literal=MYSQL_HOST="${MYSQL_HOST:-mysql-podman-service}" \
    --from-literal=MYSQL_PORT="${MYSQL_PORT:-3306}" \
    --dry-run=client -o yaml | kubectl apply -f -

  kubectl create secret generic tableau-bridge-secret \
    --from-literal=TABLEAU_TOKEN_NAME="${TABLEAU_TOKEN_NAME}" \
    --from-literal=TABLEAU_TOKEN_VALUE="${TABLEAU_TOKEN_VALUE}" \
    --from-literal=MYSQL_USER="${MYSQL_USER:-appuser}" \
    --from-literal=MYSQL_PASSWORD="${MYSQL_PASSWORD}" \
    --dry-run=client -o yaml | kubectl apply -f -
fi

# 7. Ambil Initial Admin Password Argo CD
echo "🔑 Mengambil Argo CD Initial Admin Password..."
ARGO_PASSWORD=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" 2>/dev/null | base64 -d || echo "Belum tersedia, jalankan: kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d")

# 8. Deploy App-of-Apps (Root Application)
echo "🚀 Menerapkan Root Application Argo CD (App-of-Apps Pattern)..."
kubectl apply -f argocd/bootstrap/root-app.yaml

echo ""
echo "=========================================================="
echo "✅ SETUP BERHASIL! Argo CD GitOps Cluster Siap Digunakan"
echo "=========================================================="
echo "🌐 Argo CD Web UI:          http://localhost:8085"
echo "👤 Username:                 admin"
echo "🔑 Initial Password:         ${ARGO_PASSWORD}"
echo ""
echo "⚖️  Perbandingan Akses Endpoint:"
echo "----------------------------------------------------------"
echo "• Cluster Lama (Manual):     http://localhost/api/v1/nodejs/info"
echo "• Cluster Baru (Argo CD):    http://localhost:8080/api/v1/nodejs/info"
echo "                             http://localhost:8080/api/v1/golang/products"
echo "                             http://localhost:8080/api/v1/java/users"
echo "----------------------------------------------------------"
echo "📌 Catatan Sinkronisasi GitOps:"
echo "Argo CD menarik manifest dari branch remote: poc/argo-cd"
echo "Pastikan perubahan lokal di-push ke GitHub agar Argo CD melakukan auto-sync:"
echo "   git add argocd/ scripts/"
echo "   git commit -m 'feat: argo-cd gitops setup and comparison cluster'"
echo "   git push origin poc/argo-cd"
echo ""
echo "Untuk melihat status aplikasi di terminal:"
echo "   kubectl -n argocd get applications"
echo "=========================================================="
