# Troubleshooting Checklist

This checklist helps you quickly diagnose and resolve common issues with the Keycloak HA setup.

## Pre-Deployment Checklist

### Before Starting Primary Server

- [ ] Docker and Docker Compose are installed and up to date
- [ ] `.env` file exists (copied from `.env.primary.example`)
- [ ] All passwords in `.env` are set and secure
- [ ] Firewall allows incoming connections on port 5432 (for replication)
- [ ] Firewall allows incoming connections on port 8080 (for Keycloak)
- [ ] At least 2GB RAM available
- [ ] At least 20GB disk space available

### Before Starting Replica Server

- [ ] `.env` file exists (copied from `.env.replica.example`)
- [ ] All passwords match the primary server
- [ ] `PRIMARY_SERVER_IP` is set correctly
- [ ] Network connectivity to primary server verified (ping, telnet)
- [ ] Firewall allows outgoing connections to port 5432
- [ ] At least 2GB RAM available
- [ ] At least 20GB disk space available

## Issue: Primary Server Won't Start

### PostgreSQL Container Failing

**Check:**
```bash
docker logs postgres-primary
```

**Common causes:**

- [ ] Port 5432 already in use
  - Solution: `sudo lsof -i :5432` and stop conflicting service
  
- [ ] Invalid PostgreSQL configuration
  - Solution: Check `primary/postgres/config/postgresql.conf` syntax
  
- [ ] Permission issues on volumes
  - Solution: `sudo chown -R 999:999 volumes/postgres-primary-data/`
  
- [ ] Insufficient disk space
  - Solution: `df -h` and free up space

### Keycloak Container Failing

**Check:**
```bash
docker logs keycloak-primary
```

**Common causes:**

- [ ] Can't connect to database
  - Verify PostgreSQL is healthy: `docker ps | grep postgres-primary`
  - Check network: `docker exec keycloak-primary ping postgres-primary`
  
- [ ] Database credentials incorrect
  - Verify `.env` file has correct `KEYCLOAK_DB_PASSWORD`
  - Check it matches the password in init script
  
- [ ] Port 8080 already in use
  - Solution: Change port mapping in docker-compose-primary.yml

## Issue: Replica Server Won't Start

### Base Backup Fails

**Check:**
```bash
docker logs postgres-replica
```

**Common causes:**

- [ ] Can't connect to primary server
  - Test connectivity: `telnet PRIMARY_SERVER_IP 5432`
  - Check `PRIMARY_SERVER_IP` in `.env`
  - Verify firewall allows port 5432
  
- [ ] Replication password incorrect
  - Verify `REPLICATION_PASSWORD` matches primary
  - Check primary's pg_hba.conf allows replication
  
- [ ] Primary server not ready
  - Wait for primary to be fully healthy
  - Check: `docker exec postgres-primary pg_isready`

### Replication Not Working

**Check replication on primary:**
```bash
docker exec postgres-primary psql -U postgres -c "SELECT * FROM pg_stat_replication;"
```

**Common causes:**

- [ ] No replication connections shown
  - Verify replica is running
  - Check network connectivity
  - Review pg_hba.conf on primary
  
- [ ] Replication slot not created
  - Check: `docker exec postgres-primary psql -U postgres -c "SELECT * FROM pg_replication_slots;"`
  - Recreate if needed (see Primary init script)
  
- [ ] WAL files not being sent
  - Check primary's `wal_level` is set to `replica`
  - Verify `max_wal_senders` > 0

## Issue: High Replication Lag

**Check lag:**
```bash
docker exec postgres-replica psql -U postgres -c "SELECT EXTRACT(EPOCH FROM (now() - pg_last_xact_replay_timestamp())) AS lag_seconds;"
```

**Common causes:**

- [ ] Network latency between servers
  - Test: `ping PRIMARY_SERVER_IP`
  - Consider dedicated replication network
  
- [ ] High load on primary
  - Check CPU/memory: `docker stats postgres-primary`
  - Tune PostgreSQL parameters
  
- [ ] Slow disk I/O on replica
  - Check disk performance: `iostat -x 1`
  - Consider faster storage
  
- [ ] Insufficient WAL retention
  - Increase `wal_keep_size` in postgresql.conf
  - Monitor disk space

## Issue: Keycloak Can't Connect to Database

**Check Keycloak logs:**
```bash
docker logs keycloak-primary --tail 100
```

**Common causes:**

- [ ] Database not ready
  - Wait for database health check to pass
  - Check: `docker compose -f docker-compose-primary.yml ps`
  
- [ ] Wrong database URL
  - Verify `KC_DB_URL` in docker-compose file
  - Should be: `jdbc:postgresql://postgres-primary:5432/keycloak`
  
- [ ] Database user doesn't exist
  - Check init script ran: `docker logs postgres-primary | grep "keycloak"`
  - Manually create if needed
  
- [ ] Network isolation issue
  - Verify both containers on same network
  - Check: `docker network inspect keycloak-network`

## Issue: Failover Not Working

### Promotion Fails

**Check:**
```bash
docker exec postgres-replica psql -U postgres -c "SELECT pg_is_in_recovery();"
```

**If returns 't' (still in recovery):**

- [ ] Trigger file not created
  - Manually create: `docker exec postgres-replica touch /tmp/promote_trigger`
  
- [ ] PostgreSQL didn't detect trigger file
  - Restart container: `docker restart postgres-replica`
  - Check promote_trigger_file path in postgresql.conf
  
- [ ] Replication still connected
  - Stop primary first (if accessible)
  - Wait for replica to detect disconnection

### Keycloak Won't Start on Replica

**Common causes:**

- [ ] Database not promoted
  - Verify database is read-write (see above)
  
- [ ] Port conflict
  - Check port 8081 is available
  - `sudo lsof -i :8081`
  
- [ ] Profile not activated
  - Use: `docker compose --profile manual up -d keycloak-replica`

## Issue: Performance Problems

### Slow Keycloak Response

**Check:**
```bash
docker stats keycloak-primary
```

**Common causes:**

- [ ] Insufficient memory
  - Increase container memory limit
  - Tune JVM heap size (JAVA_OPTS)
  
- [ ] Database connection pool exhausted
  - Increase max_connections in PostgreSQL
  - Tune Keycloak connection pool
  
- [ ] Slow database queries
  - Check PostgreSQL slow query log
  - Add database indexes if needed

### Slow Replication

**Check network:**
```bash
iperf3 -s  # on primary
iperf3 -c PRIMARY_IP  # on replica
```

**Common causes:**

- [ ] Network bandwidth saturated
  - Consider dedicated replication network
  - Implement network QoS
  
- [ ] Large transactions
  - Break large data loads into smaller batches
  - Tune checkpoint settings

## Issue: Data Inconsistency

### Data Not Appearing on Replica

**Verify replication:**
```bash
./scripts/verify-replication.sh
```

**Common causes:**

- [ ] Replication stopped
  - Check `pg_stat_replication` on primary
  - Review logs for errors
  
- [ ] Replication lag too high
  - See "High Replication Lag" section above
  
- [ ] Replication slot dropped
  - Recreate replication slot
  - May need to reinitialize replica

## Issue: Disk Space Full

**Check disk usage:**
```bash
df -h
docker system df
```

**Solutions:**

- [ ] Clean up old WAL files
  - Verify archiving is working
  - Increase `wal_keep_size` if needed
  
- [ ] Clean up Docker resources
  ```bash
  docker system prune -a --volumes
  ```
  **WARNING:** Only do this if you have backups!
  
- [ ] Resize volumes
  - Expand underlying storage
  - Resize filesystem

## Issue: Can't Access Keycloak Admin Console

**Common causes:**

- [ ] Wrong URL
  - Primary: `http://SERVER_IP:8080/admin`
  - Replica: `http://SERVER_IP:8081/admin`
  
- [ ] Service not ready
  - Check health: `curl http://localhost:8080/health/ready`
  - Wait for startup (can take 60+ seconds)
  
- [ ] Firewall blocking
  - Allow port 8080/8081 in firewall
  - Check: `sudo ufw status`
  
- [ ] Wrong credentials
  - Check `KEYCLOAK_ADMIN` and `KEYCLOAK_ADMIN_PASSWORD` in `.env`

## Monitoring Commands

### Quick Health Check
```bash
./scripts/health-check.sh
```

### Detailed Status
```bash
# All containers
docker ps -a

# Logs for primary
docker compose -f docker-compose-primary.yml logs -f

# Logs for replica
docker compose -f docker-compose-replica.yml logs -f

# Resource usage
docker stats

# Network info
docker network inspect keycloak-network
```

### Database Queries

**Replication status on primary:**
```sql
SELECT client_addr, state, sync_state, replay_lag 
FROM pg_stat_replication;
```

**Recovery status on replica:**
```sql
SELECT pg_is_in_recovery(), 
       pg_last_wal_receive_lsn(), 
       pg_last_wal_replay_lsn();
```

**Database size:**
```sql
SELECT pg_size_pretty(pg_database_size('keycloak'));
```

## When to Seek Help

If you've gone through this checklist and still have issues:

1. Collect all relevant logs
2. Document steps to reproduce
3. Note your environment (OS, Docker version, etc.)
4. Open an issue on GitHub with details

## Emergency Recovery

### Complete Reset (DESTRUCTIVE)

**WARNING:** This will delete all data!

```bash
# Stop everything
docker compose -f docker-compose-primary.yml down -v
docker compose -f docker-compose-replica.yml down -v

# Remove volumes
docker volume rm $(docker volume ls -q | grep postgres)

# Start fresh
docker compose -f docker-compose-primary.yml up -d
# Wait for primary to be ready
docker compose -f docker-compose-replica.yml up -d postgres-replica
```

### Restore from Backup

```bash
# Stop Keycloak
docker stop keycloak-primary

# Restore database
docker exec -i postgres-primary psql -U postgres keycloak < backup.sql

# Start Keycloak
docker start keycloak-primary
```
