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
│  Server A     │  │  Server B     │  │ Health       │
│  (Primary)    │  │  (Replica)    │  │ Checks       │
│               │  │               │  │              │
│ Keycloak:8080 │  │ Keycloak:8081 │  │ Every 5s     │
│ PostgreSQL    │  │ PostgreSQL    │  │ (Keycloak)   │
│ :5432         │  │ :5433         │  │              │
│               │  │               │  │ Every 3s     │
│ [ACTIVE]      │  │ [STANDBY]     │  │ (PostgreSQL) │
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

## Prerequisites

- Docker Engine 20.10+
- Docker Compose 2.0+
- Two servers (physical or virtual) for Active/Passive setup
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

**Note:** Keycloak on the replica is NOT started automatically. It will only be started during failover.

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
- **Stats Page:** http://server-c-ip:8404/stats
- **Keycloak:** https://server-c-ip/
- **PostgreSQL:** server-c-ip:5432

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
  test: ["CMD-SHELL", "curl -sf http://localhost:8080/health/ready"]
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

Update your DNS records or load balancer to point to Server B:
- Change A record or CNAME to Server B's IP
- Update load balancer backend to Server B

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

2. **Monitor metrics:**
   - Database connections
   - Query performance
   - Replication throughput
   - Keycloak response times

3. **Log aggregation:**
   - Centralize logs from both servers
   - Set up log retention policies
   - Implement log analysis

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

### Custom Network Configuration

Modify the network settings in docker-compose files:

```yaml
networks:
  keycloak-network:
    driver: bridge
    ipam:
      config:
        - subnet: 10.10.0.0/16
```

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

## Version History

- **v1.0.0** - Initial release with Active/Passive architecture
  - PostgreSQL 15 streaming replication
  - Keycloak 23.0
  - Docker Compose setup
  - Automated scripts for management and failover

---

**Note:** This setup is designed for production use but should be thoroughly tested in your environment before deployment. Always have a comprehensive backup and disaster recovery plan.