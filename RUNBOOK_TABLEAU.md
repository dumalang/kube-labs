# 📘 Runbook Setup & Troubleshooting Tableau Bridge HA di Kubernetes

Runbook ini berisi panduan komprehensif langkah demi langkah (*step-by-step*) untuk mengonfigurasi dan mengoperasikan **Tableau Bridge for Linux** di cluster Kubernetes (Kind/Podman) dalam konfigurasi **High Availability (HA)** untuk menghubungkan database **MySQL 8** ke **Tableau Cloud**.

---

## ❓ Mengapa Tableau Bridge Belum Berjalan Sebelumnya?

Jika Pod Tableau Bridge mengalami status `Error` atau `CrashLoopBackOff`, hal ini disebabkan oleh 2 hal utama:

1. **Kredensial Dummy di Manifest Kubernetes**:
   File [`k8s/08-tableau-bridge-ha.yaml`](file:///Users/jimmy/Labs/k8s/08-tableau-bridge-ha.yaml) saat ini masih berisi variabel placeholder/dummy:
   - `TABLEAU_SERVER_URL`: `"https://prod-ap-northeast-1.online.tableau.com"`
   - `TABLEAU_SITE_NAME`: `"your-tableau-site-name"`
   - `TABLEAU_USER_EMAIL`: `"your-email@example.com"`
   - `POOL_ID`: `"00000000-0000-0000-0000-000000000000"`
   - `PAT_SECRET`: `"YOUR_PAT_SECRET_TOKEN_HERE"`

   Saat Tableau Bridge CLI (`TabBridgeClientCmd tokenLogin`) berjalan, ia mencoba otentikasi ke Tableau Cloud menggunakan kredensial dummy tersebut. Karena ditolak oleh Tableau Cloud, proses container langsung *exit*.

2. **IP Host MySQL Podman Masih Placeholder**:
   File `Endpoints` (`mysql-podman-service`) masih mengarah ke IP dummy `192.168.1.100`.

---

## 🛠️ Langkah Demi Langkah (Step-by-Step Runbook)

---

### Phase 1: Setup Di Luar Kubernetes (External Prerequisites)

#### 1. Dapatkan Kredensial dari Tableau Cloud Portal
Buka browser dan login ke **Tableau Cloud**:

1. **Buat Personal Access Token (PAT)**:
   - Masuk ke **My Account Settings** -> scroll ke bagian **Personal Access Tokens**.
   - Masukkan Token Name, contoh: `tableau-bridge-k8s-token`.
   - Klik **Create Token**.
   - ⚠️ **Catat & Simpan**:
     - **PAT Name**: `tableau-bridge-k8s-token`
     - **PAT Secret**: *(String acak yang hanya muncul 1x)*

2. **Dapatkan Pool ID (Untuk HA Load Balancing)**:
   - Buka menu **Settings** -> tab **Bridge**.
   - Buat Pool baru atau pilih Pool yang ada (misal: `MySQL-Production-Pool`).
   - Salin **Pool ID** (Format UUID: `xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx`).

3. **Catat Detail Site**:
   - **Server URL**: URL pod Tableau Cloud Anda (misal: `https://prod-ap-northeast-1.online.tableau.com` atau `https://online.tableau.com`).
   - **Site Name**: URL name site Tableau Cloud Anda (misal jika URL site Anda `https://online.tableau.com/#/site/mycompany/workbooks`, maka Site Name = `mycompany`).
   - **User Email**: Email akun Tableau Cloud Anda.

---

#### 2. Konfigurasi MySQL 8 di Podman

Pastikan container MySQL 8 yang berjalan via Podman dapat diakses dari dalam cluster Kubernetes:

1. **Cek IP Host / Gateway**:
   Di terminal Mac/Linux Anda, cek IP interface host:
   ```bash
   # Di macOS / Linux:
   ifconfig
   # Atau cek IP bridge podman:
   podman machine inspect
   ```
   *Catatan: Biasanya IP gateway Podman/Kind adalah IP internal host Anda di jaringan lokal (misal: `192.168.x.x` atau `10.88.0.1`).*

2. **Pastikan MySQL 8 mendengarkan port 3306**:
   Pastikan container Podman MySQL di-publish portnya (`-p 3306:3306`).

3. **Beri Akses User MySQL**:
   Masuk ke MySQL 8 dan pastikan user database diizinkan login dari subnet cluster:
   ```sql
   CREATE USER IF NOT EXISTS 'tableau_user'@'%' IDENTIFIED BY 'PasswordMySQLAnda';
   GRANT SELECT ON your_database.* TO 'tableau_user'@'%';
   FLUSH PRIVILEGES;
   ```

---

#### 3. Unduh File RPM Tableau Bridge for Linux
1. Unduh file RPM Tableau Bridge resmi untuk Linux dari [Tableau Downloads](https://www.tableau.com/support/downloads/bridge).
2. Simpan file RPM tersebut di folder `tableau-bridge/` pada project ini:
   ```text
   /Users/jimmy/Labs/tableau-bridge/TableauBridge-2024.1.0-x86_64.rpm
   ```

---

### Phase 2: Konfigurasi Manifest Kubernetes

Edit file [`k8s/08-tableau-bridge-ha.yaml`](file:///Users/jimmy/Labs/k8s/08-tableau-bridge-ha.yaml) dan sesuaikan dengan data asli dari **Phase 1**:

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: tableau-bridge-config
data:
  TABLEAU_SERVER_URL: "https://prod-ap-northeast-1.online.tableau.com" # Ganti dengan URL Cloud Anda
  TABLEAU_SITE_NAME: "site-anda"                                      # Ganti dengan Site Name Anda
  TABLEAU_USER_EMAIL: "email-anda@domain.com"                        # Ganti dengan User Email Anda
  POOL_ID: "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"                     # Ganti dengan Pool ID asli
  CLIENT_NAME_PREFIX: "k8s-bridge-ha"
  MYSQL_HOST: "mysql-podman-service"
  MYSQL_PORT: "3306"
---
apiVersion: v1
kind: Secret
metadata:
  name: tableau-bridge-secret
type: Opaque
stringData:
  PAT_NAME: "tableau-bridge-k8s-token"                                # Token Name dari Phase 1
  PAT_SECRET: "SECRET_PAT_TOKEN_ASLI_ANDA"                            # Token Secret dari Phase 1
---
apiVersion: v1
kind: Endpoints
metadata:
  name: mysql-podman-service
subsets:
  - addresses:
      - ip: "192.168.x.x"                                              # GANTI DENGAN IP HOST PODMAN MYSQL 8 ASLI
    ports:
      - name: mysql
        port: 3306
```

---

### Phase 3: Build & Deploy ke Kubernetes

Setelah file manifest diupdate dengan Kredensial Asli:

Jalankan script otomatisasi:
```bash
./scripts/setup-tableau-bridge.sh
```

Script ini akan:
1. Mem-build image container `localhost/tableau-bridge:latest` (platform `linux/amd64`).
2. Mengunduh & menginstall MySQL ODBC 8.0 Driver.
3. Memuat (*load*) image ke dalam cluster Kind (`k8s-microservices-lab`).
4. Mengaplikasikan manifest Kubernetes (`k8s/08-tableau-bridge-ha.yaml`).
5. Melakukan `rollout restart` pada deployment `tableau-bridge`.

---

## 🧪 Verifikasi & Monitoring Status

### 1. Cek Status Pod di Kubernetes
```bash
kubectl get pods -l app=tableau-bridge -o wide
```
*Output yang diharapkan:*
```text
NAME                              READY   STATUS    RESTARTS   AGE
tableau-bridge-xxxxxxxxxx-aaaaa   1/1     Running   0          1m
tableau-bridge-xxxxxxxxxx-bbbbb   1/1     Running   0          1m
```

### 2. Cek Log Registrasi ke Tableau Cloud
```bash
kubectl logs deployment/tableau-bridge -f
```
*Pesan sukses di log:*
> `Launching Tableau Bridge process via tokenLogin...`
> `Client connected to Tableau Cloud Site... Registered in Pool ID...`

### 3. Cek Status di Web Portal Tableau Cloud
1. Login ke Tableau Cloud -> **Settings** -> **Bridge**.
2. Di bagian Pool ID Anda, pastikan **2 Client** terdaftar dengan nama `k8s-bridge-ha-xxxx` dan berstatus **Connected / Green**.

---

## 🧹 Maintenance & Pembersihan Old Pods

Jika ada Pods lama yang bermasalah, Anda bisa membersihkannya secara bersih dengan perintah:

```bash
# Hapus ReplicaSet & Pods lama
kubectl delete rs -l app=tableau-bridge --cascade=foreground
kubectl delete pods -l app=tableau-bridge --grace-period=0 --force

# Restart deployment baru
kubectl rollout restart deployment/tableau-bridge
```
