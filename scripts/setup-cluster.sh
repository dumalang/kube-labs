#!/usr/bin/env bash
set -e

CLUSTER_NAME="k8s-microservices-lab"
export KIND_EXPERIMENTAL_PROVIDER=podman

echo "=================================================="
echo "🚀 Kubernetes Microservices Lab Setup (Podman + Kind)"
echo "=================================================="

# 1. Check if cluster already exists
if kind get clusters 2>/dev/null | grep -q "^${CLUSTER_NAME}$"; then
  echo "ℹ️  Cluster '${CLUSTER_NAME}' already exists."
else
  echo "📦 Creating Kind cluster '${CLUSTER_NAME}' using Podman..."
  kind create cluster --config k8s/kind-config.yaml
fi

# 2. Build images with Podman
echo "🛠️  Building service images with Podman..."

echo " -> Building Node.js service..."
podman build -t service-a-nodejs:latest -f service-a-nodejs/Containerfile service-a-nodejs

echo " -> Building Golang service..."
podman build -t service-b-golang:latest -f service-b-golang/Containerfile service-b-golang

echo " -> Building Java service..."
podman build -t service-c-java:latest -f service-c-java/Containerfile service-c-java

# 3. Load images into Kind cluster
echo "📥 Loading images into Kind cluster..."

loadImage() {
  local img_name=$1
  local tar_path="/tmp/${img_name}.tar"
  echo " -> Loading ${img_name}:latest..."
  podman save "${img_name}:latest" -o "${tar_path}"
  kind load image-archive "${tar_path}" --name "${CLUSTER_NAME}"
  rm -f "${tar_path}"
}

loadImage "service-a-nodejs"
loadImage "service-b-golang"
loadImage "service-c-java"

# 4. Install NGINX Ingress Controller for Kind
echo "🌐 Installing NGINX Ingress Controller..."
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/kind/deploy.yaml

echo "⏳ Waiting for NGINX Ingress Controller to be ready..."
kubectl wait --namespace ingress-nginx \
  --for=condition=ready pod \
  --selector=app.kubernetes.io/component=controller \
  --timeout=120s || echo "⚠️  Ingress deployment taking longer than expected..."

# 5. Apply Kubernetes Manifests
echo "📋 Applying Kubernetes manifests..."
kubectl apply -f k8s/00-namespace-config.yaml
kubectl apply -f k8s/01-service-a-nodejs.yaml
kubectl apply -f k8s/02-service-b-golang.yaml
kubectl apply -f k8s/03-service-c-java.yaml
kubectl apply -f k8s/04-ingress.yaml
kubectl apply -f k8s/05-jobs-cronjobs.yaml
kubectl apply -f k8s/06-locust-loadtest.yaml
kubectl apply -f k8s/07-apm-service.yaml

echo ""
echo "=================================================="
echo "✅ Setup complete! Cluster status:"
echo "=================================================="
kubectl get pods
kubectl get services
kubectl get ingress
kubectl get cronjobs

echo ""
echo "🎉 You can now test your APIs via Ingress:"
echo "   Node.js API:   curl http://localhost/api/v1/nodejs/info"
echo "   Golang API:    curl http://localhost/api/v1/golang/products"
echo "   Java API:      curl http://localhost/api/v1/java/users"
echo "   Inter-Service: curl http://localhost/api/v1/nodejs/call-golang"
echo ""
echo "⚡ Load Testing Web UI (Locust):"
echo "   Run: ./scripts/run-load-test.sh"
echo "   Then open: http://localhost:8089"

