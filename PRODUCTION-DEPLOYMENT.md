# Production Deployment Guide

## Prerequisites

1. **Two Linux servers** (Ubuntu 20.04+ or similar)
   - Server A (Primary): For primary PostgreSQL and Keycloak
   - Server B (Replica): For replica PostgreSQL and Keycloak (standby)

2. **Valid SSL Certificate**
   - Use Let's Encrypt or commercial CA
   - Place certificate files in `haproxy/certs/`

3. **Domain Name**
   - Point your domain to HAProxy server
   - Example: `keycloak.yourdomain.com`

## Server Setup

### Server A (Primary)

1. **Install Docker and Docker Compose**
```bash
curl -fsSL https://get.docker.com -o get-docker.sh
sudo sh get-docker.sh
sudo apt-get install docker-compose-plugin
```

2. **Clone repository**
```bash
git clone <your-repo>
cd keycloak-ha-active-passive-docker
```

3. **Configure environment**
```bash
cp .env.primary.example .env.primary
nano .env.primary
```

Update these values:
```bash
# Strong passwords (generate with: openssl rand -base64 32)
POSTGRES_PASSWORD=<strong-password>
REPLICATION_PASSWORD=<strong-password>
KEYCLOAK_DB_PASSWORD=<strong-password>
KEYCLOAK_ADMIN_PASSWORD=<strong-password>

# Your domain
KC_HOSTNAME=keycloak.yourdomain.com

# Server IPs
PRIMARY_SERVER_IP=<server-a-ip>
REPLICA_SERVER_IP=<server-b-ip>
```

4. **Start primary services**
```bash
docker compose -f docker-compose-primary.yml --env-file .env.primary up -d
```

5. **Verify services**
```bash
docker ps
docker logs keycloak-primary
docker logs postgres-primary
```

### Server B (Replica)

1. **Install Docker and Docker Compose** (same as Server A)

2. **Clone repository** (same as Server A)

3. **Configure environment**
```bash
cp .env.replica.example .env.replica
nano .env.replica
```

Update with **same passwords** as primary:
```bash
POSTGRES_PASSWORD=<same-as-primary>
REPLICATION_PASSWORD=<same-as-primary>
KEYCLOAK_DB_PASSWORD=<same-as-primary>
KEYCLOAK_ADMIN_PASSWORD=<same-as-primary>

KC_HOSTNAME=keycloak.yourdomain.com

PRIMARY_SERVER_IP=<server-a-ip>
REPLICA_SERVER_IP=<server-b-ip>
```

4. **Start replica services**
```bash
docker compose -f docker-compose-replica.yml --env-file .env.replica up -d postgres-replica
```

Note: Keycloak replica is not started by default (backup mode)

5. **Verify replication**
```bash
docker logs postgres-replica
docker exec postgres-primary psql -U postgres -c "SELECT * FROM pg_stat_replication;"
```

### HAProxy Load Balancer

Can be deployed on either server or separate server.

1. **Configure SSL Certificate**
```bash
# If using Let's Encrypt
sudo certbot certonly --standalone -d keycloak.yourdomain.com

# Combine certificate and key
cat /etc/letsencrypt/live/keycloak.yourdomain.com/fullchain.pem \
    /etc/letsencrypt/live/keycloak.yourdomain.com/privkey.pem \
    > haproxy/certs/keycloak.pem

chmod 600 haproxy/certs/keycloak.pem
```

2. **Configure environment**
```bash
cp .env.lb.example .env.lb
nano .env.lb
```

Update:
```bash
HAPROXY_STATS_USER=admin
HAPROXY_STATS_PASSWORD=<strong-password>
PRIMARY_SERVER_IP=<server-a-ip>
REPLICA_SERVER_IP=<server-b-ip>
```

3. **Start HAProxy**
```bash
docker compose -f docker-compose-lb.yml --env-file .env.lb up -d
```

4. **Verify HAProxy**
```bash
docker logs haproxy-lb
curl -u admin:<password> http://localhost:8404/stats
```

## DNS Configuration

Point your domain to HAProxy server:
```
A Record: keycloak.yourdomain.com -> <haproxy-server-ip>
```

## Firewall Configuration

### Server A (Primary)
```bash
sudo ufw allow 22/tcp    # SSH
sudo ufw allow 5432/tcp  # PostgreSQL (from replica)
sudo ufw allow 8080/tcp  # Keycloak (from HAProxy)
sudo ufw allow 9000/tcp  # Keycloak management (from HAProxy)
sudo ufw enable
```

### Server B (Replica)
```bash
sudo ufw allow 22/tcp    # SSH
sudo ufw allow 5432/tcp  # PostgreSQL (from HAProxy)
sudo ufw allow 8080/tcp  # Keycloak (from HAProxy, for failover)
sudo ufw allow 9000/tcp  # Keycloak management (from HAProxy)
sudo ufw enable
```

### HAProxy Server
```bash
sudo ufw allow 22/tcp    # SSH
sudo ufw allow 80/tcp    # HTTP (redirect to HTTPS)
sudo ufw allow 443/tcp   # HTTPS
sudo ufw allow 8404/tcp  # Stats (restrict to admin IPs)
sudo ufw enable
```

## Testing

1. **Test HTTPS access**
```bash
curl https://keycloak.yourdomain.com/
```

2. **Test admin console**
```bash
# Open in browser
https://keycloak.yourdomain.com/admin/
```

3. **Test HAProxy stats**
```bash
https://keycloak.yourdomain.com:8404/stats
```

4. **Test database replication**
```bash
# On primary
docker exec postgres-primary psql -U postgres -c "SELECT * FROM pg_stat_replication;"

# On replica
docker exec postgres-replica psql -U postgres -c "SELECT pg_is_in_recovery();"
```

## Important Differences from Local Testing

### 1. No iframe/CSP issues
With valid SSL certificate and proper domain, the iframe timeout issue will not occur.

### 2. Use production ports
- HTTP: 80 (not 8000)
- HTTPS: 443 (not 8443)
- PostgreSQL: 5432 (not 15432)

### 3. Update docker-compose-lb.yml
Use `docker-compose-lb.yml` (not `docker-compose-lb-windows.yml`)

### 4. Configure Keycloak for Production

**IMPORTANT**: The default compose files are configured for development/testing with relaxed security settings. For production deployment, you should update the following environment variables in `docker-compose-primary.yml` and `docker-compose-replica.yml`:

#### Disable HTTP access to Keycloak
```bash
KC_HTTP_ENABLED=false
```
**Note**: Default is `true` for easier development setup. In production, only HTTPS should be enabled since HAProxy terminates SSL.

#### Enable HTTPS strict mode
```bash
KC_HOSTNAME_STRICT=true
KC_HOSTNAME_STRICT_HTTPS=true
```
**Note**: Default is `false` for flexibility during development. In production, strict hostname validation prevents security issues.

## Monitoring

### Check service health
```bash
# All containers
docker ps

# Keycloak logs
docker logs -f keycloak-primary

# PostgreSQL logs
docker logs -f postgres-primary

# HAProxy logs
docker logs -f haproxy-lb
```

### Monitor replication lag
```bash
docker exec postgres-primary psql -U postgres -c "
SELECT 
    client_addr,
    state,
    sent_lsn,
    write_lsn,
    flush_lsn,
    replay_lsn,
    sync_state
FROM pg_stat_replication;
"
```

### HAProxy stats
Access: `http://<haproxy-ip>:8404/stats`

## Backup Strategy

### Database Backup
```bash
# Automated backup script
docker exec postgres-primary pg_dump -U postgres keycloak > backup-$(date +%Y%m%d).sql
```

### Configuration Backup
```bash
# Backup all .env files (encrypted)
tar -czf config-backup.tar.gz .env.* haproxy/certs/
```

## Failover Procedure

### Manual Failover to Replica

1. **Stop primary Keycloak**
```bash
# On Server A
docker compose -f docker-compose-primary.yml --env-file .env.primary stop keycloak-primary
```

2. **Promote replica PostgreSQL**
```bash
# On Server B
docker exec postgres-replica psql -U postgres -c "SELECT pg_promote();"
```

3. **Start replica Keycloak**
```bash
# On Server B
docker compose -f docker-compose-replica.yml --env-file .env.replica --profile manual up -d keycloak-replica
```

4. **Update HAProxy** (if needed)
HAProxy will automatically detect backend status and route to available server.

## Security Checklist

- [ ] Use strong passwords (32+ characters)
- [ ] Valid SSL certificate (not self-signed)
- [ ] Firewall configured
- [ ] SSH key-based authentication
- [ ] Regular security updates
- [ ] Backup encryption
- [ ] Monitor logs for suspicious activity
- [ ] Restrict HAProxy stats access
- [ ] Use secrets management (not .env files in production)
- [ ] Enable audit logging in Keycloak

## Troubleshooting

See `KEYCLOAK-TROUBLESHOOTING.md` for common issues and solutions.

## Maintenance

### Update Keycloak
```bash
# Update version in docker-compose files
# Rebuild and restart
docker compose -f docker-compose-primary.yml --env-file .env.primary build keycloak-primary
docker compose -f docker-compose-primary.yml --env-file .env.primary up -d keycloak-primary
```

### Update PostgreSQL
```bash
# Backup first!
# Update version in docker-compose files
# Restart services
```

### SSL Certificate Renewal
```bash
# If using Let's Encrypt (auto-renewal)
sudo certbot renew

# Update HAProxy certificate
cat /etc/letsencrypt/live/keycloak.yourdomain.com/fullchain.pem \
    /etc/letsencrypt/live/keycloak.yourdomain.com/privkey.pem \
    > haproxy/certs/keycloak.pem

# Restart HAProxy
docker compose -f docker-compose-lb.yml --env-file .env.lb restart
```

## Support

For issues or questions:
1. Check logs: `docker logs <container-name>`
2. Review troubleshooting guide
3. Check HAProxy stats for backend status
4. Verify network connectivity between servers
