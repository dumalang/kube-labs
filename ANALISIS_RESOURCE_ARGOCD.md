# 📊 Analisis Penggunaan Resource Argo CD: Apakah Berat & Boros Kapasitas?

Dokumen ini menyajikan data empiris pengukuran langsung (*live telemetry*) penggunaan **CPU & Memory** dari seluruh komponen **Argo CD** pada cluster `k8s-argocd-lab`, perbandingannya dengan workload microservices, serta analisis skalabilitasnya dari lingkungan lokal hingga skala produksi.

---

## 💡 Ringkasan Cepat (Executive Summary)

> **Pertanyaan:** *Apakah Argo CD memakan resource kapasitas cluster? Apakah ini berat dan boros resource?*
>
> **Jawaban:** **TIDAK. Argo CD tergolong SANGAT RINGAN (Extremely Lightweight).**
>
> - **Total Memory (RAM) yang dipakai:** **~235 MB** (semua 7 komponen pod digabung).
>   *Sebagai perbandingan: ini lebih kecil daripada 1 aplikasi Java Spring Boot (`service-c-java` = ~204 MB), atau bahkan 2 tab Google Chrome!*
> - **Total CPU yang dipakai (Idle/Periodic):** **< 0.1 vCPU (< 6% dari 1 core)**.
> - **Bahasa Pemrograman:** Komponen inti Argo CD ditulis dalam bahasa **Golang** (efisiensi memory kompilasi native) dan cache-nya menggunakan **Redis** berbasis C (sangat hemat footprint).

---

## 🔬 Data Pengukuran Nyata (Live Metrics dari Cluster `k8s-argocd-lab`)

Pengukuran ini diambil langsung menggunakan runtime container inspect (`crictl stats`) pada cluster `k8s-argocd-lab`:

| Nama Komponen Pod | Fungsi Utama | Penggunaan CPU | Penggunaan RAM | Persentase Beban |
| :--- | :--- | :--- | :--- | :--- |
| **`argocd-application-controller`** | Otak sinkronisasi, drift detector, & health check | ~4.76% | **115.5 MB** | 49.3% (Terbesar) |
| **`argocd-server`** | API Server backend & penyaji Web UI Dashboard | ~0.19% | **27.6 MB** | 11.8% |
| **`argocd-repo-server`** | Men-clone Git repo & me-render Kustomize/Helm | ~0.00% | **28.0 MB** | 11.9% |
| **`argocd-applicationset-controller`** | Generator otomatisasi pola App-of-Apps | ~0.11% | **20.9 MB** | 8.9% |
| **`argocd-notifications-controller`** | Pengirim notifikasi webhook/Slack (opsional) | ~0.03% | **18.7 MB** | 8.0% |
| **`argocd-dex-server`** | OIDC / SSO Authentication gateway (opsional) | ~0.00% | **18.5 MB** | 7.9% |
| **`argocd-redis`** | In-memory cache metadata Git & cluster state | ~0.88% | **5.2 MB** | 2.2% |
| **TOTAL KESELURUHAN (Argo CD)** | **7 Pod GitOps Control Plane** | **~6.0% (0.06 core)** | **~234.4 MB** | **100%** |

---

## ⚖️ Perbandingan Beban Resource: Argo CD vs Komponen Lain

Untuk memberikan perspektif seberapa ringannya Argo CD, mari bandingkan dengan komponen lain yang berjalan di mesin yang sama:

```
[ Penggunaan RAM Komponen di Cluster k8s-argocd-lab ]

1. Kubernetes Internal (kube-apiserver) : ██████████████████████████ 504.6 MB
2. SELURUH ARGO CD (7 Pods)             : ████████████ 234.4 MB
3. Microservice Java (Spring Boot)      : ██████████ 203.6 MB
4. Microservice Node.js (2 Replicas)    : █████ 104.3 MB
5. Ingress Controller (NGINX)           : ███ 64.7 MB
6. Microservice Golang (2 Replicas)     : █ 19.8 MB
```

### Dibandingkan CI/CD Tradisional (Jenkins / GitLab Runner):
- **Jenkins Controller + Agent:** Membutuhkan **2 GB – 4 GB RAM** hanya untuk idle running JVM.
- **GitLab Runner:** Membutuhkan **500 MB – 1 GB RAM** per pipeline executor.
- **Argo CD:** Hanya **~235 MB RAM** untuk mengelola seluruh siklus rilis dan deployment secara *continuous*.

---

## 📈 Kapan Pemakaian Resource Argo CD Bisa Meningkat?

Meskipun saat ini hanya memakai ~235 MB, konsumsi resource Argo CD dapat bertambah jika skala aplikasi membesar karena faktor-faktor berikut:

1. **Jumlah Objek & Aplikasi (Scale of Applications):**
   - *Lab ini:* Memiliki 5 aplikasi (`root-app`, `microservices`, `jobs`, `monitoring`, `tableau`) ➜ RAM ~115 MB pada controller.
   - *Skala 100+ Aplikasi:* Controller menyimpan pohon dependensi setiap objek di memory, sehingga RAM controller bisa naik ke **500 MB – 1 GB**.
2. **Kompleksitas Templating di `repo-server`:**
   - Manifest Kustomize sederhana di repo ini sangat cepat di-render.
   - Jika menggunakan chart Helm raksasa dengan banyak subchart, CPU `argocd-repo-server` akan mengalami lonjakan singkat (*spike*) saat proses *render manifest*.
3. **Frekuensi Polling Git:**
   - Secara default, Argo CD memeriksa remote Git setiap **3 menit** (`timeout.reconciliation = 180s`).
   - Setiap 3 menit, `repo-server` melakukan `git fetch`. Pada saat itu terjadi spike CPU kecil (~2–5 detik) lalu kembali tidur (idle 0%).

---

## 🛠️ Rekomendasi Resource Requests & Limits untuk Produksi

Jika Anda ingin menerapkan batasan kapasitas (*ResourceQuota* atau *Requests/Limits*) pada namespace `argocd`, berikut adalah rekomendasi standar industri:

### 1. Lingkungan Dev / Homelab / Small Cluster (< 25 Aplikasi)
*(Kapasitas yang sangat cukup untuk kebutuhan lab saat ini)*

```yaml
resources:
  argocd-application-controller:
    requests: { cpu: 100m, memory: 256Mi }
    limits:   { cpu: 500m, memory: 512Mi }
  argocd-server:
    requests: { cpu: 50m,  memory: 64Mi }
    limits:   { cpu: 200m, memory: 128Mi }
  argocd-repo-server:
    requests: { cpu: 50m,  memory: 128Mi }
    limits:   { cpu: 500m, memory: 256Mi }
  argocd-redis:
    requests: { cpu: 20m,  memory: 32Mi }
    limits:   { cpu: 100m, memory: 128Mi }
```
*Total alokasi request:* **~0.22 vCPU & ~480 MiB RAM**.

### 2. Lingkungan Produksi Menengah (50 – 200 Aplikasi)
- `argocd-application-controller`: Requests 500m CPU, 1Gi RAM; Limits 2 CPU, 2Gi RAM.
- `argocd-repo-server`: Scale horizontal ke 2-3 replika dengan HPA (Horizontal Pod Autoscaler).
- `argocd-redis`: Naikkan limit memory ke 512Mi.

---

## 💡 Tips Optimasi agar Argo CD Lebih Ringan Lagi

Jika Anda menjalankan Kubernetes pada node dengan memory sangat terbatas (misal VPS 2 GB RAM atau laptop dengan RAM terbatas):

1. **Gunakan Argo CD "Core" Mode (Headless):**
   - Jika Anda hanya butuh sinkronisasi otomatis GitOps dan tidak memerlukan Web UI Dashboard atau SSO:
   - Gunakan manifest `install-core.yaml`.
   - Pod `argocd-server` dan `argocd-dex-server` tidak diinstal.
   - **Footprint turun menjadi hanya ~140 MB RAM!**
2. **Matikan Notifikasi jika Belum Digunakan:**
   - Pod `argocd-notifications-controller` bisa di-scale ke `replicas: 0` jika Anda belum menghubungkannya ke Slack, Telegram, atau Discord.
   - Menghemat ~20 MB RAM.
3. **Gunakan Webhook GitHub daripada Interval Polling:**
   - Alih-alih membiarkan Argo CD melakukan `git fetch` setiap 3 menit, pasang Webhook dari GitHub ke endpoint Argo CD (`/api/webhook`).
   - Argo CD hanya akan bangun dan bekerja saat ada event push baru di GitHub. CPU idle akan mendekati 0.00%.

---

## 🎯 Kesimpulan

| Pertanyaan | Jawaban Realistis |
| :--- | :--- |
| **Apakah Argo CD memakan resource?** | Ya, sekitar **~235 MB RAM** dan **~0.06 core CPU**. |
| **Apakah tergolong berat?** | **Sama sekali tidak.** Argo CD adalah salah satu controller Kubernetes paling efisien di kelasnya. |
| **Apakah worth it dibanding manfaatnya?** | **Sangat worth it.** Dengan menukar ~235 MB RAM, Anda mendapatkan otomasi deployment, self-healing 24/7, audit trail Git, eliminasi risiko salah ketik command manual, dan visual dashboard kelas enterprise. |
