#!/usr/bin/env bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

echo "=== 🛑 Stopping APM ELK Monitoring Stack ==="

if command -v docker-compose >/dev/null 2>&1; then
    cd "${ROOT_DIR}/monitoring-elk"
    docker-compose down --remove-orphans || true
elif podman compose version >/dev/null 2>&1; then
    cd "${ROOT_DIR}/monitoring-elk"
    podman compose down || true
else
    podman stop monitoring-elasticsearch monitoring-kibana monitoring-apm-server 2>/dev/null || true
    podman rm monitoring-elasticsearch monitoring-kibana monitoring-apm-server 2>/dev/null || true
fi

echo "✅ APM ELK containers stopped and removed."
