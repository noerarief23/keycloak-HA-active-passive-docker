# Failback Guide - Mengembalikan Primary PostgreSQL Setelah Failover

## Skenario

Anda telah melakukan failover karena primary PostgreSQL mati:
- **Server A (Primary)** - PostgreSQL mati, kemudian diperbaiki dan menyala kembali
- **Server B (Replica)** - Sudah dipromote menjadi primary baru

## Pertanyaan: Apa yang harus dilakukan setelah Server A menyala kembali?

## Pilihan 1: Biarkan Server B Sebagai Primary (REKOMENDASI) ⭐

### Kapan Menggunakan
- ✅ Production environment
- ✅ Ingin meminimalkan downtime
- ✅ Tidak masalah dengan role reversal

### Diagram Alur

```
SEBELUM FAILOVER:
┌─────────────┐ Replication  ┌─────────────┐
│  Server A   │─────────────→│  Server B   │
│  (Primary)  │              │  (Replica)  │
└─────────────┘              └─────────────┘

SETELAH FAILOVER (Server A mati):
┌─────────────┐              ┌─────────────┐
│  Server A   │              │  Server B   │
│  (DOWN) ❌  │              │  (Primary)  │
└─────────────┘              └─────────────┘

SERVER A MENYALA KEMBALI:
┌─────────────┐              ┌─────────────┐
│  Server A   │              │  Server B   │
│  (UP) ⚠️    │              │  (Primary)  │
│  No Role    │              │             │
└─────────────┘              └─────────────┘

SETELAH REBUILD (Option 1):
┌─────────────┐ Replication  ┌─────────────┐
│  Server A   │←─────────────│  Server B   │
│  (Replica)  │              │  (Primary)  │
└─────────────┘              └─────────────┘
     ↑                              ↑
   NEW ROLE                    NEW ROLE
```

### Langkah-Langkah

#### 1. Jalankan Script Rebuild
```bash
# Di Server A (old primary)
cd /path/to/keycloak-ha
./scripts/rebuild-as-replica.sh
```

Script akan:
- Stop semua services
- Backup data lama
- Hapus data PostgreSQL lama
- Update konfigurasi untuk menjadi replica
- Start PostgreSQL sebagai replica dari Server B

#### 2. Verifikasi Replication
```bash
# Di Server B (new primary)
docker exec postgres-replica psql -U postgres -c \
  "SELECT client_addr, state, sync_state FROM pg_stat_replication;"
```

Output yang diharapkan:
```
 client_addr  |   state   | sync_state 
--------------+-----------+------------
 <server-a-ip>  | streaming | async
```

#### 3. Update Dokumentasi
```bash
# Update catatan internal
echo "Server B is now PRIMARY" >> deployment-notes.txt
echo "Server A is now REPLICA" >> deployment-notes.txt
echo "Failover date: $(date)" >> deployment-notes.txt
```

### Keuntungan
- ✅ **Zero downtime** - Tidak ada service interruption
- ✅ **Cepat** - Selesai dalam 10-15 menit
- ✅ **Aman** - Tidak ada risiko data loss
- ✅ **Sederhana** - Hanya perlu rebuild satu server

### Kerugian
- ⚠️ **Role reversal** - Server A sekarang replica, Server B primary
- ⚠️ **Dokumentasi** - Perlu update dokumentasi dan naming

---

## Pilihan 2: Kembalikan Server A Sebagai Primary (KOMPLEKS)

### Kapan Menggunakan
- ⚠️ Testing/Development environment
- ⚠️ Perlu konsistensi role server
- ⚠️ Bisa terima downtime 5-15 menit

### Diagram Alur

```
KONDISI SAAT INI:
┌─────────────┐              ┌─────────────┐
│  Server A   │              │  Server B   │
│  (UP) ⚠️    │              │  (Primary)  │
│  No Role    │              │             │
└─────────────┘              └─────────────┘

STEP 1 - Rebuild A sebagai Replica:
┌─────────────┐ Replication  ┌─────────────┐
│  Server A   │←─────────────│  Server B   │
│  (Replica)  │              │  (Primary)  │
└─────────────┘              └─────────────┘

STEP 2 - Tunggu Sync Selesai:
┌─────────────┐ Lag: 0.5s    ┌─────────────┐
│  Server A   │←─────────────│  Server B   │
│  (Replica)  │   SYNCED ✅  │  (Primary)  │
└─────────────┘              └─────────────┘

STEP 3 - Maintenance Window (Stop Keycloak):
┌─────────────┐              ┌─────────────┐
│  Server A   │←─────────────│  Server B   │
│  Keycloak:  │              │  Keycloak:  │
│  STOPPED ⏸️ │              │  STOPPED ⏸️ │
└─────────────┘              └─────────────┘

STEP 4 - Promote Server A:
┌─────────────┐              ┌─────────────┐
│  Server A   │              │  Server B   │
│  (Primary)  │              │  (Replica)  │
│  PROMOTED ✅│              │  DEMOTED ⬇️ │
└─────────────┘              └─────────────┘

STEP 5 - Rebuild B sebagai Replica:
┌─────────────┐ Replication  ┌─────────────┐
│  Server A   │─────────────→│  Server B   │
│  (Primary)  │              │  (Replica)  │
└─────────────┘              └─────────────┘
     ↑                              ↑
ORIGINAL ROLE              ORIGINAL ROLE
```

### Langkah-Langkah Detail

#### Step 1: Rebuild Server A sebagai Replica
```bash
# Di Server A
./scripts/rebuild-as-replica.sh
# Input: Server B IP dan port
```

#### Step 2: Tunggu Replication Sync
```bash
# Di Server A - Monitor lag
watch -n 5 'docker exec postgres-replica psql -U postgres -t -c \
  "SELECT EXTRACT(EPOCH FROM (now() - pg_last_xact_replay_timestamp())) AS lag;"'

# Tunggu sampai lag < 1 detik
```

#### Step 3: Maintenance Window - Stop Keycloak
```bash
# Di Server A
docker compose -f docker-compose-primary.yml stop keycloak-replica

# Di Server B  
docker compose -f docker-compose-replica.yml stop keycloak-replica

# Informasikan users tentang maintenance
```

#### Step 4: Promote Server A
```bash
# Di Server A
./scripts/promote-replica.sh

# Verify
docker exec postgres-replica psql -U postgres -c "SELECT pg_is_in_recovery();"
# Output: f (false = primary)
```

#### Step 5: Rebuild Server B sebagai Replica
```bash
# Di Server B
./scripts/rebuild-as-replica.sh
# Input: Server A IP dan port (original primary)
```

#### Step 6: Start Keycloak Services
```bash
# Di Server A (now primary)
docker compose -f docker-compose-primary.yml start keycloak-primary

# Di Server B (now replica)
docker compose -f docker-compose-replica.yml start keycloak-replica

# Verify
./scripts/health-check.sh
```

#### Step 7: Verify Replication
```bash
# Di Server A (primary)
docker exec postgres-primary psql -U postgres -c \
  "SELECT client_addr, state FROM pg_stat_replication;"

# Should show Server B connected
```

### Keuntungan
- ✅ **Original roles restored** - Server A kembali jadi primary
- ✅ **Konsisten** - Sesuai dokumentasi awal

### Kerugian
- ❌ **Downtime** - 5-15 menit maintenance window
- ❌ **Kompleks** - Banyak langkah, risiko error lebih tinggi
- ❌ **Lama** - Total waktu 30-60 menit

---

## Perbandingan Pilihan

| Aspek | Option 1: Keep B as Primary | Option 2: Restore A as Primary |
|-------|----------------------------|-------------------------------|
| **Downtime** | 0 menit | 5-15 menit |
| **Kompleksitas** | Rendah | Tinggi |
| **Risiko** | Rendah | Medium |
| **Waktu Total** | 10-15 menit | 30-60 menit |
| **Manual Steps** | 3 langkah | 7 langkah |
| **Rollback** | Mudah | Sulit |
| **Production** | ✅ Recommended | ⚠️ Not Recommended |
| **Testing** | ✅ OK | ✅ OK |

---

## Rekomendasi Berdasarkan Environment

### Production Environment
**Gunakan Option 1** (Keep Server B as Primary)

Alasan:
- Zero downtime untuk users
- Risiko minimal
- Cepat dan sederhana
- Server B sudah terbukti stabil sebagai primary

### Testing/Development Environment
**Pilih sesuai kebutuhan:**
- **Option 1** jika ingin cepat dan aman
- **Option 2** jika ingin practice disaster recovery atau perlu konsistensi role

---

## Pencegahan Masalah di Masa Depan

### 1. Root Cause Analysis
Setelah failback, investigasi kenapa primary mati:
```bash
# Check system logs
journalctl -u docker -n 100

# Check PostgreSQL logs
docker logs postgres-primary --tail 100

# Check disk space
df -h

# Check memory
free -h
```

### 2. Monitoring Improvements
```bash
# Setup alerts untuk:
- Disk space < 20%
- Memory usage > 80%
- Replication lag > 10 seconds
- PostgreSQL connection errors
```

### 3. Regular Testing
```bash
# Schedule quarterly drills
# Practice both:
- Failover (Primary → Replica)
- Failback (Restore original roles)
```

### 4. Documentation
```bash
# Maintain current state documentation
cat > current-state.md << EOF
# Current PostgreSQL Configuration
- Primary: Server B (<server-b-ip>)
- Replica: Server A (<server-a-ip>)
- Last Failover: $(date)
- Reason: Primary PostgreSQL failure
EOF
```

---

## Troubleshooting

### Server A tidak bisa connect ke Server B
```bash
# Test connectivity
telnet <server-b-ip> 5432

# Check firewall
sudo ufw status

# Check PostgreSQL pg_hba.conf
docker exec postgres-primary cat /etc/postgresql/pg_hba.conf | grep replication
```

### Replication lag tinggi
```bash
# Check network bandwidth
iperf3 -c <server-b-ip>

# Check Server B load
ssh <server-b-ip> "top -bn1 | head -20"

# Increase wal_keep_size
# Edit postgresql.conf
wal_keep_size = 2GB
```

### Promote gagal
```bash
# Manual promote
docker exec postgres-replica pg_ctl promote -D /var/lib/postgresql/data/pgdata

# Check status
docker exec postgres-replica psql -U postgres -c "SELECT pg_is_in_recovery();"
```

---

## Kesimpulan

**Untuk Production: Gunakan Option 1** ⭐
- Paling aman dan cepat
- Zero downtime
- Recommended approach

**Untuk Testing: Pilih sesuai kebutuhan**
- Option 1: Cepat dan aman
- Option 2: Practice disaster recovery

**Yang Penting:**
- Dokumentasikan keputusan Anda
- Update monitoring dan alerts
- Test prosedur secara berkala
- Selalu backup sebelum perubahan besar
