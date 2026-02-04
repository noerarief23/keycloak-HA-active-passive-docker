# Quick Start Guide

This guide will help you set up the Keycloak HA Active/Passive architecture in under 15 minutes.

## Prerequisites Checklist

- [ ] Docker Engine 20.10+ installed
- [ ] Docker Compose 2.0+ installed
- [ ] Two servers available (can be VMs for testing)
- [ ] Network connectivity between servers
- [ ] At least 2GB RAM per server
- [ ] At least 20GB disk space per server

## Step-by-Step Setup

### Server A (Primary) - 5 minutes

1. **Clone and configure:**
   ```bash
   git clone https://github.com/noerarief23/keycloak-HA-active-passive-docker.git
   cd keycloak-HA-active-passive-docker
   cp .env.primary.example .env
   ```

2. **Edit `.env` file with secure passwords:**
   ```bash
   nano .env
   ```
   Update these values:
   - `POSTGRES_PASSWORD=` (generate a strong password)
   - `REPLICATION_PASSWORD=` (generate a strong password)
   - `KEYCLOAK_DB_PASSWORD=` (generate a strong password)
   - `KEYCLOAK_ADMIN_PASSWORD=` (generate a strong password)
   - `KC_HOSTNAME=` (your server's hostname or IP)

3. **Start the primary server:**
   ```bash
   docker compose -f docker-compose-primary.yml up -d
   ```

4. **Wait for services to be healthy (2-3 minutes):**
   ```bash
   watch docker compose -f docker-compose-primary.yml ps
   ```
   Wait until all services show "healthy" status, then press Ctrl+C.

5. **Verify Keycloak is running:**
   ```bash
   curl http://localhost:8080/health/ready
   ```
   You should see: `{"status":"UP"}`

### Server B (Replica) - 5 minutes

1. **Clone and configure:**
   ```bash
   git clone https://github.com/noerarief23/keycloak-HA-active-passive-docker.git
   cd keycloak-HA-active-passive-docker
   cp .env.replica.example .env
   ```

2. **Edit `.env` file:**
   ```bash
   nano .env
   ```
   Update these values:
   - Use **SAME** passwords as Server A
   - `PRIMARY_SERVER_IP=` (IP address of Server A)
   - `KC_HOSTNAME=` (this server's hostname or IP)

3. **Start the replica database:**
   ```bash
   docker compose -f docker-compose-replica.yml up -d postgres-replica
   ```

4. **Watch the base backup process:**
   ```bash
   docker logs -f postgres-replica
   ```
   You'll see the base backup being performed. This may take 1-2 minutes for an empty database.
   Press Ctrl+C when you see "database system is ready to accept read-only connections".

### Verification - 3 minutes

1. **On Server A, check replication status:**
   ```bash
   docker exec postgres-primary psql -U postgres -c "SELECT client_addr, state, sync_state FROM pg_stat_replication;"
   ```
   You should see the replica connected and streaming.

2. **Run the health check script:**
   ```bash
   ./scripts/health-check.sh
   ```
   Both primary and replica PostgreSQL should show as running and healthy.

3. **Verify replication is working:**
   ```bash
   ./scripts/verify-replication.sh
   ```
   You should see: "✓ Replication is working correctly!"

## Testing Failover - 2 minutes

1. **On Server B, promote replica to primary:**
   ```bash
   ./scripts/promote-replica.sh
   ```
   Type `yes` when prompted.

2. **Verify the new primary:**
   ```bash
   curl http://localhost:8081/health/ready
   ```
   You should see: `{"status":"UP"}`

3. **Check services:**
   ```bash
   ./scripts/health-check.sh
   ```
   The replica should now show as PRIMARY.

## Access Keycloak

### Primary (Server A)
- URL: `http://server-a-ip:8080`
- Admin Console: `http://server-a-ip:8080/admin`
- Username: `admin` (or what you set in KEYCLOAK_ADMIN)
- Password: (value from KEYCLOAK_ADMIN_PASSWORD)

### After Failover (Server B)
- URL: `http://server-b-ip:8081`
- Admin Console: `http://server-b-ip:8081/admin`
- Same credentials as above

## What's Next?

1. **Production Setup:**
   - Set up SSL/TLS certificates
   - Configure a load balancer
   - Set up monitoring and alerts
   - Configure regular backups

2. **Customize:**
   - Configure Keycloak realms and clients
   - Set up user federation
   - Configure authentication flows

3. **Testing:**
   - Perform regular failover drills
   - Test backup and restore procedures
   - Load test the system

## Common Issues

### Replica can't connect to primary
- Check firewall rules allow port 5432
- Verify PRIMARY_SERVER_IP is correct
- Ensure passwords match between servers

### Keycloak won't start
- Check database is healthy
- Verify database credentials
- Check logs: `docker logs keycloak-primary`

### Replication lag is high
- Check network latency between servers
- Verify sufficient disk I/O on both servers
- Monitor with: `./scripts/health-check.sh`

## Support

For detailed documentation, see the main [README.md](README.md).

For issues, check the [Troubleshooting section](README.md#troubleshooting).
