#!/usr/bin/env bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

echo "=== 🚀 Setting up APM ELK Stack (Elasticsearch, Kibana, APM Server) ==="

cd "${ROOT_DIR}"

# 1. Verify Kubernetes connectivity
if ! kubectl cluster-info >/dev/null 2>&1; then
    echo "❌ Error: Cannot connect to Kubernetes cluster. Ensure Kind cluster is running."
    exit 1
fi

echo "✅ Kubernetes cluster connected."

# 2. Apply APM Kubernetes ExternalName/Endpoint Service
echo "📦 Applying APM Kubernetes service endpoint..."
kubectl apply -f k8s/07-apm-service.yaml

# 3. Launch APM ELK Containers
echo "🐳 Launching Elasticsearch, Kibana, and APM Server containers on 'kind' network..."

COMPOSE_CMD=""
if command -v docker-compose >/dev/null 2>&1; then
    COMPOSE_CMD="docker-compose"
elif podman compose version >/dev/null 2>&1; then
    COMPOSE_CMD="podman compose"
fi

if [ -n "$COMPOSE_CMD" ]; then
    cd monitoring-elk
    $COMPOSE_CMD down --remove-orphans >/dev/null 2>&1 || true
    $COMPOSE_CMD up -d
else
    echo "⚠️ Neither docker-compose nor podman compose found, launching via podman run..."
    podman stop monitoring-elasticsearch monitoring-kibana monitoring-apm-server 2>/dev/null || true
    podman rm monitoring-elasticsearch monitoring-kibana monitoring-apm-server 2>/dev/null || true

    echo " -> Starting Elasticsearch container..."
    podman run -d \
        --name monitoring-elasticsearch \
        --net kind \
        -p 9200:9200 \
        -e "discovery.type=single-node" \
        -e "xpack.security.enabled=false" \
        -e "ES_JAVA_OPTS=-Xms512m -Xmx512m" \
        docker.elastic.co/elasticsearch/elasticsearch:8.14.3

    echo " -> Waiting for Elasticsearch to respond..."
    for i in {1..30}; do
        if curl -s http://localhost:9200/_cluster/health | grep -q '"status"'; then
            echo "✅ Elasticsearch is healthy."
            break
        fi
        sleep 2
    done

    echo " -> Starting Kibana container..."
    podman run -d \
        --name monitoring-kibana \
        --net kind \
        -p 5601:5601 \
        -e "ELASTICSEARCH_HOSTS=http://elasticsearch:9200" \
        docker.elastic.co/kibana/kibana:8.14.3

    echo " -> Starting APM Server container..."
    podman run -d \
        --name monitoring-apm-server \
        --net kind \
        -p 8200:8200 \
        docker.elastic.co/apm/apm-server:8.14.3 \
        apm-server -e \
        -E apm-server.host=0.0.0.0:8200 \
        -E apm-server.kibana.enabled=true \
        -E apm-server.kibana.host=kibana:5601 \
        -E apm-server.data_streams.wait_for_integration=false \
        -E output.elasticsearch.hosts=["http://elasticsearch:9200"]
fi

echo "⏳ Waiting for APM Server to become operational at http://localhost:8200..."
for i in {1..30}; do
    if curl -s http://localhost:8200/ | grep -q "build_date"; then
        echo "✅ APM Server is up and ready!"
        break
    fi
    sleep 2
done

echo "🛠️ Ensuring Elasticsearch mappings and fielddata are enabled for APM traces..."
AUTH_ARG=""
if curl -s -u elastic:securepassword123 http://localhost:9200/_cluster/health | grep -q '"status"'; then
    AUTH_ARG="-u elastic:securepassword123"
fi

# 1. Enable fielddata on all text fields in traces-apm-default
python3 -c '
import urllib.request, json, base64

url = "http://localhost:9200/traces-apm-default/_mapping"
req = urllib.request.Request(url)
credentials = base64.b64encode(b"elastic:securepassword123").decode("utf-8")
req.add_header("Authorization", f"Basic {credentials}")

try:
    res = urllib.request.urlopen(req)
    data = json.loads(res.read())
    properties = data.get("traces-apm-default", {}).get("mappings", {}).get("properties", {})

    def build_update_props(props):
        update = {}
        for k, v in props.items():
            if isinstance(v, dict):
                if v.get("type") == "text":
                    sub_fields = v.get("fields", {})
                    update[k] = {"type": "text", "fielddata": True}
                    if sub_fields:
                        update[k]["fields"] = sub_fields
                elif "properties" in v:
                    sub_update = build_update_props(v["properties"])
                    if sub_update:
                        update[k] = {"properties": sub_update}
        return update

    update_payload = {"properties": build_update_props(properties)}
    update_req = urllib.request.Request(url, data=json.dumps(update_payload).encode("utf-8"), headers={
        "Content-Type": "application/json",
        "Authorization": f"Basic {credentials}"
    }, method="PUT")
    urllib.request.urlopen(update_req)
except Exception:
    pass
' >/dev/null 2>&1 || true

# 2. Add high-priority index template so future string fields in traces-apm* indices default to keywords
curl -s -X PUT $AUTH_ARG "http://localhost:9200/_index_template/traces-apm-override" \
  -H "Content-Type: application/json" \
  -d '{
    "priority": 1000,
    "index_patterns": ["traces-apm*"],
    "template": {
      "mappings": {
        "dynamic_templates": [
          {
            "strings_as_keywords": {
              "match_mapping_type": "string",
              "mapping": {
                "type": "keyword",
                "ignore_above": 1024
              }
            }
          }
        ]
      }
    }
  }' >/dev/null 2>&1 || true

echo "✅ APM fielddata & mapping configuration applied."

echo ""
echo "=== 🎉 APM ELK Setup Complete! ==="
echo "📊 Kibana Dashboard / APM UI: http://localhost:5601/app/apm"
echo "🔍 Elasticsearch API:        http://localhost:9200"
echo "🚀 APM Server Endpoint:      http://localhost:8200"
echo "======================================"

