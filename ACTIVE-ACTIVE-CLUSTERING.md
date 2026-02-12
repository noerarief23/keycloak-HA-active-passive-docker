# Active-Active Keycloak Clustering dengan Infinispan Cache Sync

## Overview

Dokumentasi ini menjelaskan cara upgrade dari Active-Passive ke Active-Active Keycloak clustering dengan Infinispan distributed cache.

---

## Perbandingan: Active-Passive vs Active-Active

Sebelum melakukan upgrade, pahami perbedaan fundamental antara kedua arsitektur:

### Arsitektur Keycloak

#### Active-Passive (Current Setup)
```
┌─────────────────┐
│  Keycloak       │
│  Primary        │
│  ✅ RUNNING     │  ← Hanya 1 yang aktif
│  Handle traffic │
└─────────────────┘

┌─────────────────┐
│  Keycloak       │
│  Replica        │
│  ⏸️ STOPPED     │  ← Standby, tidak running
│  No traffic     │
└─────────────────┘
```

**Karakteristik:**
- Hanya 1 Keycloak aktif pada satu waktu
- Replica di-stop, hanya start saat failover
- Cache: `KC_CACHE=local` (tidak shared)
- Resource: Hanya primary yang consume CPU/RAM

#### Active-Active (Target Setup)
```
┌─────────────────┐
│  Keycloak       │◄────┐
│  Primary        │     │ Infinispan
│  ✅ RUNNING     │     │ Cache Sync
│  Handle traffic │     │ Port 7800
└─────────────────┘     │
                        │
┌─────────────────┐     │
│  Keycloak       │◄────┘
│  Replica        │
│  ✅ RUNNING     │  ← Kedua aktif bersamaan
│  Handle traffic │
└─────────────────┘
```

**Karakteristik:**
- Kedua Keycloak aktif bersamaan
- Kedua handle traffic (load distribution)
- Cache: `KC_CACHE=ispn` (distributed cache)
- Resource: Kedua consume CPU/RAM

---

### Database Connection

#### Active-Passive
```
Keycloak Primary ──→ HAProxy ──→ PostgreSQL Primary ✅
                              ↓
Keycloak Replica     (stopped) PostgreSQL Replica (Standby)
```

**Database State:**
- PostgreSQL Primary: Read-Write ✅
- PostgreSQL Replica: Read-Only (Standby) ⏸️

#### Active-Active
```
Keycloak Primary ──┐
                   ├──→ HAProxy ──→ PostgreSQL Primary ✅
Keycloak Replica ──┘                (SHARED DATABASE)
                                    ↓
                                    PostgreSQL Replica (Standby)
```

**Database State:**
- PostgreSQL Primary: Read-Write ✅ (shared by both)
- PostgreSQL Replica: Read-Only (Standby) ⏸️

**Important:** Kedua Keycloak connect ke PostgreSQL Primary yang SAMA via HAProxy.

---

### Cache & Session Management

#### Active-Passive

**Configuration:**
```yaml
KC_CACHE=local
KC_CACHE_STACK=local
```

**Session Behavior:**
```
User Login → Primary Keycloak
           → Session stored in LOCAL cache
           → Session stored in database

Failover happens:
           → Replica Keycloak starts
           → Session NOT in cache (cache kosong)
           → User must re-login ❌
```

#### Active-Active

**Configuration:**
```yaml
KC_CACHE=ispn
KC_CACHE_STACK=tcp
JGROUPS_DISCOVERY_PROTOCOL=JDBC_PING
```

**Session Behavior:**
```
User Login → Primary Keycloak
           → Session stored in DISTRIBUTED cache
           → Infinispan sync to Replica
           → Session available on BOTH nodes ✅

Failover happens:
           → Traffic switch to Replica
           → Session ALREADY in cache
           → User stays logged in ✅
```

---

### Failover Comparison

#### Active-Passive Failover Timeline
```
t=0s:   Primary Keycloak DOWN
t=15s:  HAProxy detect failure
t=20s:  Auto-failover script detect
t=25s:  Script start Replica Keycloak
t=55s:  Replica ready, HAProxy route traffic

Total Downtime: ~55 seconds
Session Impact: ❌ All sessions lost, users must re-login
```

#### Active-Active Failover Timeline
```
t=0s:   Primary Keycloak DOWN
t=15s:  HAProxy detect failure
t=15s:  HAProxy route to Replica (already running)

Total Downtime: ~15 seconds
Session Impact: ✅ Sessions preserved, users stay logged in
```

---

### Resource Usage Comparison

| Resource | Active-Passive | Active-Active |
|----------|---------------|---------------|
| **Memory** | ~1-2 GB | ~3-5 GB |
| **CPU** | 10-30% | 30-80% |
| **Network** | Minimal | Moderate (cache sync) |
| **Disk I/O** | Low | Moderate |

---

### Complete Comparison Table

| Aspek | Active-Passive | Active-Active |
|-------|---------------|---------------|
| **Keycloak Instances** | 1 active, 1 stopped | 2 active |
| **Cache Type** | Local | Distributed (Infinispan) |
| **Cache Sync** | None | Automatic via JGroups |
| **Database Connection** | Via HAProxy | Via HAProxy (shared) |
| **PostgreSQL Replica** | Standby | Standby (same) |
| **Failover Time** | ~55 seconds | ~15 seconds |
| **Session Preservation** | ❌ Lost | ✅ Preserved |
| **Load Distribution** | No | Yes (50/50) |
| **Resource Usage** | Low (1-2 GB) | High (3-5 GB) |
| **Network Ports** | 3 ports | 4 ports (+7800) |
| **Setup Complexity** | Low (1-2 hours) | High (4-8 hours) |
| **Troubleshooting** | Easy | Difficult |
| **Maintenance** | Simple | Complex |
| **Cost** | Lower | Higher |
| **Scalability** | Vertical only | Horizontal |
| **Split-Brain Risk** | None | Possible |
| **Manual Intervention** | Some | Minimal (Keycloak) |
| **Best For** | Small-medium traffic | High traffic |
| **Downtime Tolerance** | 30-60 seconds OK | < 15 seconds required |

---

### When to Use Each Architecture

#### Use Active-Passive If:
- ✅ Traffic < 1000 concurrent users
- ✅ Downtime 30-60 seconds acceptable
- ✅ Budget terbatas
- ✅ Tim IT kecil/limited experience
- ✅ Infrastructure sederhana
- ✅ Session loss tidak masalah (users can re-login)

**Examples:**
- Internal company SSO
- Development/staging environments
- Small business applications
- Non-critical services

#### Use Active-Active If:
- ✅ Traffic > 5000 concurrent users
- ✅ Zero downtime critical (< 15 seconds)
- ✅ Session preservation required
- ✅ Budget cukup untuk resources
- ✅ Tim IT experienced dengan distributed systems
- ✅ 24/7 availability needed

**Examples:**
- Public-facing authentication
- E-commerce platforms
- Banking/financial services
- Healthcare systems
- SaaS applications

---

## Active-Active Architecture Details

## Active-Active Architecture Details

### Complete Architecture Diagram

```
                    Internet/Clients
                           │
                           ▼
                    ┌──────────────┐
                    │   HAProxy    │
                    │ (Round Robin)│
                    └──────┬───────┘
                           │
        ┌──────────────────┼──────────────────┐
        │                  │                  │
        ▼                  ▼                  ▼
┌───────────────┐  ┌───────────────┐  ┌───────────────┐
│  Keycloak     │◄─┼─────────────►│  │  Keycloak     │
│  Primary      │  │  Infinispan  │  │  Replica      │
│  (ACTIVE)     │  │  Cache Sync  │  │  (ACTIVE)     │
│               │  │  Port 7800   │  │               │
└───────┬───────┘  └───────────────┘  └───────┬───────┘
        │                                     │
        └──────────────────┬──────────────────┘
                           │
                           ▼
                    ┌──────────────┐
                    │   HAProxy    │
                    │  (Database)  │
                    └──────┬───────┘
                           │
                           ▼
                  ┌─────────────────┐
                  │  PostgreSQL     │
                  │  Primary        │
                  │  (Read-Write)   │
                  └────────┬────────┘
                           │ Streaming
                           ▼ Replication
                  ┌─────────────────┐
                  │  PostgreSQL     │
                  │  Replica        │
                  │  (Standby)      │
                  └─────────────────┘
```

### Benefits of Active-Active (Summary)

- ✅ **Zero downtime** - Seamless failover antar Keycloak instances (~15s vs ~55s)
- ✅ **Session preservation** - User tidak perlu re-login saat failover
- ✅ **Load distribution** - Traffic dibagi ke kedua instances (50/50)
- ✅ **High availability** - Jika satu instance down, yang lain langsung handle
- ✅ **Scalability** - Bisa tambah nodes sesuai kebutuhan (horizontal scaling)

### Drawbacks of Active-Active (Summary)

- ⚠️ **Complexity** - Setup dan troubleshooting lebih kompleks (4-8 hours vs 1-2 hours)
- ⚠️ **Resource usage** - Kedua Keycloak consume resources (3-5 GB vs 1-2 GB)
- ⚠️ **Network dependency** - Perlu koneksi stabil antar servers (port 7800)
- ⚠️ **Database bottleneck** - Semua write ke satu database (shared primary)
- ⚠️ **Higher cost** - Double resource consumption

---

## Decision Guide

**Should you upgrade to Active-Active?**

Answer these questions:

1. **Is your current downtime (55 seconds) unacceptable?**
   - No → Stay with Active-Passive
   - Yes → Consider Active-Active

2. **Do users complain about session loss during failover?**
   - No → Stay with Active-Passive
   - Yes → Consider Active-Active

3. **Do you have > 5000 concurrent users?**
   - No → Stay with Active-Passive
   - Yes → Consider Active-Active

4. **Do you have budget for 2x resources?**
   - No → Stay with Active-Passive
   - Yes → Consider Active-Active

5. **Do you have experienced IT team for distributed systems?**
   - No → Stay with Active-Passive
   - Yes → Consider Active-Active

**Recommendation:**
- If you answered "No" to 3+ questions → **Stay with Active-Passive**
- If you answered "Yes" to 4+ questions → **Upgrade to Active-Active**

---

## Prerequisites for Upgrade

### 1. Network Requirements

**Port yang Perlu Dibuka:**

```bash
# JGroups TCP (cluster communication)
Port 7800 (TCP) - Cluster communication

# Keycloak HTTP (existing)
Port 8080 (TCP) - HTTP endpoint
Port 9000 (TCP) - Management/health

# PostgreSQL (existing)
Port 5432/5434/5435 (TCP) - Database
```

**Firewall Configuration:**

Server A (Primary):
```bash
# Allow JGroups from Server B
sudo ufw allow from <server-b-ip> to any port 7800 proto tcp
```

Server B (Replica):
```bash
# Allow JGroups from Server A
sudo ufw allow from <server-a-ip> to any port 7800 proto tcp
```

### 2. DNS/Network Connectivity

Pastikan kedua server bisa resolve hostname:

```bash
# Test dari Server A
ping <server-b-ip>
telnet <server-b-ip> 7800

# Test dari Server B
ping <server-a-ip>
telnet <server-a-ip> 7800
```

### 3. Backup Current Setup

```bash
# Backup configurations
cp docker-compose-primary.yml docker-compose-primary.yml.backup-$(date +%Y%m%d)
cp docker-compose-replica.yml docker-compose-replica.yml.backup-$(date +%Y%m%d)
cp .env.primary .env.primary.backup-$(date +%Y%m%d)
cp .env.replica .env.replica.backup-$(date +%Y%m%d)

# Export database (optional)
docker exec postgres-primary pg_dump -U postgres keycloak > keycloak-backup-$(date +%Y%m%d).sql
```

---

## Step 1: Update Docker Compose - Primary

Edit `docker-compose-primary.yml`:

```yaml
version: '3.8'

services:
  postgres-primary:
    # ... existing config unchanged ...

  keycloak-primary:
    build:
      context: ./common/keycloak
      dockerfile: Dockerfile
    image: keycloak-ha-primary:26.5.2
    container_name: keycloak-primary
    hostname: keycloak-primary
    environment:
      # Database configuration (via HAProxy)
      - KC_DB=postgres
      - KC_DB_URL=jdbc:postgresql://${HAPROXY_SERVER_IP}:${HAPROXY_POSTGRES_PORT:-15434}/keycloak
      - KC_DB_USERNAME=keycloak
      - KC_DB_PASSWORD=${KEYCLOAK_DB_PASSWORD}
      
      # Hostname configuration
      - KC_HOSTNAME=${KC_HOSTNAME:-localhost}
      - KC_HOSTNAME_PORT=${KC_HOSTNAME_PORT:-8080}
      - KC_HOSTNAME_STRICT=${KC_HOSTNAME_STRICT:-false}
      - KC_HOSTNAME_STRICT_HTTPS=${KC_HOSTNAME_STRICT_HTTPS:-false}
      - KC_HTTP_ENABLED=true
      - KC_HEALTH_ENABLED=true
      - KC_METRICS_ENABLED=true
      - KC_PROXY=${KC_PROXY:-edge}
      - KC_PROXY_HEADERS=${KC_PROXY_HEADERS:-xforwarded}
      
      # CLUSTERING CONFIGURATION (NEW)
      - KC_CACHE=ispn
      - KC_CACHE_STACK=tcp
      
      # JGroups configuration
      - JGROUPS_DISCOVERY_PROTOCOL=JDBC_PING
      - JGROUPS_DISCOVERY_PROPERTIES=datasource_jndi_name=java:jboss/datasources/KeycloakDS,initialize_sql="CREATE TABLE IF NOT EXISTS JGROUPSPING (own_addr varchar(200) NOT NULL, cluster_name varchar(200) NOT NULL, ping_data BYTEA, constraint PK_JGROUPSPING PRIMARY KEY (own_addr, cluster_name))"
      
      # Network binding (IMPORTANT!)
      - JGROUPS_BIND_ADDRESS=0.0.0.0
      - JGROUPS_EXTERNAL_ADDRESS=${PRIMARY_SERVER_IP}
      
      # Admin credentials
      - KEYCLOAK_ADMIN=${KEYCLOAK_ADMIN:-admin}
      - KEYCLOAK_ADMIN_PASSWORD=${KEYCLOAK_ADMIN_PASSWORD}
      
      # JVM options
      - JAVA_OPTS_APPEND=-Djava.net.preferIPv4Stack=true -Djgroups.bind_addr=0.0.0.0
      
    command: start --optimized
    depends_on:
      postgres-primary:
        condition: service_healthy
    networks:
      keycloak-network:
        ipv4_address: 172.41.1.11
    ports:
      - "${KEYCLOAK_PRIMARY_HTTP_PORT:-8080}:8080"
      - "${KEYCLOAK_PRIMARY_MGMT_PORT:-9000}:9000"
      - "7800:7800"  # JGroups port (NEW)
    healthcheck:
      test: ["CMD-SHELL", "exec 3<>/dev/tcp/localhost/8080 && echo -e 'GET /health/ready HTTP/1.1\\r\\nHost: localhost\\r\\nConnection: close\\r\\n\\r\\n' >&3 && cat <&3 | grep -q '200 OK'"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 90s  # Increased for clustering startup

networks:
  keycloak-network:
    name: keycloak-network-primary
    driver: bridge
    ipam:
      config:
        - subnet: 172.41.1.0/24

volumes:
  postgres-primary-data:
    driver: local
  postgres-primary-archive:
    driver: local
```

---

## Step 2: Update Docker Compose - Replica

Edit `docker-compose-replica.yml`:

```yaml
version: '3.8'

services:
  postgres-replica:
    # ... existing config unchanged ...

  keycloak-replica:
    build:
      context: ./common/keycloak
      dockerfile: Dockerfile
    image: keycloak-ha-replica:26.5.2
    container_name: keycloak-replica
    hostname: keycloak-replica
    environment:
      # Database configuration (via HAProxy - SAME AS PRIMARY)
      - KC_DB=postgres
      - KC_DB_URL=jdbc:postgresql://${HAPROXY_SERVER_IP}:${HAPROXY_POSTGRES_PORT:-15434}/keycloak
      - KC_DB_USERNAME=keycloak
      - KC_DB_PASSWORD=${KEYCLOAK_DB_PASSWORD}
      
      # Hostname configuration (SAME AS PRIMARY)
      - KC_HOSTNAME=${KC_HOSTNAME:-localhost}
      - KC_HOSTNAME_PORT=${KC_HOSTNAME_PORT:-8080}
      - KC_HOSTNAME_STRICT=${KC_HOSTNAME_STRICT:-false}
      - KC_HOSTNAME_STRICT_HTTPS=${KC_HOSTNAME_STRICT_HTTPS:-false}
      - KC_HTTP_ENABLED=true
      - KC_HEALTH_ENABLED=true
      - KC_METRICS_ENABLED=true
      - KC_PROXY=${KC_PROXY:-edge}
      - KC_PROXY_HEADERS=${KC_PROXY_HEADERS:-xforwarded}
      
      # CLUSTERING CONFIGURATION (NEW - SAME AS PRIMARY)
      - KC_CACHE=ispn
      - KC_CACHE_STACK=tcp
      
      # JGroups configuration
      - JGROUPS_DISCOVERY_PROTOCOL=JDBC_PING
      - JGROUPS_DISCOVERY_PROPERTIES=datasource_jndi_name=java:jboss/datasources/KeycloakDS,initialize_sql="CREATE TABLE IF NOT EXISTS JGROUPSPING (own_addr varchar(200) NOT NULL, cluster_name varchar(200) NOT NULL, ping_data BYTEA, constraint PK_JGROUPSPING PRIMARY KEY (own_addr, cluster_name))"
      
      # Network binding (IMPORTANT! - Different IP)
      - JGROUPS_BIND_ADDRESS=0.0.0.0
      - JGROUPS_EXTERNAL_ADDRESS=${REPLICA_SERVER_IP}
      
      # Admin credentials
      - KEYCLOAK_ADMIN=${KEYCLOAK_ADMIN:-admin}
      - KEYCLOAK_ADMIN_PASSWORD=${KEYCLOAK_ADMIN_PASSWORD}
      
      # JVM options
      - JAVA_OPTS_APPEND=-Djava.net.preferIPv4Stack=true -Djgroups.bind_addr=0.0.0.0
      
    command: start --optimized
    depends_on:
      postgres-replica:
        condition: service_healthy
    networks:
      keycloak-network:
        ipv4_address: 172.41.10.21
    ports:
      - "${KEYCLOAK_REPLICA_HTTP_PORT:-8081}:8080"
      - "${KEYCLOAK_REPLICA_MGMT_PORT:-9001}:9000"
      - "7800:7800"  # JGroups port (NEW)
    healthcheck:
      test: ["CMD-SHELL", "exec 3<>/dev/tcp/localhost/8080 && echo -e 'GET /health/ready HTTP/1.1\\r\\nHost: localhost\\r\\nConnection: close\\r\\n\\r\\n' >&3 && cat <&3 | grep -q '200 OK'"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 90s  # Increased for clustering startup
    # REMOVE profiles - replica should start automatically now

networks:
  keycloak-network:
    name: keycloak-network-replica
    driver: bridge
    ipam:
      config:
        - subnet: 172.41.10.0/24

volumes:
  postgres-replica-data:
    driver: local
  postgres-replica-archive:
    driver: local
```

---

## Step 3: Update Environment Variables

### .env.primary

Add these variables:

```bash
# Existing variables...

# Clustering configuration (NEW)
PRIMARY_SERVER_IP=<server-a-ip>
REPLICA_SERVER_IP=<server-b-ip>

# HAProxy configuration (must be set)
HAPROXY_SERVER_IP=<haproxy-ip>
HAPROXY_POSTGRES_PORT=15434
```

### .env.replica

Add these variables:

```bash
# Existing variables...

# Clustering configuration (NEW)
PRIMARY_SERVER_IP=<server-a-ip>
REPLICA_SERVER_IP=<server-b-ip>

# HAProxy configuration (must be set - SAME AS PRIMARY)
HAPROXY_SERVER_IP=<haproxy-ip>
HAPROXY_POSTGRES_PORT=15434
```

---

## Step 4: Update HAProxy Configuration

Edit `haproxy/haproxy.cfg`:

```properties
#---------------------------------------------------------------------
# Backend: Keycloak (Active-Active with Round Robin)
#---------------------------------------------------------------------
backend keycloak_backend
    mode http
    balance roundrobin  # Changed from failover to load balancing
    
    # Health check configuration
    option httpchk
    http-check send meth GET uri /health/ready
    http-check expect status 200
    
    # Forwarding headers for Keycloak behind proxy
    http-request set-header X-Forwarded-Proto https
    http-request set-header X-Forwarded-Host %[req.hdr(Host)]
    http-request set-header X-Forwarded-Port ${HAPROXY_EXTERNAL_HTTPS_PORT}
    
    # Server definitions (BOTH ACTIVE - NO BACKUP)
    server keycloak-primary ${PRIMARY_SERVER_IP}:${PRIMARY_KEYCLOAK_PORT} check inter 5s fall 3 rise 2 addr ${PRIMARY_SERVER_IP} port ${PRIMARY_KEYCLOAK_MGMT_PORT}
    server keycloak-replica ${REPLICA_SERVER_IP}:${REPLICA_KEYCLOAK_PORT} check inter 5s fall 3 rise 2 addr ${REPLICA_SERVER_IP} port ${REPLICA_KEYCLOAK_MGMT_PORT}
    
    # Session stickiness (optional but recommended)
    cookie SERVERID insert indirect nocache
    server keycloak-primary ${PRIMARY_SERVER_IP}:${PRIMARY_KEYCLOAK_PORT} check inter 5s fall 3 rise 2 cookie primary addr ${PRIMARY_SERVER_IP} port ${PRIMARY_KEYCLOAK_MGMT_PORT}
    server keycloak-replica ${REPLICA_SERVER_IP}:${REPLICA_KEYCLOAK_PORT} check inter 5s fall 3 rise 2 cookie replica addr ${REPLICA_SERVER_IP} port ${REPLICA_KEYCLOAK_MGMT_PORT}
    
    # Connection settings
    option http-server-close
    option forwardfor
```

---

## Step 5: Deploy Active-Active Cluster

### 1. Stop Current Services

```bash
# Stop Keycloak instances
docker compose -f docker-compose-primary.yml stop keycloak-primary
docker compose -f docker-compose-replica.yml stop keycloak-replica

# PostgreSQL tetap running
```

### 2. Rebuild Keycloak Images (if needed)

```bash
# Rebuild dengan clustering support
docker compose -f docker-compose-primary.yml build keycloak-primary
docker compose -f docker-compose-replica.yml build keycloak-replica
```

### 3. Start Primary Keycloak

```bash
# Start primary first
docker compose -f docker-compose-primary.yml up -d keycloak-primary

# Wait for startup (90 seconds)
sleep 90

# Check logs
docker logs -f keycloak-primary
```

Look for:
```
INFO  [org.infinispan.CLUSTER] (main) ISPN000078: Starting JGroups channel keycloak
INFO  [org.jgroups.protocols.pbcast.GMS] (main) keycloak-primary: elected as coordinator
```

### 4. Start Replica Keycloak

```bash
# Start replica
docker compose -f docker-compose-replica.yml up -d keycloak-replica

# Wait for startup
sleep 90

# Check logs
docker logs -f keycloak-replica
```

Look for:
```
INFO  [org.jgroups.protocols.pbcast.GMS] (main) keycloak-replica: joined cluster keycloak
INFO  [org.infinispan.CLUSTER] (main) ISPN000094: Received new cluster view for channel keycloak: [keycloak-primary|1] (2) [keycloak-primary, keycloak-replica]
```

### 5. Restart HAProxy

```bash
docker compose -f docker-compose-lb.yml restart haproxy
```

---

## Step 6: Verify Clustering

### 1. Check Cluster Members

```bash
# Check primary logs
docker logs keycloak-primary 2>&1 | grep -i "cluster view"

# Expected output:
# Received new cluster view for channel keycloak: [keycloak-primary|1] (2) [keycloak-primary, keycloak-replica]
```

### 2. Check JGROUPSPING Table

```bash
# Via HAProxy
docker exec keycloak-primary psql -h ${HAPROXY_SERVER_IP} -p ${HAPROXY_POSTGRES_PORT} -U keycloak -d keycloak -c "SELECT own_addr, cluster_name FROM JGROUPSPING;"

# Expected output:
#     own_addr      | cluster_name
# ------------------+--------------
#  keycloak-primary | keycloak
#  keycloak-replica | keycloak
```

### 3. Test Cache Replication

```bash
# Create session on primary
curl -k https://<haproxy-ip>:10443/realms/master/protocol/openid-connect/auth?client_id=admin-cli&redirect_uri=http://localhost&response_type=code

# Check if session visible on replica
docker exec keycloak-replica /opt/keycloak/bin/kcadm.sh get sessions --realm master --server http://localhost:8080
```

### 4. Check HAProxy Stats

```bash
curl -u admin:<password> http://<haproxy-ip>:18404/stats

# Both keycloak-primary and keycloak-replica should show: UP
```

### 5. Test Failover

```bash
# Stop primary
docker stop keycloak-primary

# Test access (should still work via replica)
curl -k https://<haproxy-ip>:10443/health/ready

# Start primary again
docker start keycloak-primary

# Both should rejoin cluster
docker logs keycloak-primary 2>&1 | grep -i "joined"
```

---

## Troubleshooting

### Issue 1: Cluster Not Forming

**Symptoms:**
```
WARN  [org.jgroups] Failed to join cluster
```

**Solutions:**

1. **Check network connectivity:**
```bash
# From Server A
telnet <server-b-ip> 7800

# From Server B
telnet <server-a-ip> 7800
```

2. **Check firewall:**
```bash
sudo ufw status
sudo ufw allow from <other-server-ip> to any port 7800 proto tcp
```

3. **Check JGROUPS_EXTERNAL_ADDRESS:**
```bash
docker exec keycloak-primary env | grep JGROUPS
# Should show correct external IP
```

4. **Check JGROUPSPING table:**
```bash
docker exec keycloak-primary psql -h ${HAPROXY_SERVER_IP} -p ${HAPROXY_POSTGRES_PORT} -U keycloak -d keycloak -c "SELECT * FROM JGROUPSPING;"
```

### Issue 2: Split Brain

**Symptoms:**
```
Two separate clusters formed
```

**Solutions:**

1. **Stop both Keycloak instances:**
```bash
docker stop keycloak-primary keycloak-replica
```

2. **Clear JGROUPSPING table:**
```bash
docker exec postgres-primary psql -U keycloak -d keycloak -c "TRUNCATE TABLE JGROUPSPING;"
```

3. **Start primary first, then replica:**
```bash
docker start keycloak-primary
sleep 60
docker start keycloak-replica
```

### Issue 3: High Memory Usage

**Symptoms:**
```
Keycloak consuming > 2GB RAM
```

**Solutions:**

1. **Tune JVM heap:**
```yaml
environment:
  - JAVA_OPTS_APPEND=-Xms512m -Xmx1024m -Djava.net.preferIPv4Stack=true
```

2. **Tune Infinispan cache:**
```yaml
environment:
  - KC_CACHE_CONFIG_FILE=cache-ispn-jdbc-ping.xml
```

### Issue 4: Session Not Replicated

**Symptoms:**
```
User logged out after failover
```

**Solutions:**

1. **Check cluster view:**
```bash
docker logs keycloak-primary 2>&1 | grep "cluster view"
```

2. **Check cache configuration:**
```bash
docker exec keycloak-primary cat /opt/keycloak/conf/cache-ispn.xml
```

3. **Enable session replication logging:**
```yaml
environment:
  - KC_LOG_LEVEL=DEBUG,org.infinispan:DEBUG
```

---

## Performance Tuning

### 1. JVM Heap Size

```yaml
environment:
  - JAVA_OPTS_APPEND=-Xms1024m -Xmx2048m
```

### 2. Infinispan Cache Size

```yaml
environment:
  - KC_CACHE_CONFIG_FILE=cache-ispn-jdbc-ping.xml
  - CACHE_OWNERS_COUNT=2
  - CACHE_OWNERS_AUTH_SESSIONS_COUNT=2
```

### 3. JGroups Thread Pool

```yaml
environment:
  - JGROUPS_THREAD_POOL_MIN_THREADS=2
  - JGROUPS_THREAD_POOL_MAX_THREADS=20
```

### 4. Database Connection Pool

```yaml
environment:
  - KC_DB_POOL_INITIAL_SIZE=10
  - KC_DB_POOL_MIN_SIZE=10
  - KC_DB_POOL_MAX_SIZE=50
```

---

## Monitoring

### 1. Cluster Health

```bash
# Check cluster members
docker exec keycloak-primary /opt/keycloak/bin/kcadm.sh get serverinfo --server http://localhost:8080

# Check cache statistics
docker exec keycloak-primary /opt/keycloak/bin/kcadm.sh get cache-stats --server http://localhost:8080
```

### 2. Metrics

Enable Prometheus metrics:

```yaml
environment:
  - KC_METRICS_ENABLED=true
```

Access metrics:
```bash
curl http://<keycloak-ip>:9000/metrics
```

### 3. Logs

```bash
# Real-time cluster logs
docker logs -f keycloak-primary | grep -i "cluster\|jgroups\|infinispan"

# Check for errors
docker logs keycloak-primary 2>&1 | grep -i "error\|exception"
```

---

## Rollback to Active-Passive

If you need to rollback:

### 1. Stop Services

```bash
docker compose -f docker-compose-primary.yml stop keycloak-primary
docker compose -f docker-compose-replica.yml stop keycloak-replica
```

### 2. Restore Backup

```bash
cp docker-compose-primary.yml.backup-YYYYMMDD docker-compose-primary.yml
cp docker-compose-replica.yml.backup-YYYYMMDD docker-compose-replica.yml
cp .env.primary.backup-YYYYMMDD .env.primary
cp .env.replica.backup-YYYYMMDD .env.replica
```

### 3. Clear Clustering Data

```bash
docker exec postgres-primary psql -U keycloak -d keycloak -c "DROP TABLE IF EXISTS JGROUPSPING;"
```

### 4. Restart Services

```bash
docker compose -f docker-compose-primary.yml up -d keycloak-primary
# Replica stays stopped (Active-Passive)
```

---

## Best Practices

1. **Always start Primary first** - Establishes cluster coordinator
2. **Monitor cluster view** - Ensure both nodes see each other
3. **Test failover regularly** - Verify clustering works
4. **Keep configurations identical** - Except JGROUPS_EXTERNAL_ADDRESS
5. **Use session stickiness** - Reduces cache sync overhead
6. **Monitor memory usage** - Clustering increases memory consumption
7. **Backup before changes** - Easy rollback if issues occur
8. **Document your setup** - Note any custom configurations

---

## Summary

Active-Active clustering provides:
- ✅ Zero downtime failover (~15s vs ~55s)
- ✅ Session preservation (no re-login required)
- ✅ Load distribution (50/50 traffic split)
- ✅ High availability (automatic failover)

But requires:
- ⚠️ More complex setup (4-8 hours vs 1-2 hours)
- ⚠️ Higher resource usage (3-5 GB vs 1-2 GB)
- ⚠️ Network connectivity between servers (port 7800)
- ⚠️ Careful monitoring and maintenance

---

## Final Recommendation

### Stay with Active-Passive if:
Your current setup is working well and:
- Downtime of 30-60 seconds is acceptable
- Session loss during failover is not critical
- You have < 5000 concurrent users
- You prefer simpler infrastructure
- Budget is limited

**Active-Passive is production-ready and suitable for most use cases!**

### Upgrade to Active-Active if:
You have specific requirements:
- Zero downtime is critical (< 15 seconds)
- Session preservation is mandatory
- You have > 5000 concurrent users
- You need load distribution
- You have experienced IT team
- Budget allows for 2x resources

**Only upgrade if you have clear business requirements that justify the complexity.**

---

## Next Steps

### If Staying with Active-Passive:
- ✅ Your current setup is already optimal
- ✅ Continue monitoring and maintenance
- ✅ Test failover procedures regularly
- ✅ Keep documentation updated

### If Upgrading to Active-Active:
1. Review all prerequisites carefully
2. Test in staging environment first
3. Schedule maintenance window (4-8 hours)
4. Follow step-by-step guide above
5. Verify clustering thoroughly
6. Monitor for 24-48 hours post-upgrade
7. Keep rollback plan ready

---

## Support

For questions or issues:
- Review troubleshooting section above
- Check Keycloak logs for cluster errors
- Verify network connectivity (port 7800)
- Test with staging environment first
- Keep backup of Active-Passive config for rollback

**Remember:** Active-Passive is a proven, production-ready architecture. Only upgrade to Active-Active if you have specific business requirements that justify the additional complexity.
