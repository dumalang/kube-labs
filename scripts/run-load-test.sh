#!/usr/bin/env bash
set -e

MODE=${1:-"--web"}
TARGET_HOST=${TARGET_HOST:-"http://host.containers.internal"}

echo "=================================================="
echo "⚡ External Standalone Locust Load Generator (Podman)"
echo "=================================================="

# Check if podman is available
if ! command -v podman >/dev/null 2>&1; then
  echo "❌ Podman command not found. Please install Podman."
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [ "$MODE" = "--cli" ] || [ "$MODE" = "--headless" ]; then
  USERS=${2:-50}
  SPAWN_RATE=${3:-10}
  RUN_TIME=${4:-30s}

  echo "🚀 Running External Headless Benchmark Test (Locust)..."
  echo "   Target Host: $TARGET_HOST"
  echo "   Concurrent Users: $USERS"
  echo "   Spawn Rate: $SPAWN_RATE users/sec"
  echo "   Duration: $RUN_TIME"
  echo "--------------------------------------------------"

  podman run --rm -i \
    --add-host host.containers.internal:host-gateway \
    -v "$SCRIPT_DIR/loadtest:/mnt/locust:z" \
    docker.io/locustio/locust:latest \
    -f /mnt/locust/locustfile.py \
    --headless \
    -u "$USERS" \
    -r "$SPAWN_RATE" \
    --run-time "$RUN_TIME" \
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
  echo "💡 Tip: Default Host is set to $TARGET_HOST"
  echo "   Press Ctrl+C to stop the Locust container."
  echo "--------------------------------------------------"

  podman run --rm -it \
    -p 8089:8089 \
    --add-host host.containers.internal:host-gateway \
    -v "$SCRIPT_DIR/loadtest:/mnt/locust:z" \
    docker.io/locustio/locust:latest \
    -f /mnt/locust/locustfile.py \
    --web-port 8089 \
    --host "$TARGET_HOST"
fi

