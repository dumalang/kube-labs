# Setup Tableau Bridge High Availability (HA) di Kubernetes

Panduan ini berisi langkah-langkah implementasi **Tableau Bridge for Linux** di cluster Kubernetes dalam mode **High Availability (HA)** untuk menghubungkan **Tableau Cloud** dengan database **MySQL 8** (yang berjalan via Podman/Host).

---

## 💡 Konsep High Availability (HA) Tableau Bridge

Tableau Bridge tidak menggunakan skema Master-Worker/Active-Passive tradisional dengan leader election. Sebaliknya, Tableau Cloud menggunakan fitur **Bridge Pooling**:

1. **Pooling Load Balancing**: Ketika beberapa instansi/Pod Tableau Bridge terdaftar menggunakan **`POOL_ID`** yang sama di Tableau Cloud, Tableau Cloud secara otomatis mendistribusikan tugas *refresh extract* data ke seluruh Pod yang aktif di Pool tersebut.
2. **Automatic Failover**: Jika salah satu Pod di cluster Kubernetes mengalami *crash* atau *restart*, Tableau Cloud secara otomatis mengalihkan tugas yang tertunda ke Pod lain yang masih hidup di Pool tersebut.
3. **Kubernetes Deployment**: Kita menggunakan `Deployment` dengan `replicas: 2` (atau lebih) serta `podAntiAffinity` agar Pod didistribusikan ke Node fisik Kubernetes yang berbeda.

---

## 📂 Struktur File

- [`tableau-bridge/Dockerfile`](file:///Users/jimmy/Labs/tableau-bridge/Dockerfile): Build image Tableau Bridge Linux (UBI 8) + MySQL ODBC 8.0 Driver.
- [`tableau-bridge/entrypoint.sh`](file:///Users/jimmy/Labs/tableau-bridge/entrypoint.sh): Script inisialisasi & registrasi ke Tableau Cloud.
- [`tableau-bridge/odbcinst.ini`](file:///Users/jimmy/Labs/tableau-bridge/odbcinst.ini): Konfigurasi MySQL ODBC 8.0 Driver.
- [`k8s/08-tableau-bridge-ha.yaml`](file:///Users/jimmy/Labs/k8s/08-tableau-bridge-ha.yaml): Manifest Kubernetes (ConfigMap, Secret, Service/Endpoints MySQL Podman, Deployment HA).

---

## 🛠️ Langkah 1: Persiapan di Tableau Cloud

Sebelum deploy ke Kubernetes, siapkan kredensial berikut di Tableau Cloud:

1. **Personal Access Token (PAT)**:
   - Login ke Tableau Cloud.
   - Buka **My Account Settings** -> scroll ke **Personal Access Tokens**.
   - Buat Token Baru (misal: `tableau-bridge-k8s-token`).
   - Simpan **Token Name** dan **Token Secret** (Secret hanya ditampilkan 1x).

2. **Bridge Pool ID**:
   - Buka **Settings** -> **Bridge** di Tableau Cloud.
   - Buat atau pilih **Pool** (misal: `Production-MySQL-Pool`).
   - Salin **Pool ID** (UUID format `xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx`).

---

## 📦 Langkah 2: Build & Push Container Image

1. Unduh RPM Tableau Bridge untuk Linux versi terbaru dari [Tableau Downloads](https://www.tableau.com/support/downloads/bridge) dan letakkan file RPM tersebut di direktori `tableau-bridge/` (misal: `TableauBridge-2024.1.0-x86_64.rpm`).

2. Build Docker image:
   ```bash
   cd tableau-bridge
   docker build --build-arg TABLEAU_BRIDGE_RPM=TableauBridge-2024.1.0-x86_64.rpm -t your-registry/tableau-bridge:latest .
   ```

3. Push ke Container Registry Anda (atau load ke Kind/Minikube cluster):
   ```bash
   docker push your-registry/tableau-bridge:latest
   # Atau jika menggunakan Kind cluster lokal:
   # kind load docker-image your-registry/tableau-bridge:latest
   ```

---

## ⚙️ Langkah 3: Konfigurasi Manifest Kubernetes

Edit file [`k8s/08-tableau-bridge-ha.yaml`](file:///Users/jimmy/Labs/k8s/08-tableau-bridge-ha.yaml):

1. **ConfigMap (`tableau-bridge-config`)**:
   - `TABLEAU_SERVER_URL`: URL Pod Tableau Cloud Anda (contoh: `https://prod-ap-northeast-1.online.tableau.com`).
   - `TABLEAU_SITE_NAME`: Content URL Site Tableau Cloud Anda.
   - `POOL_ID`: Pool ID dari Langkah 1.

2. **Secret (`tableau-bridge-secret`)**:
   - `PAT_NAME`: Nama Token dari Langkah 1.
   - `PAT_SECRET`: Secret Value dari Langkah 1.

3. **Endpoints (`mysql-podman-service`)**:
   - Masukkan IP Host tempat Podman MySQL 8 Anda berjalan pada bagian `subsets.addresses[0].ip`.

---

## 🚀 Langkah 4: Deploy ke Kubernetes

Jalankan perintah berikut untuk mengaplikasikan konfigurasi ke cluster Kubernetes:

```bash
kubectl apply -f k8s/08-tableau-bridge-ha.yaml
```

Cek status Pod:
```bash
kubectl get pods -l app=tableau-bridge
```

Lihat log Pod untuk memastikan registrasi ke Tableau Cloud berhasil:
```bash
kubectl logs -f deployment/tableau-bridge --all-containers=true
```

---

## 🧪 Langkah 5: Verifikasi di Tableau Cloud & Koneksi MySQL 8

1. Masuk ke **Settings** -> **Bridge** di Tableau Cloud.
2. Anda akan melihat 2 client baru terdaftar di Pool (contoh: `k8s-bridge-ha-tableau-bridge-xxx-yyy`).
3. Di Tableau Desktop/Cloud Data Source, saat membuat koneksi ke MySQL 8:
   - Hostname: `mysql-podman-service` (atau IP host/domain internal)
   - Port: `3306`
   - Pilih opsi **"Keep data fresh with Tableau Bridge"** dan pilih Pool yang sudah dikonfigurasi.
