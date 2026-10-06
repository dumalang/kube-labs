# ⚖️ Analisis Mendalam: GitOps (Argo CD) vs Manual (Imperative Scripting)

Dokumen ini menyajikan perbandingan komprehensif antara pendekatan **Manual / Imperative Scripting** (yang digunakan pada cluster `k8s-microservices-lab`) dan pendekatan **Declarative GitOps via Argo CD** (yang digunakan pada cluster pembanding `k8s-argocd-lab`).

---

## 📑 Daftar Isi
1. [Ringkasan Eksekutif](#1-ringkasan-eksekutif)
2. [Tabel Komparasi Head-to-Head](#2-tabel-komparasi-head-to-head)
3. [Deep-Dive: 8 Dimensi Perbedaan Kritis](#3-deep-dive-8-dimensi-perbedaan-kritis)
   - [A. Paradigma & Delivery Model (Push vs Pull)](#a-paradigma--delivery-model-push-vs-pull)
   - [B. Source of Truth & Konsep "State"](#b-source-of-truth--konsep-state)
   - [C. Configuration Drift & Self-Healing](#c-configuration-drift--self-healing)
   - [D. Keamanan & Manajemen Kredensial](#d-keamanan--manajemen-kredensial)
   - [E. Rollback & Disaster Recovery](#e-rollback--disaster-recovery)
   - [F. Lifecycle & Penghapusan Resource (Pruning)](#f-lifecycle--penghapusan-resource-pruning)
   - [G. Audit Trail, Governance & Compliance](#g-audit-trail-governance--compliance)
   - [H. Developer Experience & Observability](#h-developer-experience--observability)
4. [Studi Kasus Nyata pada Lab Ini](#4-studi-kasus-nyata-pada-lab-ini)
5. [Kapan Memilih Manual vs Argo CD?](#5-kapan-memilih-manual-vs-argo-cd)
6. [Kesimpulan](#6-kesimpulan)

---

## 1. Ringkasan Eksekutif

Dalam siklus hidup operasional Kubernetes, perbedaan fundamental antara **Manual** dan **GitOps** terletak pada **siapa yang mengontrol cluster** dan **di mana kebenaran status aplikasi berada**:

- **Pendekatan Manual (`kubectl apply` / Shell Script):**
  Menggunakan paradigma *Imperative / Push*. Pengembang atau runner CI/CD mengeksekusi serangkaian instruksi ke Kubernetes API dari luar cluster. Jika kondisi cluster berubah di kemudian hari, sistem luar tidak mengetahui perubahannya.
- **Pendekatan GitOps (Argo CD):**
  Menggunakan paradigma *Declarative / Pull*. Sebuah agen di dalam cluster secara aktif memantau Git repository sebagai **Single Source of Truth**, membandingkannya dengan kondisi aktual di cluster, dan secara otomatis melakukan rekonsiliasi terus-menerus tanpa intervensi manual.

---

## 2. Tabel Komparasi Head-to-Head

| Parameter Evaluasi | 🛠️ Manual (`kubectl apply` / Shell Scripts) | 🐙 Declarative GitOps (Argo CD) |
| :--- | :--- | :--- |
| **Karakter Model** | **Push Model** (Klien mendorong perintah ke cluster) | **Pull Model** (Cluster menarik konfigurasi dari Git) |
| **Single Source of Truth** | Tidak pasti (Bisa file lokal, repo dev, atau konfigurasi live di etcd) | **Pasti Git Repository** (Branch tertentu yang disepakati) |
| **Drift Detection** | ❌ **Tidak ada** (Perubahan via `kubectl edit` tidak terdeteksi) | ✅ **Real-time** (Otomatis ditandai status `OutOfSync`) |
| **Self-Healing** | ❌ **Manual** (Jika Pod/Service dihapus orang, harus di-apply ulang manual) | ✅ **Otomatis** (Argo CD otomatis membuat ulang objek yang hilang) |
| **Akses & Keamanan Cluster** | ⚠️ **Tinggi Risiko** (Kredensial admin cluster harus ada di laptop dev / CI runner) | 🔒 **Sangat Aman** (Tidak ada kubeconfig cluster yang keluar; cluster yang fetch ke Git) |
| **Strategi Rollback** | ⏱️ Lambat & Rawan salah (Mencari file lama, re-run script apply) | ⚡ Instan (`git revert <hash>` atau 1-click Rollback di UI Argo CD) |
| **Resource Pruning (Pembersihan)** | ❌ **Tidak ada** (Jika file YAML dihapus dari folder, objek di cluster tetap hidup) | ✅ **Otomatis** (`prune: true` otomatis menghapus objek di cluster jika dihapus dari Git) |
| **Audit Trail & Compliance** | ⚠️ Terbatas pada K8s API audit log (Sulit melacak siapa & kenapa) | 📜 Sangat Jelas (Git commit history: author, time, commit message, PR review) |
| **Visualisasi Dependensi** | ❌ Bergantung CLI (`kubectl get ...`) atau tool pihak ketiga | ✅ Graph dependensi visual lengkap, status health pod, dan event stream bawaan |
| **Skalabilitas Multi-Cluster** | ⚠️ Butuh looping script bash yang rumit dan rawan timeout | ✅ Mengelola puluhan cluster dari 1 control plane Argo CD via ApplicationSet |

---

## 3. Deep-Dive: 8 Dimensi Perbedaan Kritis

### A. Paradigma & Delivery Model (Push vs Pull)

```
[ Pendekatan Manual (Push Model) ]
Developer Laptop / CI Runner  ──(kubectl apply)──▶  Kubernetes API (Port 6443)
(Membutuhkan Kubeconfig Admin)

[ Pendekatan GitOps (Pull Model) ]
Developer  ──(git push)──▶  Git Repository (GitHub)
                                   ▲
                                   │ (Argo CD Controller polling & sync)
                            Kubernetes Cluster (Internal Agent)
```

- **Manual (Push):** Perangkat eksternal harus memiliki rute jaringan langsung ke API Server Kubernetes (`6443`), serta menyimpan token akses sensitif. Jika koneksi terputus di tengah jalan, deployment bisa berakhir dalam status *partially applied*.
- **GitOps (Pull):** API Server Kubernetes tidak perlu dibuka ke publik. Argo CD yang berada di dalam cluster secara berkala mengambil (*pull*) manifest dari Git repository melalui protokol HTTPS/SSH standar.

---

### B. Source of Truth & Konsep "State"

- **Pada Setup Manual:**
  Bila seorang engineer mengubah environment variable langsung di cluster via `kubectl edit deployment service-a-nodejs`, state di cluster telah menyimpang dari file di laptop atau repository. Jika script `setup-cluster.sh` dijalankan ulang esok hari, perubahan tersebut bisa tertimpa tanpa disengaja.
- **Pada Argo CD:**
  Git adalah satu-satunya representasi sah dari sistem. Apapun yang tidak tercatat di Git dianggap ilegal atau *drift*. Jika ada perubahan yang ingin diterapkan ke cluster, developer **wajib** membuat commit di Git.

---

### C. Configuration Drift & Self-Healing

Apa yang terjadi saat seseorang tanpa sengaja menghapus Service atau Deployment di cluster?

```
Skenario: Operator tidak sengaja menjalankan 'kubectl delete svc service-b-golang'

[Cluster Manual]
- Service hilang.
- Aplikasi lain (service-a) gagal menghubungi service-b (502 Bad Gateway).
- Cluster tetap rusak sampai ada engineer yang sadar dan menjalankan 'kubectl apply'.

[Cluster Argo CD]
- Argo CD Controller mendeteksi status live != status Git (State: OutOfSync).
- Fitur Self-Heal langsung memicu rekonsiliasi.
- Dalam hitungan 2–5 detik, service-b-golang dibuat ulang secara otomatis.
- Sistem kembali normal tanpa perlu intervensi manusia di tengah malam.
```

---

### D. Keamanan & Manajemen Kredensial

1. **Prinsip Least Privilege:**
   - Pada cara manual, runner CI/CD (GitHub Actions/GitLab CI) membutuhkan akses *cluster-admin* ke Kubernetes. Jika runner diretas, seluruh cluster terancam.
   - Pada GitOps, CI runner hanya bertugas membangun image container dan memperbarui tag di file manifest Git. CI runner **sama sekali tidak memiliki akses** ke Kubernetes.
2. **Kredensial Zero-Expose:**
   - Akses cluster tetap berada di dalam perimeter privat (VPC/Firewall internal).

---

### E. Rollback & Disaster Recovery

- **Manual:**
  Rollback memerlukan pencarian commit image lama atau file YAML lama, lalu mengeksekusi `kubectl apply` manual atau `kubectl rollout undo`. Namun `rollout undo` tidak mengembalikan ConfigMap, Secret, atau Ingress yang terlanjur berubah.
- **GitOps:**
  Karena seluruh ekosistem (Deployment, Service, ConfigMap, Ingress, CronJob) tersimpan sebagai satu kesatuan snapshot di Git commit, melakukan rollback cukup dengan:
  ```bash
  git revert <bad-commit-hash>
  git push origin poc/argo-cd
  ```
  Argo CD akan mengembalikan **seluruh komponen secara serentak** ke kondisi stabil sebelumnya.

---

### F. Lifecycle & Penghapusan Resource (Pruning)

Salah satu masalah terbesar script manual seperti `kubectl apply -f k8s/` adalah **kebocoran resource yatim (orphaned resources)**:

- Jika Anda menghapus file `07-apm-service.yaml` dari repositori lokal karena layanannya sudah tidak dipakai:
  - `kubectl apply -f k8s/` **TIDAK AKAN** menghapus service `apm-server` yang sudah terlanjur ada di cluster.
  - Resource tersebut akan terus hidup di cluster tanpa ada yang merawatnya.
- Pada Argo CD:
  - Dengan mengaktifkan `syncPolicy.automated.prune: true`, saat file manifest dihapus dari Git, Argo CD akan **otomatis membersihkan dan menghapus objek tersebut dari cluster Kubernetes**.

---

### G. Audit Trail, Governance & Compliance

Bagi standar industri seperti **SOC 2, ISO 27001, atau PCI-DSS**:
- Pendekatan manual sulit diaudit: "Siapa yang menaikkan replika ke 10 kemarin sore?" Jawabannya terkubur di log audit Kubernetes yang rumit.
- Pada GitOps:
  - Siapa yang mengubah: `Author commit` & `Pull Request submitter`.
  - Siapa yang menyetujui: `PR Reviewer / Approver`.
  - Kapan disetujui: `Merge timestamp`.
  - Mengapa diubah: `Commit message & PR description`.
  Semua tercatat permanen di riwayat Git.

---

### H. Developer Experience & Observability

| Fitur | Manual | Argo CD Dashboard |
| :--- | :--- | :--- |
| **Health Status Pod** | Jalankan banyak perintah `kubectl get pods`, `kubectl describe pod ...` | Indikator visual hijau/kuning/merah dengan pesan error instan |
| **Log Streaming** | `kubectl logs -f <pod>` satu per satu | Tab log terintegrasi langsung di browser web |
| **Event Stream** | `kubectl get events` (sulit difilter) | Tab Events terisolasi per aplikasi |
| **Struktur Hubungan** | Harus membayangkan sendiri relasi Ingress ➜ Service ➜ Endpoints ➜ Pods | Visualisasi pohon hierarki (Resource Tree) interaktif secara grafis |

---

## 4. Studi Kasus Nyata pada Lab Ini

Berikut adalah contoh perbandingan nyata menggunakan repositori ini antara cluster **`k8s-microservices-lab`** dan **`k8s-argocd-lab`**:

### Kasus 1: Mengubah Replikasi `service-a-nodejs` dari 2 menjadi 4 Pod

#### Cara Manual (Cluster `k8s-microservices-lab`):
1. Buka file `k8s/01-service-a-nodejs.yaml`.
2. Ubah `replicas: 2` menjadi `replicas: 4`.
3. Buka terminal dan pastikan context aktif: `kubectl config use-context kind-k8s-microservices-lab`.
4. Jalankan: `kubectl apply -f k8s/01-service-a-nodejs.yaml`.
5. *Masalah:* Jika developer lain tidak pull perubahannya, file lokalnya tidak sinkron.

#### Cara GitOps (Cluster `k8s-argocd-lab`):
1. Buka file `argocd/apps/microservices/01-service-a-nodejs.yaml`.
2. Ubah `replicas: 2` menjadi `replicas: 4`.
3. Commit dan push:
   ```bash
   git commit -am "chore: scale service-a-nodejs to 4 replicas"
   git push origin poc/argo-cd
   ```
4. **Selesai.** Argo CD mendeteksi commit baru, melakukan sinkronisasi otomatis, dan pod bertambah menjadi 4 tanpa perlu menjalankan `kubectl` sama sekali!

---

### Kasus 2: Simulasi Kerusakan / Human Error (Pod Terhapus)

#### Uji Coba Langsung di Terminal:
```bash
# Pastikan berada di cluster Argo CD
kubectl config use-context kind-k8s-argocd-lab

# Hapus Deployment service-b-golang secara sengaja
kubectl delete deployment service-b-golang
```

- **Di Cluster Manual:** Deployment hilang selamanya sampai ada yang sadar dan apply ulang.
- **Di Cluster Argo CD:**
  Buka dashboard [http://localhost:8085](http://localhost:8085). Anda akan melihat status aplikasi `microservices-core` sejenak berwarna kuning (`OutOfSync`), lalu dalam 2–5 detik Argo CD memicu **Auto-Healing** dan membuat ulang Deployment `service-b-golang` secara otomatis!

---

## 5. Kapan Memilih Manual vs Argo CD?

```
                          ┌───────────────────────────┐
                          │ Apakah proyek masih tahap │
                          │ eksperimen lokal kilat?   │
                          └─────────────┬─────────────┘
                                        │
                         Ya ┌───────────┴───────────┐ Tidak
                            ▼                       ▼
               ┌───────────────────────┐ ┌─────────────────────────┐
               │ Gunakan Manual/Script │ │ Apakah digunakan untuk  │
               │ (Quick kubectl apply) │ │ tim/staging/production? │
               └───────────────────────┘ └───────────┬─────────────┘
                                                     │
                                                     ▼
                                         ┌───────────────────────┐
                                         │ Wajib Gunakan Argo CD │
                                         │ (GitOps Declarative)  │
                                         └───────────────────────┘
```

### ✅ Gunakan Manual / Shell Scripting Jika:
1. Sedang belajar dasar Kubernetes untuk pertama kali (memahami objek dasar Pod, Service, ReplicaSet).
2. Melakukan eksperimen sekali pakai (*scratchpad*) yang akan langsung dihancurkan dalam hitungan menit.
3. Menulis pengujian lokal terisolasi pada mesin dev tanpa koneksi remote Git.

### 🚀 Gunakan Argo CD (GitOps) Jika:
1. Bekerja dalam tim pengembang multi-anggota (menghindari saling timpa konfigurasi).
2. Lingkungan **Staging** dan **Production** yang menuntut ketersediaan tinggi (*Zero Downtime* & *Self-Healing*).
3. Membutuhkan standar audit kepatuhan (*compliance*) yang ketat (semua perubahan tercatat di Git).
4. Mengelola arsitektur Microservices dengan banyak komponen (Node.js, Go, Java, Batch, DB, Ingress).
5. Mengelola lebih dari satu cluster Kubernetes (Multi-Cluster / Hybrid-Cloud).

---

## 6. Kesimpulan

Meskipun pendekatan manual menggunakan script bash sederhana untuk dipelajari di awal, pendekatan tersebut memiliki batas skalabilitas yang sangat rapuh seiring bertambahnya kompleksitas layanan.

Pendekatan **Argo CD GitOps**:
1. Menjadikan **Git sebagai satu-satunya pengendali sistem**.
2. Memberikan jaminan **Self-Healing otomatis** terhadap kegagalan dan drift konfigurasi.
3. Meningkatkan **keamanan** dengan meniadakan kebutuhan menyebarkan kredensial admin cluster ke luar.
4. Memberikan **visibilitas menyeluruh** melalui Web UI kelas produksi.

Dengan tersedianya kedua cluster di lab ini:
- **`k8s-microservices-lab`** (Manual di port 80/443)
- **`k8s-argocd-lab`** (Argo CD GitOps di port 8080/8443/8085)

Anda memiliki perbandingan nyata secara langsung (*side-by-side comparison*) untuk menguji dan memahami evolusi dari otomasi tradisional menuju praktik modern **Cloud-Native GitOps**.
