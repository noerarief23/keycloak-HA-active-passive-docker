# Operations and Maintenance Guide

This guide covers routine operations, maintenance tasks, and best practices for running the Keycloak HA setup in production.

## Daily Operations

### Morning Health Check (5 minutes)

```bash
# Run automated health check
./scripts/health-check.sh

# Check HAProxy backend status (if using HAProxy)
./haproxy/scripts/check-backends.sh

# Check replication lag
docker exec postgres-replica psql -U postgres -c \
  "SELECT EXTRACT(EPOCH FROM (now() - pg_last_xact_replay_timestamp())) AS lag_seconds;"

# Verify replication is active
docker exec postgres-primary psql -U postgres -c \
  "SELECT client_addr, state, sync_state FROM pg_stat_replication;"

# Check disk space
df -h

# Check Docker resources
docker system df
```

Expected results:
- Health check shows all services running and healthy
- HAProxy shows all backends UP (if deployed)
- Replication lag < 5 seconds
- Replication state = "streaming"
- Disk usage < 80%

## Weekly Maintenance

### Database Backup (15 minutes)

**Automated backup script:**

```bash
#!/bin/bash
# backup-database.sh
BACKUP_DIR="/backups/postgresql"
DATE=$(date +%Y%m%d_%H%M%S)
BACKUP_FILE="$BACKUP_DIR/keycloak_backup_$DATE.sql"

mkdir -p $BACKUP_DIR

# Backup from primary (custom format already includes compression)
docker exec postgres-primary pg_dump -U postgres -Fc keycloak > $BACKUP_FILE

# Keep only last 30 days
find $BACKUP_DIR -name "*.sql" -mtime +30 -delete

echo "Backup completed: ${BACKUP_FILE}"
```

**Test restore:**

```bash
# On a test database
gunzip -c backup.sql.gz | docker exec -i postgres-primary psql -U postgres -d test_db
```

### Log Review (10 minutes)

```bash
# Check for errors in last 7 days
docker logs postgres-primary --since 7d | grep -i error
docker logs postgres-replica --since 7d | grep -i error
docker logs keycloak-primary --since 7d | grep -i error

# Check for WARNING messages
docker logs postgres-primary --since 7d | grep -i warning
docker logs keycloak-primary --since 7d | grep -i warning
```

### Performance Review (10 minutes)

```bash
# Database connection statistics
docker exec postgres-primary psql -U postgres -c \
  "SELECT datname, numbackends, xact_commit, xact_rollback, blks_read, blks_hit 
   FROM pg_stat_database WHERE datname = 'keycloak';"

# Top queries by total time (requires pg_stat_statements extension)
# To enable: Add 'shared_preload_libraries = pg_stat_statements' to postgresql.conf
# and run 'CREATE EXTENSION pg_stat_statements;' in the database
# docker exec postgres-primary psql -U postgres -c \
#   "SELECT query, calls, total_exec_time, mean_exec_time 
#    FROM pg_stat_statements 
#    ORDER BY total_exec_time DESC LIMIT 10;"

# Table sizes
docker exec postgres-primary psql -U postgres -c \
  "SELECT schemaname, tablename, pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename)) AS size 
   FROM pg_tables 
   WHERE schemaname = 'public' 
   ORDER BY pg_total_relation_size(schemaname||'.'||tablename) DESC LIMIT 10;"
```

### Replication Verification (5 minutes)

```bash
# Run automated verification
./scripts/verify-replication.sh

# Manual verification - create test data
TEST_ID=$(uuidgen)
docker exec postgres-primary psql -U postgres -c \
  "CREATE TABLE IF NOT EXISTS health_check (id TEXT, created_at TIMESTAMP DEFAULT NOW()); 
   INSERT INTO health_check (id) VALUES ('$TEST_ID');"

# Wait for replication
sleep 5

# Verify on replica
docker exec postgres-replica psql -U postgres -c \
  "SELECT * FROM health_check WHERE id = '$TEST_ID';"

# Cleanup
docker exec postgres-primary psql -U postgres -c \
  "DROP TABLE health_check;"
```

### HAProxy Maintenance (5 minutes)

If using HAProxy load balancer:

```bash
# Check HAProxy stats
curl -u admin:password http://haproxy-ip:8404/stats

# View HAProxy logs
docker logs haproxy-lb --tail 100

# Check SSL certificate expiration
openssl x509 -in haproxy/certs/keycloak.pem -noout -enddate

# Validate configuration
docker run --rm -v $(pwd)/haproxy:/usr/local/etc/haproxy:ro \
  haproxy:2.9-alpine haproxy -c -f /usr/local/etc/haproxy/haproxy.cfg
```

## Monthly Maintenance

### Update Docker Images (30 minutes)

**Always test in non-production first!**

```bash
# Pull latest images
docker compose -f docker-compose-primary.yml pull
docker compose -f docker-compose-replica.yml pull

# If using HAProxy
docker compose -f docker-compose-lb.yml pull

# Backup before updating
./backup-database.sh

# Update HAProxy first (minimal downtime)
docker compose -f docker-compose-lb.yml up -d

# Update primary (requires downtime)
docker compose -f docker-compose-primary.yml up -d

# Wait and verify
sleep 60
./scripts/health-check.sh

# Update replica
docker compose -f docker-compose-replica.yml up -d postgres-replica
```

### Database Maintenance (20 minutes)

```bash
# Vacuum and analyze (run during low traffic)
docker exec postgres-primary psql -U postgres -c "VACUUM ANALYZE;"

# Check for bloat
docker exec postgres-primary psql -U postgres -c \
  "SELECT schemaname, tablename, 
          pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename)) as total_size,
          pg_size_pretty(pg_relation_size(schemaname||'.'||tablename)) as table_size
   FROM pg_tables 
   WHERE schemaname = 'public' 
   ORDER BY pg_total_relation_size(schemaname||'.'||tablename) DESC;"

# Reindex if needed (during maintenance window)
docker exec postgres-primary psql -U postgres -c "REINDEX DATABASE keycloak;"
```

### Security Updates

```bash
# Check for security advisories
# PostgreSQL: https://www.postgresql.org/support/security/
# Keycloak: https://www.keycloak.org/security

# Update system packages
sudo apt update && sudo apt upgrade -y

# Restart if kernel updated
sudo reboot
```

## Quarterly Maintenance

### Failover Drill (1 hour)

**Purpose:** Verify failover procedures and timing

1. **Schedule during maintenance window**
   - Notify users of potential disruption
   - Document current state

2. **Perform failover**
   ```bash
   # Time the operation
   time ./scripts/promote-replica.sh
   ```

3. **Verify functionality**
   - Test user login
   - Check admin console
   - Verify all realms accessible

4. **Document results**
   - Total failover time
   - Issues encountered
   - User impact

5. **Failback**
   - Rebuild old primary as replica
   - Perform reverse failover
   - Verify everything back to normal

### Capacity Planning Review (30 minutes)

```bash
# Database growth
docker exec postgres-primary psql -U postgres -c \
  "SELECT pg_size_pretty(pg_database_size('keycloak')) as current_size;"

# Compare to historical data
# Estimate growth rate
# Plan for capacity upgrades

# Resource utilization over last 30 days
docker stats --no-stream

# Review and project 6 months ahead
```

### Backup Testing (2 hours)

1. **Full restore test:**
   ```bash
   # Create test environment
   docker compose -f docker-compose-test.yml up -d
   
   # Restore latest backup
   gunzip -c latest_backup.sql.gz | \
     docker exec -i postgres-test psql -U postgres -d keycloak
   
   # Verify data integrity
   # Test Keycloak functionality
   
   # Cleanup
   docker compose -f docker-compose-test.yml down -v
   ```

2. **Document:**
   - Restore time
   - Any issues
   - Data verification results

## Monitoring and Alerting

### Key Metrics to Monitor

**PostgreSQL Primary:**
- Replication connections (should be 1+)
- Replication lag (should be < 5 seconds)
- Disk space (alert at 80%)
- Connection count (alert at 80% of max_connections)
- CPU usage (alert at 80%)
- Memory usage (alert at 90%)

**PostgreSQL Replica:**
- Recovery status (should be true)
- Replication lag (should be < 5 seconds)
- Disk space (alert at 80%)
- Connectivity to primary (should be connected)

**Keycloak:**
- Health endpoint status (should be UP)
- Response time (alert if > 2 seconds)
- Error rate (alert if > 1%)
- Active sessions
- CPU/Memory usage

### Sample Prometheus Queries

```yaml
# Replication lag
pg_replication_lag_seconds > 10

# Disk space
(node_filesystem_avail_bytes / node_filesystem_size_bytes) < 0.2

# Database connections
pg_stat_database_numbackends > 80

# Keycloak response time
histogram_quantile(0.95, http_request_duration_seconds) > 2
```

### Alert Response Playbook

**Alert: Replication Lag High**
1. Check network connectivity
2. Check primary server load
3. Review PostgreSQL logs
4. If lag > 1 minute, page on-call

**Alert: Primary Database Down**
1. Attempt to restart service
2. If restart fails, initiate failover
3. Investigate root cause
4. Prepare incident report

**Alert: Disk Space Low**
1. Identify large files/tables
2. Clean up old WAL files
3. Expand storage if needed
4. Update capacity plan

## Backup and Recovery Procedures

### Backup Schedule

- **Continuous:** WAL archiving
- **Hourly:** Incremental WAL backups
- **Daily:** Full database dump
- **Weekly:** Verified restore test
- **Monthly:** Offsite backup copy

### Recovery Time Objectives (RTO)

- **Failover to replica:** < 5 minutes
- **Restore from daily backup:** < 1 hour
- **Full disaster recovery:** < 4 hours

### Recovery Point Objectives (RPO)

- **With replication:** < 1 second
- **From backup:** < 24 hours
- **With WAL archiving:** < 1 minute

## Configuration Changes

### Making Configuration Changes

1. **Test in non-production first**
2. **Document the change**
3. **Backup current configuration**
4. **Apply change during maintenance window**
5. **Monitor closely after change**
6. **Be ready to rollback**

### PostgreSQL Configuration Changes

```bash
# Edit configuration
nano primary/postgres/config/postgresql.conf

# Reload configuration (no restart needed for most settings)
docker exec postgres-primary psql -U postgres -c "SELECT pg_reload_conf();"

# Verify change
docker exec postgres-primary psql -U postgres -c "SHOW setting_name;"

# Some settings require restart
docker compose -f docker-compose-primary.yml restart postgres-primary
```

### Keycloak Configuration Changes

```bash
# Edit environment variables
nano .env

# Restart Keycloak
docker compose -f docker-compose-primary.yml restart keycloak-primary

# Verify
curl http://localhost:8080/health/ready
```

## Scaling Considerations

### When to Scale Up

Indicators:
- CPU consistently > 80%
- Memory consistently > 85%
- Disk I/O wait time high
- Response times degrading
- Connection pool exhausted

### Vertical Scaling

```yaml
# In docker-compose.yml, add resource limits
services:
  postgres-primary:
    deploy:
      resources:
        limits:
          cpus: '4'
          memory: 8G
        reservations:
          cpus: '2'
          memory: 4G
```

### Horizontal Scaling

For higher availability and performance:
- Add more read replicas
- Implement connection pooling (PgBouncer)
- Consider Active-Active clustering
- Use external load balancer

## Documentation

### Keep Updated

- Network diagram
- IP addresses and hostnames
- Credentials location
- Escalation procedures
- Vendor contacts
- SLA commitments

### Incident Response

After any incident:
1. Write incident report
2. Identify root cause
3. Implement preventive measures
4. Update runbooks
5. Share lessons learned

## Useful Commands Reference

### PostgreSQL

```bash
# Connect to database
docker exec -it postgres-primary psql -U postgres

# List databases
\l

# Connect to keycloak database
\c keycloak

# List tables
\dt

# Describe table
\d table_name

# Show running queries
SELECT pid, now() - pg_stat_activity.query_start AS duration, query, state
FROM pg_stat_activity
WHERE state != 'idle' AND query NOT ILIKE '%pg_stat_activity%'
ORDER BY duration DESC;

# Kill query
SELECT pg_terminate_backend(pid);
```

### Docker

```bash
# View logs
docker logs -f container_name

# Execute command in container
docker exec -it container_name bash

# Copy file from container
docker cp container_name:/path/file ./local_file

# Inspect container
docker inspect container_name

# Resource usage
docker stats

# Clean up
docker system prune -a
```

## Best Practices Summary

1. **Always have recent backups**
2. **Test failover regularly**
3. **Monitor continuously**
4. **Update regularly**
5. **Document everything**
6. **Automate repetitive tasks**
7. **Plan for capacity**
8. **Security first**
9. **Measure and improve**
10. **Learn from incidents**
