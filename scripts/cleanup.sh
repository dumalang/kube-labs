#!/usr/bin/env bash
CLUSTER_NAME="k8s-microservices-lab"
export KIND_EXPERIMENTAL_PROVIDER=podman

echo "🗑️  Deleting Kind cluster '${CLUSTER_NAME}'..."
kind delete cluster --name "${CLUSTER_NAME}" || true

echo "🧹 Cleaning up built local container images..."
podman rmi service-a-nodejs:latest service-b-golang:latest service-c-java:latest || true

echo "✅ Cleanup complete!"
