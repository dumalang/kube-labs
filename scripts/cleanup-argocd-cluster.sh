#!/usr/bin/env bash
set -e

CLUSTER_NAME="k8s-argocd-lab"
export KIND_EXPERIMENTAL_PROVIDER=podman

echo "=========================================================="
echo "🧹 Menghapus Cluster Pembanding Argo CD: ${CLUSTER_NAME}"
echo "=========================================================="

if kind get clusters 2>/dev/null | grep -q "^${CLUSTER_NAME}$"; then
  echo "🗑️  Menghapus Kind cluster '${CLUSTER_NAME}'..."
  kind delete cluster --name "${CLUSTER_NAME}"
  echo "✅ Cluster '${CLUSTER_NAME}' berhasil dihapus."
else
  echo "ℹ️  Cluster '${CLUSTER_NAME}' tidak ditemukan."
fi

echo "=========================================================="
