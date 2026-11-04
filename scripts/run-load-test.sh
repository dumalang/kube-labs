#!/usr/bin/env bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Check if podman is available
if ! command -v podman >/dev/null 2>&1; then
  echo "❌ Podman command not found. Please install Podman."
  exit 1
fi

MODE="--web"
TARGET_CLUSTER=""
CUSTOM_HOST=""
CLI_USERS=50
CLI_SPAWN_RATE=10
CLI_RUN_TIME="30s"

POS_ARGS=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --argocd)
      TARGET_CLUSTER="argocd"
      shift
      ;;
    --manual)
      TARGET_CLUSTER="manual"
      shift
      ;;
    --target)
      TARGET_CLUSTER="$2"
      shift 2
      ;;
    --host)
      CUSTOM_HOST="$2"
      shift 2
      ;;
    --cli|--headless)
      MODE="--cli"
      shift
      ;;
    --k6)
      MODE="--k6"
      shift
      ;;
    --web)
      MODE="--web"
      shift
      ;;
    -h|--help)
      echo "Penggunaan: ./scripts/run-load-test.sh [PILIHAN CLUSTER] [MODE] [OPSI LAIN]"
      echo ""
      echo "Pilihan Cluster Target:"
      echo "  --argocd            Target ke cluster Argo CD (k8s-argocd-lab) -> http://host.containers.internal:8080"
      echo "  --manual            Target ke cluster manual (k8s-microservices-lab) -> http://host.containers.internal"
      echo "  --host <url>        Target ke custom host URL"
      echo ""
      echo "Mode Pengujian:"
      echo "  --web               (Default) Jalankan Locust dengan Web UI di http://localhost:8089"
      echo "  --cli [u] [r] [t]   Jalankan Locust headless (CLI). Contoh: --cli 50 10 30s"
      echo "  --k6                Jalankan load testing menggunakan k6"
      echo ""
      echo "Contoh:"
      echo "  ./scripts/run-load-test.sh --argocd"
      echo "  ./scripts/run-load-test.sh --argocd --cli 100 20 1m"
      echo "  ./scripts/run-load-test.sh --argocd --k6"
      echo "  ./scripts/run-load-test.sh --manual"
      exit 0
      ;;
    *)
      POS_ARGS+=("$1")
      shift
      ;;
  esac
done

if [[ ${#POS_ARGS[@]} -ge 1 ]]; then
  CLI_USERS="${POS_ARGS[0]}"
fi
if [[ ${#POS_ARGS[@]} -ge 2 ]]; then
  CLI_SPAWN_RATE="${POS_ARGS[1]}"
fi
if [[ ${#POS_ARGS[@]} -ge 3 ]]; then
  CLI_RUN_TIME="${POS_ARGS[2]}"
fi

# Determine Target Host
if [ -n "$CUSTOM_HOST" ]; then
  TARGET_HOST="$CUSTOM_HOST"
  TARGET_DESC="Custom Host ($TARGET_HOST)"
elif [ "$TARGET_CLUSTER" = "argocd" ]; then
  TARGET_HOST="http://host.containers.internal:8080"
  TARGET_DESC="Argo CD GitOps Cluster [k8s-argocd-lab] (Port 8080)"
elif [ "$TARGET_CLUSTER" = "manual" ]; then
  TARGET_HOST="http://host.containers.internal"
  TARGET_DESC="Manual Cluster [k8s-microservices-lab] (Port 80)"
elif [ -n "$TARGET_HOST" ]; then
  TARGET_DESC="Environment Variable TARGET_HOST ($TARGET_HOST)"
else
  # Auto-detection logic:
  CURRENT_CTX=$(kubectl config current-context 2>/dev/null || echo "")
  RUNNING_ARGOCD=$(podman ps --format '{{.Names}}' 2>/dev/null | grep -E "^k8s-argocd-lab" || echo "")
  RUNNING_MANUAL=$(podman ps --format '{{.Names}}' 2>/dev/null | grep -E "^k8s-microservices-lab" || echo "")

  if [ -n "$RUNNING_ARGOCD" ] && [ -z "$RUNNING_MANUAL" ]; then
    TARGET_HOST="http://host.containers.internal:8080"
    TARGET_DESC="Auto-detected: Argo CD Cluster [k8s-argocd-lab] (Port 8080)"
  elif [ -n "$RUNNING_MANUAL" ] && [ -z "$RUNNING_ARGOCD" ]; then
    TARGET_HOST="http://host.containers.internal"
    TARGET_DESC="Auto-detected: Manual Cluster [k8s-microservices-lab] (Port 80)"
  elif [[ "$CURRENT_CTX" == *"argocd"* ]]; then
    TARGET_HOST="http://host.containers.internal:8080"
    TARGET_DESC="Auto-detected (kubectl context: $CURRENT_CTX): Argo CD Cluster (Port 8080)"
  else
    TARGET_HOST="http://host.containers.internal:8080"
    TARGET_DESC="Default: Argo CD Cluster [k8s-argocd-lab] (Port 8080)"
  fi
fi

echo "=================================================="
echo "⚡ External Standalone Load Generator (Podman)"
echo "🎯 Target     : $TARGET_DESC"
echo "🌐 Target URL : $TARGET_HOST"
echo "=================================================="

if [ "$MODE" = "--cli" ] || [ "$MODE" = "--headless" ]; then
  echo "🚀 Running External Headless Benchmark Test (Locust)..."
  echo "   Target Host: $TARGET_HOST"
  echo "   Concurrent Users: $CLI_USERS"
  echo "   Spawn Rate: $CLI_SPAWN_RATE users/sec"
  echo "   Duration: $CLI_RUN_TIME"
  echo "--------------------------------------------------"

  podman run --rm -i \
    --add-host host.containers.internal:host-gateway \
    -e TARGET_HOST="$TARGET_HOST" \
    -v "$SCRIPT_DIR/loadtest:/mnt/locust:z" \
    docker.io/locustio/locust:latest \
    -f /mnt/locust/locustfile.py \
    --headless \
    -u "$CLI_USERS" \
    -r "$CLI_SPAWN_RATE" \
    --run-time "$CLI_RUN_TIME" \
    --host "$TARGET_HOST"

  echo "--------------------------------------------------"
  echo "✅ Locust benchmark test completed!"

elif [ "$MODE" = "--k6" ]; then
  echo "🚀 Running Standalone Grafana k6 Load Test Container..."
  echo "   Target Host: $TARGET_HOST"
  echo "--------------------------------------------------"

  podman run --rm -i \
    --add-host host.containers.internal:host-gateway \
    -v "$SCRIPT_DIR/loadtest:/mnt/k6:z" \
    -e TARGET_HOST="$TARGET_HOST" \
    grafana/k6:latest \
    run /mnt/k6/k6-script.js

  echo "--------------------------------------------------"
  echo "✅ k6 stress test completed!"

else
  echo "🌐 Starting External Locust Standalone Web UI..."
  echo "👉 Access the Web Dashboard in your browser:"
  echo "   http://localhost:8089"
  echo ""
  echo "💡 Default Host is set to: $TARGET_HOST"
  echo "   Press Ctrl+C to stop the Locust container."
  echo "--------------------------------------------------"

  podman run --rm -it \
    -p 8089:8089 \
    --add-host host.containers.internal:host-gateway \
    -e TARGET_HOST="$TARGET_HOST" \
    -v "$SCRIPT_DIR/loadtest:/mnt/locust:z" \
    docker.io/locustio/locust:latest \
    -f /mnt/locust/locustfile.py \
    --web-port 8089 \
    --host "$TARGET_HOST"
fi

