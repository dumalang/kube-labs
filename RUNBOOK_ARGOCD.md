# 🐙 Argo CD GitOps Lab & Comparison Runbook

Runbook ini menjelaskan implementasi **GitOps** menggunakan **Argo CD** pada cluster Kubernetes baru (**`k8s-argocd-lab`**) sebagai pembanding langsung terhadap cluster sebelumnya (**`k8s-microservices-lab`**) yang dikelola secara imperatif/manual (`kubectl apply`).

---

## ⚖️ Perbandingan Arsitektur: Manual vs GitOps

| Aspek | Cluster Lama (`k8s-microservices-lab`) | Cluster Baru (`k8s-argocd-lab`) |
| :--- | :--- | :--- |
| **Metode Deployment** | Manual / Imperatif (`./scripts/setup-cluster.sh`, `kubectl apply`) | **GitOps Declarative** (Argo CD otomatis mensinkronkan dari Git) |
| **Source of Truth** | Local filesystem / command prompt | **Git Repository** (`poc/argo-cd` branch di GitHub) |
| **Self-Healing** | ❌ Manual (jika resource dihapus/berubah, tidak otomatis kembali) | ✅ **Otomatis** (Argo CD mendeteksi drift dan mengembalikan state) |
| **Visibility & UI** | CLI (`kubectl get pods`) / Lens | **Argo CD Web Dashboard** (`http://localhost:8085`) |
| **Pola Aplikasi** | Script batch memanggil semua file yaml satu per satu | **App-of-Apps Pattern** (Root Application mengelola sub-aplikasi) |
| **Ingress HTTP Port** | `http://localhost/` (Port 80) | `http://localhost:8080/` (Port 8080) |
| **Ingress HTTPS Port**| `https://localhost/` (Port 443) | `https://localhost:8443/` (Port 8443) |
| **Argo CD UI Port**   | N/A | `http://localhost:8085` (NodePort 30085) |

---

## 🏗️ Struktur GitOps & Pola App-of-Apps

```
argocd/
├── kind-argocd-config.yaml          # Konfigurasi Kind (Port 8080, 8443, 8085)
├── bootstrap/
│   ├── root-app.yaml                # 👑 Root Application (App-of-Apps)
│   └── applications/
│       ├── 01-microservices.yaml    # Argo CD App: Node.js, Go, Java, Ingress
│       ├── 02-batch-jobs.yaml       # Argo CD App: Worker Job & Scheduled CronJob
│       ├── 03-monitoring.yaml       # Argo CD App: Prometheus SA & Kube State Metrics
│       └── 04-tableau-bridge.yaml   # Argo CD App: Tableau Bridge HA
└── apps/
    ├── microservices/               # Kustomization manifest microservices
    ├── batch-jobs/                  # Kustomization manifest batch jobs
    ├── monitoring/                  # Kustomization manifest monitoring
    └── tableau-bridge/              # Kustomization manifest Tableau Bridge
```

### Diagram Relasi App-of-Apps
```
                  ┌────────────────────────┐
                  │  root-app (Argo CD)    │
                  └───────────┬────────────┘
                              │ Mengelola Sub-Aplikasi
       ┌──────────────────────┼──────────────────────┬──────────────────────┐
       ▼                      ▼                      ▼                      ▼
┌──────────────┐       ┌──────────────┐       ┌──────────────┐       ┌──────────────┐
│microservices-│       │  batch-jobs  │       │  monitoring  │       │tableau-bridge│
│    core      │       └──────────────┘       └──────────────┘       └──────────────┘
└──────────────┘
```

---

## 🚀 Cara Menjalankan Cluster Pembanding

### 1. Jalankan Script Setup Otomatis
```bash
./scripts/setup-argocd-cluster.sh
```
Script ini akan:
1. Membuat cluster Kind `k8s-argocd-lab` menggunakan Podman.
2. Membangun dan memuat container images ke cluster.
3. Menginstal NGINX Ingress Controller.
4. Menginstal Argo CD dan mengonfigurasi akses HTTP UI pada port `8085`.
5. Menerapkan Root Application Argo CD (`root-app.yaml`).

### 2. Login ke Argo CD Web UI
- **URL**: [http://localhost:8085](http://localhost:8085)
- **Username**: `admin`
- **Password**: Dihasilkan saat setup. Untuk melihat kembali:
  ```bash
  kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d && echo
  ```

---

## 🧪 Menguji Endpoint Microservices

Kedua cluster dapat berjalan secara bersamaan tanpa konflik port:

### Cluster Pembanding (Argo CD - Port 8080)
```bash
# Node.js
curl -s http://localhost:8080/api/v1/nodejs/info | jq

# Golang
curl -s http://localhost:8080/api/v1/golang/products | jq

# Java
curl -s http://localhost:8080/api/v1/java/users | jq

# Inter-service call
curl -s http://localhost:8080/api/v1/nodejs/call-golang | jq
```

### Cluster Lama (Manual - Port 80, jika sedang running)
```bash
curl -s http://localhost/api/v1/nodejs/info | jq
```

---

## ⚡ Load Testing & Benchmarking pada Cluster Argo CD

Load testing generator (`Locust` & `k6`) dapat dijalankan langsung ke cluster Argo CD (port 8080):

### 1. Menggunakan Locust Web UI (Interaktif di Browser)
```bash
./scripts/run-load-test.sh --argocd
```
Akses dashboard di [http://localhost:8089](http://localhost:8089) (Default host otomatis terisi `http://host.containers.internal:8080`).

### 2. Menggunakan Headless CLI (Terminal Benchmark)
```bash
# Format: --cli [concurrent_users] [spawn_rate] [duration]
./scripts/run-load-test.sh --argocd --cli 50 10 30s
```

### 3. Menggunakan Grafana k6
```bash
./scripts/run-load-test.sh --argocd --k6
```

> 💡 **Info:** Script `./scripts/run-load-test.sh` secara cerdas otomatis mendeteksi cluster yang sedang aktif jika flag `--argocd` tidak disertakan. Jika ingin menguji cluster manual lama, gunakan flag `--manual`.

---

## 📊 Monitoring & Observability (Grafana & Prometheus)

Monitoring stack (Prometheus & Grafana) sudah aktif dan otomatis terhubung ke cluster `k8s-argocd-lab`:

- **Grafana Web UI:** [http://localhost:3000](http://localhost:3000)
  - **Username:** `admin`
  - **Password:** `admin`
- **Prometheus Metrics & Status:** [http://localhost:9090](http://localhost:9090)
  - Target metrics: [http://localhost:9090/targets](http://localhost:9090/targets)

### Dashboard Bawaan yang Tersedia di Grafana:
1. **Kubernetes Cluster Overview**: Status node, CPU/RAM utilization, dan status pods cluster.
2. **Microservices & Workloads Overview**: Replica count pods (`service-a-nodejs`, `service-b-golang`, `service-c-java`, `tableau-bridge`), restart count, serta request rate.

### Mengelola Monitoring Stack:
```bash
# Menjalankan / menyegarkan stack monitoring:
./scripts/setup-monitoring.sh

# Menghentikan stack monitoring:
./scripts/stop-monitoring.sh
```

---

## 🔄 Siklus Kerja GitOps (Push to Sync)

Karena Argo CD diset untuk membaca remote branch `poc/argo-cd`:
1. Lakukan perubahan pada manifest di `argocd/apps/...`
2. Commit dan push ke branch `poc/argo-cd`:
   ```bash
   git add argocd/ scripts/ RUNBOOK_ARGOCD.md
   git commit -m "feat: setup argo cd comparison cluster"
   git push origin poc/argo-cd
   ```
3. Argo CD akan mendeteksi commit baru secara otomatis (default polling interval 3 menit) atau klik **Sync** di UI untuk instan.

---

## 🛡️ Demonstrasi Self-Healing & Drift Detection

Salah satu keunggulan utama GitOps dibanding manual `kubectl`:

1. Coba hapus deployment service secara sengaja:
   ```bash
   kubectl delete deployment service-a-nodejs
   ```
2. Pantau apa yang terjadi:
   ```bash
   kubectl get pods -w
   ```
   **Hasil**: Argo CD secara otomatis mendeteksi bahwa state cluster tidak sesuai dengan Git (`OutOfSync`), dan fitur `selfHeal: true` akan langsung membuat ulang deployment tersebut!

---

## 🔀 Berpindah Antar Cluster di Terminal

Untuk beralih kontrol `kubectl` antar kedua cluster:

```bash
# Pindah ke cluster Argo CD:
kubectl config use-context kind-k8s-argocd-lab

# Pindah ke cluster manual:
kubectl config use-context kind-k8s-microservices-lab
```

---

## 🧹 Cleanup Cluster Argo CD

Jika sudah selesai melakukan pembandingan dan ingin membersihkan resource:
```bash
./scripts/cleanup-argocd-cluster.sh
```
Cluster lama `k8s-microservices-lab` tidak akan terpengaruh sama sekali.
