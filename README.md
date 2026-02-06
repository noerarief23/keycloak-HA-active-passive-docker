# Keycloak High Availability - Active/Passive Architecture with PostgreSQL Streaming Replication

This repository provides a production-ready Active/Passive High Availability setup for Keycloak with PostgreSQL streaming replication using Docker.

## Architecture Overview

### Components

**Server A (Active/Primary):**
- Keycloak (Active) - Handles all authentication requests
- PostgreSQL Primary - Read/write database

**Server B (Passive/Standby):**
- Keycloak (Standby) - Stopped by default, activated during failover
- PostgreSQL Replica - Read-only replica with streaming replication

**Server C (Load Balancer) - Optional:**
- HAProxy - Load balancer and single entry point
- Automatic failover detection
- SSL/TLS termination
- Health monitoring and statistics

### Architecture Diagram

#### Without Load Balancer (Basic Setup)

```
┌─────────────────────────────────────────────────────────────────┐
│                         Server A (Active)                        │
│  ┌──────────────────┐              ┌─────────────────────────┐  │
│  │  Keycloak        │◄────────────►│  PostgreSQL Primary     │  │
│  │  (Active)        │              │  (Read/Write)           │  │
│  │  Port: 8080      │              │  Port: 5432             │  │
│  └──────────────────┘              └──────────┬──────────────┘  │
└────────────────────────────────────────────────┼─────────────────┘
                                                 │
                                    Streaming    │
                                    Replication  │
                                                 ▼
┌─────────────────────────────────────────────────────────────────┐
│                        Server B (Passive)                        │
│  ┌──────────────────┐              ┌─────────────────────────┐  │
│  │  Keycloak        │              │  PostgreSQL Replica     │  │
│  │  (Stopped)       │              │  (Read-Only)            │  │
│  │  Port: 8081      │              │  Port: 5433             │  │
│  └──────────────────┘              └─────────────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
```

#### With HAProxy Load Balancer (Recommended for Production)

```
                    Internet/Clients
                           │
                           ▼
                  ┌─────────────────┐
                  │   Server C      │
                  │   HAProxy       │
                  │                 │
                  │  HTTP: 80/443   │
                  │  PG: 5432       │
                  │  Stats: 8404    │
                  └────────┬────────┘
                           │
        ┌──────────────────┼──────────────────┐
        │                  │                  │
        ▼                  ▼                  ▼
┌───────────────┐  ┌───────────────┐  ┌──────────────┐
│  Server A     │  │  Server B     │  │ Automatic    │
│  (Primary)    │  │  (Replica)    │  │ Failover     │
│               │  │               │  │              │
│ Keycloak:8080 │  │ Keycloak:8081 │  │ ~15-20s      │
│ PostgreSQL    │  │ PostgreSQL    │  │ downtime     │
│ :5432         │  │ :5433         │  │              │
│               │  │               │  │ Zero manual  │
│ [ACTIVE]      │  │ [STANDBY]     │  │ intervention │
└───────┬───────┘  └───────┬───────┘  └──────────────┘
        │                  │
        └──────────────────┘
         Streaming Replication
```

## Features

- ✅ PostgreSQL Streaming Replication
- ✅ Automatic replication slot management
- ✅ WAL archiving for point-in-time recovery
- ✅ Health checks for all services
- ✅ Automated failover scripts
- ✅ Replication verification tools
- ✅ Production-ready configuration
- ✅ Network isolation with custom bridge networks
- ✅ HAProxy load balancer with automatic failover
- ✅ SSL/TLS termination and certificate management
- ✅ Built-in monitoring and statistics dashboard
- ✅ Prometheus metrics export

## Why Use HAProxy Load Balancer?

### Automatic Failover (Zero Manual Intervention)

HAProxy provides **automatic failover detection and switching** without any manual intervention:

**Without HAProxy:**
- Manual detection of primary failure
- Manual start of replica Keycloak: `docker compose --profile manual up -d keycloak-replica`
- Manual DNS update or load balancer reconfiguration
- Total downtime: **5-15 minutes** (depending on detection and response time)

**With HAProxy:**
- Automatic health check every 5 seconds
- Automatic failover after 3 failed checks (15 seconds)
- Zero manual intervention required
- Total downtime: **~15-20 seconds**

### How HAProxy Automatic Failover Works

```
Timeline of Automatic Failover:

Second 0:  Primary UP ✅ → Traffic flows to Primary
           |
Second 5:  Health check #1 FAIL ❌ → Still routing to Primary
           |
Second 10: Health check #2 FAIL ❌ → Still routing to Primary
           |
Second 15: Health check #3 FAIL ❌ → Primary marked DOWN 🔴
           |
           └──→ AUTOMATIC SWITCH to Replica ✅
           |
Second 20: All traffic now flows to Replica
```

### HAProxy Configuration for Automatic Failover

The automatic failover is configured in `haproxy/haproxy.cfg`:

```properties
backend keycloak_backend
    # Health check configuration
    option httpchk
    http-check connect port 9000              # Keycloak management port
    http-check send meth GET uri /health/ready
    http-check expect status 200
    
    # Primary server (active)
    server keycloak-primary keycloak-primary:8080 \
        check inter 5s fall 3 rise 2
    
    # Replica server (backup - only used when primary is down)
    server keycloak-replica keycloak-replica:8080 \
        check inter 5s fall 3 rise 2 backup
```

**Key Parameters:**
- `check` - Enable health checking
- `inter 5s` - Check every 5 seconds
- `fall 3` - Mark server DOWN after 3 consecutive failures (15 seconds)
- `rise 2` - Mark server UP after 2 consecutive successes (10 seconds)
- `backup` - Only use this server when all non-backup servers are down

### Additional HAProxy Benefits

1. **Single Entry Point**
   - One IP/hostname for clients
   - No DNS changes needed during failover
   - Simplified client configuration

2. **SSL/TLS Termination**
   - Centralized certificate management
   - Offload SSL processing from Keycloak
   - Automatic HTTP to HTTPS redirect

3. **Real-time Monitoring**
   - Stats dashboard at `http://haproxy-ip:8404/stats`
   - See server status (UP/DOWN) in real-time
   - Monitor health check results
   - Track failover events

4. **Load Distribution**
   - Round-robin load balancing (when both servers are up)
   - Automatic traffic redistribution during failover
   - Connection pooling and optimization

5. **PostgreSQL Failover**
   - Same automatic failover for PostgreSQL
   - Health checks every 3 seconds
   - Faster detection for database issues

### Comparison: With vs Without HAProxy

| Aspect | Without HAProxy | With HAProxy |
|--------|----------------|--------------|
| **Failover Detection** | Manual monitoring | Automatic (every 5s) |
| **Failover Time** | 5-15 minutes | 15-20 seconds |
| **Manual Steps** | 3-4 steps required | Zero |
| **DNS Changes** | Required | Not required |
| **Monitoring** | External tools needed | Built-in stats dashboard |
| **SSL Management** | Per-server | Centralized |
| **Client Config** | Must update after failover | No changes needed |
| **Downtime** | High | Minimal |

## Prerequisites

- Docker Engine 20.10+
- Docker Compose 2.0+
- Two servers (physical or virtual) for Active/Passive setup
- Optional: Third server for HAProxy load balancer (recommended for production)
- Network connectivity between servers
- Minimum 2GB RAM per server
- Minimum 20GB disk space per server

## Quick Start

### 1. Clone the Repository

```bash
git clone https://github.com/noerarief23/keycloak-HA-active-passive-docker.git
cd keycloak-HA-active-passive-docker
```

### 2. Configure Environment Variables

#### On Server A (Primary):

```bash
cp .env.primary.example .env
# Edit .env and set secure passwords
nano .env
```

#### On Server B (Replica):

```bash
cp .env.replica.example .env
# Edit .env and set the same passwords as Server A
# Update PRIMARY_SERVER_IP to Server A's IP address
nano .env
```

**Important:** All passwords must match between primary and replica servers.

### 3. Start Primary Server (Server A)

```bash
# On Server A
docker compose -f docker-compose-primary.yml up -d
```

Wait for all services to be healthy:

```bash
docker compose -f docker-compose-primary.yml ps
```

### 4. Start Replica Server (Server B)

```bash
# On Server B
docker compose -f docker-compose-replica.yml up -d postgres-replica
```

The replica will automatically:
1. Connect to the primary server
2. Perform a base backup
3. Start streaming replication

**Note:** Keycloak on the replica is NOT started automatically. It will only be started during failover. The replica uses Docker Compose profiles to prevent automatic startup:

```yaml
profiles:
  - manual  # Don't start automatically
```

To start Keycloak on replica during failover:
```bash
docker compose -f docker-compose-replica.yml --profile manual up -d keycloak-replica
```

### 5. Verify the Setup

#### Check health status:

```bash
./scripts/health-check.sh
```

#### Verify replication:

```bash
./scripts/verify-replication.sh
```

### 6. Deploy HAProxy Load Balancer (Optional but Recommended)

For production deployments, deploy HAProxy on Server C:

```bash
# On Server C
cp .env.lb.example .env
# Edit .env and configure:
# - HAPROXY_STATS_USER and HAPROXY_STATS_PASSWORD
# - PRIMARY_SERVER_IP (Server A IP address)
# - REPLICA_SERVER_IP (Server B IP address)
nano .env

# Deploy HAProxy
cd haproxy/scripts
./deploy-haproxy.sh
```

The deployment script will:
- Check prerequisites
- Generate SSL certificates (if needed)
- Validate configuration
- Start HAProxy container
- Verify health checks

Access HAProxy:
- **Keycloak:** https://server-c-ip/
- **PostgreSQL:** server-c-ip:5432
- **Stats Dashboard:** http://server-c-ip:8404/stats (see Best Practices → Monitoring for details)

For detailed HAProxy setup, see [HAPROXY.md](HAPROXY.md)

## Configuration Details

### PostgreSQL Replication Configuration

#### Primary Server Configuration

Key settings in `primary/postgres/config/postgresql.conf`:

```ini
wal_level = replica                 # Enable WAL for replication
max_wal_senders = 10               # Max concurrent replication connections
max_replication_slots = 10         # Max replication slots
wal_keep_size = 1GB                # Keep 1GB of WAL files
hot_standby = on                   # Allow read queries on standby
archive_mode = on                  # Enable WAL archiving
```

#### Replica Server Configuration

Key settings in `replica/postgres/config/postgresql.conf`:

```ini
hot_standby = on                   # Allow read-only queries
hot_standby_feedback = on          # Prevent query conflicts
primary_conninfo = '...'           # Connection to primary
primary_slot_name = 'replica_slot' # Replication slot name
```

### Replication User

A dedicated `replicator` user is created with `REPLICATION` privileges:

```sql
CREATE ROLE replicator WITH REPLICATION PASSWORD 'password' LOGIN;
```

### Health Check User

A dedicated `haproxy_check` user is created for HAProxy health checks:

```sql
CREATE USER haproxy_check WITH LOGIN;
```

### pg_hba.conf Configuration

Both servers allow replication connections from Docker networks:

```
host    replication     replicator      172.16.0.0/12           md5
host    replication     replicator      192.168.0.0/16          md5
```

### Keycloak Configuration

#### Environment Variables

- `KC_DB`: Database type (postgres)
- `KC_DB_URL`: JDBC connection string
- `KC_DB_USERNAME`: Database user (keycloak)
- `KC_DB_PASSWORD`: Database password
- `KC_HOSTNAME`: Public hostname
- `KC_HEALTH_ENABLED`: Enable health endpoints
- `KC_METRICS_ENABLED`: Enable metrics
- `KC_PROXY`: Proxy mode (edge for HAProxy)
- `KEYCLOAK_ADMIN`: Admin username
- `KEYCLOAK_ADMIN_PASSWORD`: Admin password

#### Docker Image

The project uses a custom Keycloak image built from `common/keycloak/Dockerfile`:
- Base image: `quay.io/keycloak/keycloak:26.5.2`
- Pre-built with PostgreSQL support
- Health and metrics enabled
- Optimized for production use

#### Health Checks

Both PostgreSQL and Keycloak have health checks configured:

**PostgreSQL:**
```yaml
healthcheck:
  test: ["CMD-SHELL", "pg_isready -U postgres"]
  interval: 10s
  timeout: 5s
  retries: 5
```

**Keycloak:**
```yaml
healthcheck:
  test: ["CMD-SHELL", "exec 3<>/dev/tcp/localhost/8080 && echo -e 'GET /health/ready HTTP/1.1\\r\\nHost: localhost\\r\\nConnection: close\\r\\n\\r\\n' >&3 && cat <&3 | grep -q '200 OK'"]
  interval: 30s
  timeout: 10s
  retries: 3
  start_period: 60s
```

## Monitoring and Maintenance

### Check Replication Status

On the primary server:

```bash
docker exec postgres-primary psql -U postgres -c "SELECT client_addr, state, sync_state FROM pg_stat_replication;"
```

Expected output:
```
 client_addr |   state   | sync_state 
-------------+-----------+------------
 172.20.0.20 | streaming | async
```

### Check Replication Lag

On the replica server:

```bash
docker exec postgres-replica psql -U postgres -c "SELECT EXTRACT(EPOCH FROM (now() - pg_last_xact_replay_timestamp())) AS replication_lag_seconds;"
```

A low value (< 1 second) indicates healthy replication.

### View Logs

**Primary logs:**
```bash
docker compose -f docker-compose-primary.yml logs -f
```

**Replica logs:**
```bash
docker compose -f docker-compose-replica.yml logs -f
```

## Failover Procedure

### When to Failover

Perform a failover when:
- Primary server hardware failure
- Primary server network failure
- Planned maintenance on primary server
- Primary server performance degradation

### Failover Steps

#### 1. Stop Primary Server (if possible)

```bash
# On Server A (if accessible)
docker compose -f docker-compose-primary.yml down
```

#### 2. Promote Replica to Primary

```bash
# On Server B
./scripts/promote-replica.sh
```

This script will:
1. Promote the PostgreSQL replica to primary
2. Start Keycloak on the new primary
3. Verify services are healthy

#### 3. Update DNS/Load Balancer

If using HAProxy:
- HAProxy will automatically detect the failover and route traffic to the new primary
- No manual DNS changes needed

If not using HAProxy:
- Update your DNS records to point to Server B
- Change A record or CNAME to Server B's IP
- Wait for DNS propagation (TTL dependent)

#### 4. Verify Failover

```bash
# On Server B
./scripts/health-check.sh
```

Access Keycloak at the new URL to verify functionality.

### Failback Procedure (Returning to Primary)

After the original primary is fixed:

1. **Rebuild the old primary as a replica:**
   - Clear the old primary's data
   - Reconfigure it as a replica of the current primary (former replica)
   - Perform base backup from new primary

2. **When ready to failback:**
   - Repeat the failover procedure in reverse
   - Promote the original primary
   - Update DNS/Load Balancer back to Server A

## Limitations and Considerations

### Session Loss

⚠️ **Important:** When failover occurs, all active user sessions will be lost because:
- Keycloak sessions are stored in the database
- The replica Keycloak instance was not running during active sessions
- Session state is not synchronized between Keycloak instances

**Impact:**
- Users will be logged out
- Users must log in again after failover
- Any in-progress authentication flows will be interrupted

**Mitigation strategies:**
- Use session affinity in load balancers (not helpful during failover)
- Implement short session timeouts
- Educate users about potential interruptions
- Consider upgrading to Active-Active clustering for session persistence

### Data Loss Window

- Asynchronous replication may result in minor data loss (seconds) if primary fails suddenly
- Use synchronous replication for zero data loss (impacts performance)

### Network Requirements

- Stable network connection between servers required
- High bandwidth recommended for large databases
- Low latency preferred for replication lag

### Capacity Planning

- Replica server should have same or better specs than primary
- Consider storage growth for WAL archiving
- Monitor disk space on both servers

## Best Practices

### Security

1. **Use strong passwords:**
   - Generate random passwords for all accounts
   - Store passwords in a secure vault (e.g., HashiCorp Vault)

2. **Enable SSL/TLS:**
   - Configure PostgreSQL to use SSL for replication
   - Configure Keycloak to use HTTPS
   - Use valid SSL certificates

3. **Network isolation:**
   - Use firewalls to restrict access
   - Allow only necessary ports between servers
   - Use VPN or private network for replication traffic

4. **Regular security updates:**
   - Keep Docker images updated
   - Monitor security advisories
   - Apply patches promptly

### Backup Strategy

1. **Regular backups:**
   ```bash
   # Backup primary database
   docker exec postgres-primary pg_dump -U postgres keycloak > backup-$(date +%Y%m%d).sql
   ```

2. **WAL archiving:**
   - Archive WAL files to external storage
   - Implement retention policies
   - Test restore procedures

3. **Backup verification:**
   - Regularly test restore procedures
   - Verify backup integrity
   - Document restore steps

### Monitoring

1. **Set up alerts for:**
   - Replication lag > threshold
   - Replication connection failures
   - Disk space low
   - Service health check failures
   - High CPU/memory usage
   - HAProxy backend failures (if using HAProxy)

2. **Monitor metrics:**
   - Database connections
   - Query performance
   - Replication throughput
   - Keycloak response times
   - HAProxy backend status and response times

3. **Log aggregation:**
   - Centralize logs from all servers
   - Set up log retention policies
   - Implement log analysis

4. **HAProxy monitoring (if deployed):**
   - **Stats Dashboard:** http://haproxy-ip:8404/stats
     - Current active server (Primary or Replica)
     - Health check status and failure count
     - Last status change timestamp
     - Traffic statistics per backend
     - Response times and error rates
   - **Prometheus Metrics:** http://haproxy-ip:8404/metrics
   - **Backend Health Check Script:** `./haproxy/scripts/check-backends.sh`
   - **Health Endpoint:** http://haproxy-ip:8404/health

### Testing

1. **Regular failover testing:**
   - Schedule quarterly failover drills
   - Document actual failover times
   - Identify and fix issues

2. **Load testing:**
   - Test system under expected load
   - Verify replica can handle promotion
   - Identify performance bottlenecks

3. **Disaster recovery testing:**
   - Test full restore from backups
   - Verify RTO/RPO targets
   - Update runbooks based on findings

## Troubleshooting

### Replication Not Working

**Symptoms:**
- No data on replica
- `pg_stat_replication` shows no connections

**Solutions:**
1. Check network connectivity between servers:
   ```bash
   # On Server B
   telnet <server-a-ip> 5432
   ```

2. Verify replication user credentials

3. Check `pg_hba.conf` allows replication connections

4. Review PostgreSQL logs:
   ```bash
   docker logs postgres-primary
   docker logs postgres-replica
   ```

### High Replication Lag

**Symptoms:**
- Replication lag > 10 seconds
- Replica falling behind

**Solutions:**
1. Check network bandwidth and latency

2. Review primary server load

3. Increase `wal_keep_size` if replica is catching up

4. Consider tuning `checkpoint_timeout` and `max_wal_size`

### Keycloak Connection Issues

**Symptoms:**
- Keycloak can't connect to database
- Health check failing

**Solutions:**
1. Verify database is running:
   ```bash
   docker ps | grep postgres
   ```

2. Check database credentials in `.env` file

3. Verify network connectivity:
   ```bash
   docker exec keycloak-primary ping postgres-primary
   ```

4. Review Keycloak logs:
   ```bash
   docker logs keycloak-primary
   ```

### Promotion Failed

**Symptoms:**
- Replica still in recovery mode after promotion
- `promote-replica.sh` reports failure

**Solutions:**
1. Manually create trigger file:
   ```bash
   docker exec postgres-replica touch /tmp/promote_trigger
   ```

2. Check PostgreSQL logs for errors

3. Verify replica was healthy before promotion

4. Restart PostgreSQL if needed:
   ```bash
   docker compose -f docker-compose-replica.yml restart postgres-replica
   ```

## Advanced Configuration

### Synchronous Replication

For zero data loss, enable synchronous replication:

**On primary (`postgresql.conf`):**
```ini
synchronous_commit = on
synchronous_standby_names = 'replica'
```

**Note:** This impacts performance as writes wait for replica acknowledgment.

### Multiple Replicas

To add more replicas:

1. Copy `docker-compose-replica.yml` to `docker-compose-replica2.yml`
2. Update IP addresses and ports
3. Use the same replication user and slot
4. Start the additional replica

### Network Configuration

#### Docker Networks

Both primary and replica use the same subnet (172.20.0.0/16) by design:
- This configuration assumes deployment on **separate physical servers**
- Each server has its own isolated Docker network
- If running both on the same host for testing, there will be network conflicts

**For single-host testing:**
- Use different subnets (e.g., 172.21.0.0/16 for replica)
- Or create a `docker-compose.override.yml` file
- Or use a shared Docker network

#### Cross-Server Communication

The replica uses `extra_hosts` to map the primary server:

```yaml
extra_hosts:
  - "postgres-primary:${PRIMARY_SERVER_IP}"
```

This allows the replica to connect to the primary server for replication. The `PRIMARY_SERVER_IP` must be set in the `.env` file to the actual IP address of Server A.

**Important:** For single-host testing, this `extra_hosts` entry may conflict with Docker's built-in DNS. Consider removing it via `docker-compose.override.yml` for local testing.

## Performance Tuning

### PostgreSQL

**For better performance:**
```ini
shared_buffers = 256MB
effective_cache_size = 1GB
maintenance_work_mem = 64MB
checkpoint_completion_target = 0.9
random_page_cost = 1.1
effective_io_concurrency = 200
work_mem = 4MB
```

### Keycloak

**Optimize JVM settings:**
```yaml
environment:
  - JAVA_OPTS=-Xms512m -Xmx1024m
```

## Support and Contribution

### Documentation

- **[README.md](README.md)** - Main documentation (this file)
- **[QUICKSTART.md](QUICKSTART.md)** - Quick start guide
- **[OPERATIONS.md](OPERATIONS.md)** - Operations and maintenance
- **[PRODUCTION-DEPLOYMENT.md](PRODUCTION-DEPLOYMENT.md)** - Production deployment guide
- **[HAPROXY.md](HAPROXY.md)** - HAProxy load balancer setup
- **[HAPROXY-TROUBLESHOOTING.md](HAPROXY-TROUBLESHOOTING.md)** - HAProxy troubleshooting
- **[haproxy/README.md](haproxy/README.md)** - HAProxy directory overview
- **[haproxy/TESTING-GUIDE.md](haproxy/TESTING-GUIDE.md)** - HAProxy testing procedures
- **[haproxy/QUICK-REFERENCE.md](haproxy/QUICK-REFERENCE.md)** - HAProxy command reference

### Scripts

**Core Scripts:**
- `scripts/health-check.sh` - Check health of all services
- `scripts/verify-replication.sh` - Verify replication is working
- `scripts/promote-replica.sh` - Promote replica to primary during failover

**HAProxy Scripts:**
- `haproxy/scripts/deploy-haproxy.sh` - Automated HAProxy deployment
- `haproxy/scripts/check-backends.sh` - Check backend server health
- `haproxy/scripts/validate-config.sh` - Validate HAProxy configuration
- `haproxy/scripts/generate-cert.sh` - Generate self-signed SSL certificates
- `haproxy/scripts/combine-cert.sh` - Combine SSL certificate and key
- `haproxy/scripts/test-failover.sh` - Test failover scenarios
- `haproxy/scripts/integration-test.sh` - Run integration tests
- `haproxy/scripts/load-test.sh` - Performance load testing
- `haproxy/scripts/rollback-haproxy.sh` - Rollback HAProxy configuration

### Issues

For bugs or feature requests, please open an issue on GitHub.

### Contributing

Contributions are welcome! Please:
1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Submit a pull request

## License

This project is provided as-is for educational and production use.

## References

- [PostgreSQL Streaming Replication Documentation](https://www.postgresql.org/docs/current/warm-standby.html)
- [Keycloak Documentation](https://www.keycloak.org/documentation)
- [Docker Compose Documentation](https://docs.docker.com/compose/)
- [PostgreSQL High Availability Best Practices](https://www.postgresql.org/docs/current/high-availability.html)
- [HAProxy Documentation](https://www.haproxy.com/documentation/)
- [HAProxy Configuration Manual](https://cbonte.github.io/haproxy-dconv/)

## Version History

- **v1.0.0** - Initial release with Active/Passive architecture
  - PostgreSQL 16 streaming replication
  - Keycloak 26.5.2
  - Docker Compose setup
  - Automated scripts for management and failover
  - HAProxy load balancer support
  - SSL/TLS termination
  - Comprehensive monitoring and health checks

---

**Note:** This setup is designed for production use but should be thoroughly tested in your environment before deployment. Always have a comprehensive backup and disaster recovery plan.