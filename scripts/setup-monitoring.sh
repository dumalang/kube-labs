#!/usr/bin/env bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

echo "=== 🚀 Setting up Cluster Monitoring Stack ==="

cd "${ROOT_DIR}"

# 1. Verify Kubernetes connectivity
if ! kubectl cluster-info >/dev/null 2>&1; then
    echo "❌ Error: Cannot connect to Kubernetes cluster. Ensure Kind cluster is running."
    exit 1
fi

echo "✅ Kubernetes cluster connected."

# 2. Apply Monitoring RBAC and Kube-State-Metrics
echo "📦 Applying Kubernetes monitoring RBAC & kube-state-metrics manifests..."
kubectl apply -f k8s/06-monitoring-setup.yaml

echo "⏳ Waiting for kube-state-metrics deployment to be ready..."
kubectl rollout status deployment/kube-state-metrics -n kube-system --timeout=90s

# 3. Retrieve ServiceAccount token for Prometheus
echo "🔑 Extracting Prometheus ServiceAccount bearer token..."
TOKEN=""
for i in {1..10}; do
    TOKEN=$(kubectl get secret prometheus-token-secret -n kube-system -o jsonpath='{.data.token}' 2>/dev/null | base64 --decode || true)
    if [ -n "$TOKEN" ]; then
        break
    fi
    sleep 2
done

if [ -z "$TOKEN" ]; then
    echo "❌ Failed to retrieve Prometheus bearer token."
    exit 1
fi

echo "✅ Bearer token retrieved successfully."

# 4. Generate dynamic prometheus.yml configuration
echo "⚙️ Generating monitoring/prometheus.yml..."
sed "s/__SERVICE_ACCOUNT_TOKEN__/${TOKEN}/g" monitoring/prometheus.yml.template > monitoring/prometheus.yml

# 5. Launch Monitoring Containers
echo "🐳 Launching Prometheus and Grafana containers on 'kind' network..."

COMPOSE_CMD=""
if command -v docker-compose >/dev/null 2>&1; then
    COMPOSE_CMD="docker-compose"
elif podman compose version >/dev/null 2>&1; then
    COMPOSE_CMD="podman compose"
fi

if [ -n "$COMPOSE_CMD" ]; then
    cd monitoring
    $COMPOSE_CMD down --remove-orphans >/dev/null 2>&1 || true
    $COMPOSE_CMD up -d
else
    echo "⚠️ Neither docker-compose nor podman compose found, launching via podman run..."
    podman stop monitoring-prometheus monitoring-grafana 2>/dev/null || true
    podman rm monitoring-prometheus monitoring-grafana 2>/dev/null || true

    podman run -d \
        --name monitoring-prometheus \
        --net kind \
        -p 9090:9090 \
        -v "${ROOT_DIR}/monitoring/prometheus.yml:/etc/prometheus/prometheus.yml:ro" \
        prom/prometheus:v2.54.0

    podman run -d \
        --name monitoring-grafana \
        --net kind \
        -p 3000:3000 \
        -e GF_SECURITY_ADMIN_USER=admin \
        -e GF_SECURITY_ADMIN_PASSWORD=admin \
        -e GF_USERS_ALLOW_SIGN_UP=false \
        -v "${ROOT_DIR}/monitoring/grafana/provisioning/datasources:/etc/grafana/provisioning/datasources:ro" \
        -v "${ROOT_DIR}/monitoring/grafana/provisioning/dashboards:/etc/grafana/provisioning/dashboards:ro" \
        -v "${ROOT_DIR}/monitoring/grafana/dashboards:/etc/grafana/dashboards:ro" \
        grafana/grafana:11.1.0
fi

echo ""
echo "=== 🎉 Monitoring Setup Complete! ==="
echo "📊 Grafana Dashboard:    http://localhost:3000 (User: admin / Pass: admin)"
echo "🔥 Prometheus Metrics:   http://localhost:9090"
echo "======================================"
