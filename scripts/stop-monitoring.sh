#!/usr/bin/env bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

echo "=== 🛑 Stopping Monitoring Stack ==="

if command -v docker-compose >/dev/null 2>&1; then
    cd "${ROOT_DIR}/monitoring"
    docker-compose down --remove-orphans || true
elif podman compose version >/dev/null 2>&1; then
    cd "${ROOT_DIR}/monitoring"
    podman compose down || true
else
    podman stop monitoring-prometheus monitoring-grafana 2>/dev/null || true
    podman rm monitoring-prometheus monitoring-grafana 2>/dev/null || true
fi

echo "✅ Monitoring containers stopped and removed."
