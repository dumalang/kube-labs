# 🚀 Kubernetes Microservices & Technology Lab (Podman + Kind)

Welcome to your hands-on **Kubernetes Microservices Lab**! This project is designed specifically for beginners to learn, experiment with, and master core Kubernetes concepts using **Podman** as the container engine and **Kind** (Kubernetes in Docker/Podman) as the local cluster manager.

---

## 🏗️ Architecture Overview

The lab deploys three distinct microservices written in **Node.js**, **Golang**, and **Java**, exposed through an **NGINX Ingress Controller**, along with background **Jobs**, scheduled **CronJobs**, and centralized **ConfigMaps/Secrets**.

```
                           [ Localhost Browser / cURL ]
                                        │
                                        ▼ (Port 80)
                            ┌───────────────────────┐
                            │ NGINX Ingress Controller │
                            └───────────┬───────────┘
                                        │
             ┌──────────────────────────┼──────────────────────────┐
             ▼                          ▼                          ▼
     Path: /api/v1/nodejs       Path: /api/v1/golang       Path: /api/v1/java
             │                          │                          │
  ┌──────────▼──────────┐    ┌──────────▼──────────┐    ┌──────────▼──────────┐
  │  Service (Node.js)  │    │   Service (Go)      │    │   Service (Java)    │
  │  Port 3000          │    │   Port 8080         │    │   Port 8080         │
  └──────────┬──────────┘    └──────────┬──────────┘    └──────────┬──────────┘
             │                          │                          │
      ┌──────┴──────┐            ┌──────┴──────┐                   │
      ▼             ▼            ▼             ▼                   ▼
  ┌───────┐     ┌───────┐    ┌───────┐     ┌───────┐           ┌───────┐
  │ Pod 1 │     │ Pod 2 │    │ Pod 1 │     │ Pod 2 │           │ Pod 1 │
  └───────┘     └───────┘    └───────┘     └───────┘           └───────┘
                                        ▲
                                        │ (Inter-service DNS call)
                       ┌────────────────┴─────────────────┐
                       │ ConfigMaps & Secrets             │
                       │ Jobs & Recurring CronJobs        │
                       └──────────────────────────────────┘
```

---

## 📚 Core Kubernetes Concepts Explained Simply

| K8s Concept | What It Does | Analogy | Lab Example |
| :--- | :--- | :--- | :--- |
| **Pod** | The smallest deployable unit in K8s; wraps one or more containers. | A single shipping container. | `service-a-nodejs-7d49959664-x82pt` |
| **Deployment** | Manages a set of identical Pods; handles scaling, self-healing, and zero-downtime rolling updates. | The factory manager making sure N copies are running. | `k8s/01-service-a-nodejs.yaml` (2 replicas) |
| **Service (ClusterIP)** | An internal virtual IP and DNS name providing stable load balancing across Pods. | An internal telephone extension number. | `http://service-b-golang:8080` |
| **Ingress** | HTTP/HTTPS routing rules mapping external requests (e.g. `http://localhost/api/...`) to internal Services. | The front receptionist routing incoming guests. | `k8s/04-ingress.yaml` (NGINX routing) |
| **ConfigMap & Secret** | Decouples configuration and passwords from container code. | Config files and secure vault credentials. | `k8s/00-namespace-config.yaml` |
| **Job** | A workload that runs to completion once (e.g., database migration or batch report). | A temp worker hired for a single task. | `batch-worker-job` in `k8s/05-jobs-cronjobs.yaml` |
| **CronJob** | A recurring Job triggered on a time schedule (e.g., every 2 minutes). | An automated alarm clock running a routine script. | `scheduled-cleanup-cronjob` |
| **Health Probes** | `livenessProbe` checks if app is alive (restarts if failed); `readinessProbe` checks if app can accept traffic. | Regular health checkups. | `/healthz` & `/readyz` endpoints |

---

## ⚡ Quick Start: 1-Command Setup

### 1. Run the Automated Cluster Setup
In your terminal, execute:
```bash
./scripts/setup-cluster.sh
```
This script automatically:
1. Configures `KIND_EXPERIMENTAL_PROVIDER=podman`
2. Creates a local Kind Kubernetes cluster named `k8s-microservices-lab`
3. Builds container images using `podman build` for Node.js, Golang, and Java
4. Loads the images into the Kind cluster
5. Installs the NGINX Ingress Controller
6. Applies all Kubernetes manifests

---

## 🧪 Testing Your Cluster & Microservices

### 1. Test Ingress REST API Routes
Once setup finishes, test all three microservices through local Ingress routing (`http://localhost`):

#### Node.js Service Endpoint:
```bash
curl -s http://localhost/api/v1/nodejs/info | jq
```
*Expected Output:*
```json
{
  "service": "service-a-nodejs",
  "language": "Node.js",
  "framework": "Express",
  "hostname": "service-a-nodejs-7d49959664-x82pt",
  "environment": "production-simulated",
  "secretLoaded": true
}
```

#### Golang Service Endpoint:
```bash
curl -s http://localhost/api/v1/golang/products | jq
```
*Expected Output:*
```json
{
  "service": "service-b-golang",
  "language": "Golang",
  "hostname": "service-b-golang-56677f98c9-j4k2m",
  "products": [
    { "id": 101, "name": "Kubernetes Handbook", "price": 29.99 },
    { "id": 102, "name": "Podman Essentials", "price": 19.99 }
  ]
}
```

#### Java (Spring Boot) Service Endpoint:
```bash
curl -s http://localhost/api/v1/java/users | jq
```
*Expected Output:*
```json
{
  "service": "service-c-java",
  "language": "Java 21",
  "framework": "Spring Boot 3",
  "users": [
    { "id": 1, "name": "Alice Johnson", "role": "DevOps Engineer" }
  ]
}
```

---

### 📬 Testing with Postman
A ready-to-use **Postman Collection** is included in the project: [`postman_collection.json`](file:///Users/jimmy/Labs/postman_collection.json).

#### How to Use:
1. Open **Postman**.
2. Click **Import** and select [`postman_collection.json`](file:///Users/jimmy/Labs/postman_collection.json).
3. The collection provides pre-configured requests with automated test assertions for:
   - **Node.js Service**: Info, Liveness Probe, Inter-Service call to Go.
   - **Golang Service**: Products catalog & Liveness Probe.
   - **Java Service**: Users list & Liveness Probe.
   - **NGINX Ingress Routing**: Path prefix routing tests (`/api/v1/nodejs`, `/api/v1/golang`, `/api/v1/java`).
4. Set the `baseUrl` variable to `http://localhost` (or `http://localhost:8080` if using `kubectl port-forward`).

---

### ⚡ Web Load Testing & Benchmarking (Locust Web UI)

This cluster includes **Locust**, a modern Python-based load testing tool with an interactive Web UI for real-time performance benchmarking.

#### 1. Start the Locust Web Dashboard
Run the load testing script:
```bash
./scripts/run-load-test.sh
```
This automatically starts port-forwarding to `http://localhost:8089`.

#### 2. Open the Locust Web Interface
Navigate to **`http://localhost:8089`** in your web browser. You will see:
- **Number of users**: e.g., `50`
- **Spawn rate**: e.g., `5` users per second
- **Host**: `http://ingress-nginx-controller.ingress-nginx.svc.cluster.local` (pre-configured to route requests through NGINX Ingress Controller)

#### 3. Live Metrics & Charts
Click **Start Swarming** to observe:
- **RPS (Requests Per Second)** across Node.js, Golang, and Java microservices.
- **Response Time Latencies** (Average, 95th Percentile, 99th Percentile).
- **Failure Rates & Exceptions**.

#### 4. Automated CLI Headless Benchmark Mode (Locust)
To execute a quick 30-second headless Locust load test directly from terminal:
```bash
./scripts/run-load-test.sh --cli 50 10 30s
```

#### 5. Grafana k6 Standalone Container Stress Test
To execute a automated Grafana k6 scenario stress test in a standalone Podman container:
```bash
./scripts/run-load-test.sh --k6
```
This runs staged user concurrency ramping (20 -> 50 VUs) with automated 95th percentile latency checks (`p(95) < 500ms`).


---

## 🎓 Hands-On Learning Exercises for Beginners

### Exercise 1: Observe Load Balancing Across Pod Replicas
Both Node.js and Golang services run **2 replicas**. Execute the command below 5 times:
```bash
for i in {1..5}; do curl -s http://localhost/api/v1/nodejs/info | jq -r '.hostname'; done
```
*What you will see:* The `hostname` alternates between the two pod names! Kubernetes automatically load balances requests across healthy pod replicas.

---

### Exercise 2: Test Inter-Service Communication (K8s Internal DNS)
Call the special Node.js endpoint `/call-golang`:
```bash
curl -s http://localhost/api/v1/nodejs/call-golang | jq
```
*What happens:* Node.js receives your request, queries `http://service-b-golang:8080/api/v1/golang/products` inside the cluster using Kubernetes internal DNS, and returns the response back to you.

---

### Exercise 3: Scale a Service Up and Down
Scale the Node.js deployment from 2 replicas to 4 replicas:
```bash
kubectl scale deployment/service-a-nodejs --replicas=4
```
Check the status:
```bash
kubectl get pods -l app=service-a-nodejs
```
You will see 4 pods running! Now scale it back down:
```bash
kubectl scale deployment/service-a-nodejs --replicas=2
```

---

### Exercise 4: Inspect Jobs & CronJobs
Check your one-off batch Job and recurring CronJob:
```bash
# View Job status
kubectl get jobs

# View logs of the completed worker job
kubectl logs job/batch-worker-job

# View scheduled CronJobs
kubectl get cronjob

# View pods created by the CronJob (runs every 2 minutes)
kubectl get pods -l app=scheduled-cleanup
```

---

### Exercise 5: Test Kubernetes Self-Healing
Delete one of the running Node.js pods manually:
```bash
# Get pod name
POD_NAME=$(kubectl get pods -l app=service-a-nodejs -o jsonpath='{.items[0].metadata.name}')

# Delete the pod
kubectl delete pod $POD_NAME

# Immediately list pods
kubectl get pods -l app=service-a-nodejs
```
*What happens:* Kubernetes notices that the desired state (2 replicas) doesn't match the actual state (1 replica), and instantly starts a brand new replacement pod!

---

### Exercise 6: Inspect ConfigMaps & Secrets
View the environment variables and secrets injected into the pods:
```bash
# View ConfigMap details
kubectl describe configmap app-config

# View secret details
kubectl describe secret app-secrets

# Check environment variables inside a running pod
kubectl exec -it deployment/service-a-nodejs -- env | grep -E "APP_ENV|API_KEY"
```

---

### Exercise 7: Perform Load Testing & Monitor CPU/Memory Usage
Observe how microservice pods handle high traffic load under stress:
1. Run a 30-second headless load test generating 100 concurrent users:
   ```bash
   ./scripts/run-load-test.sh --cli 100 20 30s
   ```
2. In a separate terminal window, monitor CPU and memory utilization across pods:
   ```bash
   kubectl top pods
   ```
3. Open Locust Web UI at `http://localhost:8089` using `./scripts/run-load-test.sh` to analyze response time percentiles and peak RPS live!

---

## 📊 Cluster Monitoring (Grafana & Prometheus Containers)

A dedicated monitoring stack running **Grafana** and **Prometheus** in separate containers connected directly to the local Kind Kubernetes cluster.

### 🚀 Quick Start: Launch Monitoring Stack

Run the automated setup script:
```bash
./scripts/setup-monitoring.sh
```

This script will:
1. Deploy Kubernetes RBAC and `kube-state-metrics` exporter to `kube-system`.
2. Extract dynamic ServiceAccount bearer tokens for secure API access.
3. Launch **Prometheus** (`port 9090`) and **Grafana** (`port 3000`) in separate containers on the `kind` network bridge.
4. Auto-provision Prometheus datasource and pre-loaded visual Grafana dashboards.

### 🌐 Access Interfaces

| Service | Access URL | Default Credentials | Description |
| :--- | :--- | :--- | :--- |
| **Grafana UI** | `http://localhost:3000` | `admin` / `admin` | Visual dashboards (Cluster & Microservices overview) |
| **Prometheus UI** | `http://localhost:9090` | None | Raw PromQL metric queries & target health check |

### 📈 Included Dashboards
- **Kubernetes Cluster Overview**: Live Node CPU & RAM usage, pod status breakdown (Running, Pending, Failed), container CPU/memory per pod, network traffic & disk I/O.
- **Microservices & Workloads Overview**: Replica count gauges (Service A, Service B, Service C), pod restart counts, API Server request rates.

### 🛑 Stop Monitoring Stack
```bash
./scripts/stop-monitoring.sh
```

---

## ⚡ Application Performance Monitoring (Elastic APM ELK Stack)

A dedicated **Elastic APM (ELK Stack)** container environment providing real-time distributed tracing, performance metrics, request latency breakdowns, and cross-service transaction tracking across all microservices (`service-a-nodejs`, `service-b-golang`, `service-c-java`).

### 🚀 Quick Start: Launch APM ELK Stack

Run the automated APM setup script:
```bash
./scripts/setup-apm-elk.sh
```

This script will:
1. Apply the internal Kubernetes `apm-server` Service endpoint manifest (`k8s/07-apm-service.yaml`).
2. Spin up containerized **Elasticsearch**, **Kibana**, and **APM Server** on the `kind` network bridge.
3. Perform health checks for APM Server (`http://localhost:8200`) and Kibana (`http://localhost:5601`).

### 🌐 APM Access Interfaces

| Service | Access URL | Credentials | Description |
| :--- | :--- | :--- | :--- |
| **Kibana APM UI** | `http://localhost:5601/app/apm` | None (Local Lab) | Interactive APM service dashboard, latency percentiles, error tracking & distributed traces |
| **APM Server API** | `http://localhost:8200` | None | Elastic APM ingestion server endpoint |
| **Elasticsearch API** | `http://localhost:9200` | None | Search & analytical engine backend |

### 🔬 Microservice APM Instrumentation Summary

- **Node.js (`service-a-nodejs`)**: Instrumented with `elastic-apm-node` agent initialized before Express server creation.
- **Golang (`service-b-golang`)**: Instrumented with `go.elastic.co/apm/module/apmhttp/v2` wrapping HTTP request handlers.
- **Java (`service-c-java`)**: Instrumented with zero-code Spring Boot Java Agent (`elastic-apm-agent-1.50.0.jar`) via `JAVA_TOOL_OPTIONS="-javaagent:..."`.

### 🛡️ APM Best Practices Applied
- **Fault-Tolerant Connection Handling**: App performance is unaffected if APM server drops connection.
- **ConfigMap-Driven Active Toggle**: `ELASTIC_APM_ACTIVE` can pause/resume tracing without recompiling code.
- **Distributed Trace Context Propagation**: `service-a-nodejs` propagation headers allow Kibana to render complete trace graphs when calling `service-b-golang`.

### 🛑 Stop APM ELK Stack
```bash
./scripts/stop-apm-elk.sh
```

---

## 🛠️ Essential `kubectl` Beginner Cheat Sheet

```bash
# 📌 Viewing Resources
kubectl get pods                   # List all pods
kubectl get services               # List all services
kubectl get deployments            # List all deployments
kubectl get ingress                # List all ingresses
kubectl get all                    # List everything in default namespace

# 🔍 Debugging & Inspection
kubectl describe pod <pod-name>    # Detailed information & events for a pod
kubectl logs <pod-name>            # Print pod logs
kubectl logs -f <pod-name>         # Stream pod logs (tail -f)
kubectl exec -it <pod-name> -- sh  # Open interactive terminal shell inside container

# 🔄 Lifecycle Management
kubectl rollout restart deployment/service-a-nodejs # Restart all pods in a deployment
kubectl delete pod <pod-name>                       # Delete a pod
```

---

## 🧹 Clean Up

To delete the Kind cluster and remove local images created during this lab, run:
```bash
./scripts/cleanup.sh
```

---

## 📁 Repository Directory Structure

```
.
├── README.md                      # This comprehensive guide
├── service-a-nodejs/             # Express REST API (Node.js 20 + Elastic APM)
│   ├── Containerfile
│   ├── package.json
│   └── src/index.js
├── service-b-golang/             # Go REST API (Go 1.22 + Elastic APM)
│   ├── Containerfile
│   ├── go.mod
│   └── main.go
├── service-c-java/               # Spring Boot REST API (Java 21 + Elastic APM)
│   ├── Containerfile
│   ├── pom.xml
│   └── src/main/java/com/example/app/Application.java
├── k8s/                          # Kubernetes Manifests
│   ├── kind-config.yaml          # Kind cluster config (port 80/443 mapping)
│   ├── 00-namespace-config.yaml  # ConfigMaps (including ELASTIC_APM_SERVER_URL) & Secrets
│   ├── 01-service-a-nodejs.yaml  # Deployment & Service A
│   ├── 02-service-b-golang.yaml  # Deployment & Service B
│   ├── 03-service-c-java.yaml    # Deployment & Service C
│   ├── 04-ingress.yaml           # Ingress routing rules
│   ├── 05-jobs-cronjobs.yaml     # Worker Job & CronJob
│   ├── 06-monitoring-setup.yaml  # RBAC & Kube-State-Metrics setup
│   └── 07-apm-service.yaml       # K8s Service mapping to containerized APM Server
├── monitoring/                   # Prometheus & Grafana Stack
│   ├── docker-compose.yml        # Prometheus & Grafana compose setup
│   ├── prometheus.yml.template   # Dynamic Prometheus scrape config
│   └── grafana/                  # Provisioning configs & JSON dashboards
├── monitoring-elk/               # Elastic APM ELK Container Stack
│   └── docker-compose.yml        # Elasticsearch, Kibana & APM Server compose setup
└── scripts/                      # Setup, Monitoring, and Cleanup scripts
    ├── setup-cluster.sh          # Automated cluster setup script
    ├── setup-monitoring.sh       # Automated Grafana monitoring setup script
    ├── stop-monitoring.sh        # Grafana monitoring teardown script
    ├── setup-apm-elk.sh          # Automated APM ELK setup script
    ├── stop-apm-elk.sh           # APM ELK teardown script
    └── cleanup.sh                # Cluster teardown script
```
