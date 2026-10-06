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

## ⚙️ Langkah 3: Konfigurasi Lingkungan (.env.tableau)

Semua konfigurasi (URL Tableau, Site Name, Pool ID, database MySQL host/port/IP, hingga PAT Secret) dikonfigurasi melalui satu file `.env.tableau` dan **tidak ada yang di-hardcode** di file YAML Kubernetes.

1. **Buat file `.env.tableau` dari template** (file ini otomatis diabaikan oleh Git via `.gitignore`):
   ```bash
   cp .env.tableau.example .env.tableau
   ```

2. **Lengkapi variabel di `.env.tableau`**:
   ```env
   # Tableau Cloud Configuration
   TABLEAU_SERVER_URL=https://prod-apsoutheast-c.online.tableau.com
   TABLEAU_SITE_NAME=your-tableau-site-name
   TABLEAU_USER_EMAIL=your-email@example.com
   POOL_ID=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
   CLIENT_NAME_PREFIX=k8s-local-mac

   # MySQL Database Target (Podman)
   MYSQL_HOST=mysql-podman-service
   MYSQL_PORT=3306
   MYSQL_PODMAN_IP=10.89.1.2

   # Tableau Bridge Authentication (PAT)
   PAT_NAME=tableau-bridge-k8s-token
   PAT_SECRET=YOUR_PAT_SECRET_TOKEN_HERE
   ```
   *(Catatan: Jangan gunakan tanda kutip pada value)*

---

## 🚀 Langkah 4: Deploy ke Kubernetes

Jalankan script otomatisasi setup (akan build image, push ke Kind, sync ConfigMap & Secret dari `.env.tableau`, apply Service & Deployment, lalu restart pod):

```bash
./scripts/setup-tableau-bridge.sh
```

Atau jika ingin apply manual via terminal:
```bash
# 1. Load variabel dan sync ConfigMap & Secret
set -a && source .env.tableau && set +a

kubectl create configmap tableau-bridge-config \
  --from-literal=TABLEAU_SERVER_URL="${TABLEAU_SERVER_URL}" \
  --from-literal=TABLEAU_SITE_NAME="${TABLEAU_SITE_NAME}" \
  --from-literal=TABLEAU_USER_EMAIL="${TABLEAU_USER_EMAIL}" \
  --from-literal=POOL_ID="${POOL_ID}" \
  --from-literal=CLIENT_NAME_PREFIX="${CLIENT_NAME_PREFIX}" \
  --from-literal=MYSQL_HOST="${MYSQL_HOST}" \
  --from-literal=MYSQL_PORT="${MYSQL_PORT}" \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl create secret generic tableau-bridge-secret \
  --from-literal=PAT_NAME="${PAT_NAME}" \
  --from-literal=PAT_SECRET="${PAT_SECRET}" \
  --dry-run=client -o yaml | kubectl apply -f -

# 2. Apply Manifest Kubernetes (Service & Deployment HA)
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
