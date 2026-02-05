# HAProxy Deployment Checklist

Panduan lengkap untuk deployment HAProxy di environment test dan production.

## Pre-Deployment Checklist

### Server C (HAProxy Server) Requirements

- [ ] Server dengan OS Linux (Ubuntu 20.04+ atau CentOS 8+)
- [ ] Minimal 2 CPU cores
- [ ] Minimal 2GB RAM
- [ ] Minimal 20GB disk space
- [ ] Static IP address configured
- [ ] Docker Engine 20.10+ installed
- [ ] Docker Compose 2.0+ installed
- [ ] Network connectivity ke Server A dan Server B
- [ ] Firewall rules configured

### Network Requirements

- [ ] Server C dapat ping ke Server A (Primary)
- [ ] Server C dapat ping ke Server B (Replica)
- [ ] Port 8080 accessible dari Server C ke Server A (Keycloak Primary)
- [ ] Port 8081 accessible dari Server C ke Server B (Keycloak Replica)
- [ ] Port 5432 accessible dari Server C ke Server A (PostgreSQL Primary)
- [ ] Port 5433 accessible dari Server C ke Server B (PostgreSQL Replica)
- [ ] Port 80, 443, 5432, 8404 available di Server C

### Configuration Files

- [ ] `.env` file created dan configured
- [ ] `haproxy/haproxy.cfg` reviewed dan updated dengan IP yang benar
- [ ] SSL certificate generated atau installed
- [ ] Backend server IPs configured correctly

## Deployment Steps

### Step 1: Prepare Server C

```bash
# Update system
sudo apt update && sudo apt upgrade -y

# Install Docker
curl -fsSL https://get.docker.com -o get-docker.sh
sudo sh get-docker.sh
sudo usermod -aG docker $USER

# Install Docker Compose (if not included)
sudo apt install docker-compose-plugin -y

# Logout and login again
exit
```

**Verification:**
```bash
docker --version
docker compose version
```

- [ ] Docker installed successfully
- [ ] Docker Compose installed successfully
- [ ] User can run docker commands without sudo

### Step 2: Clone Repository

```bash
# Clone repository
git clone https://github.com/noerarief23/keycloak-HA-active-passive-docker.git
cd keycloak-HA-active-passive-docker
```

- [ ] Repository cloned successfully
- [ ] All files present

### Step 3: Configure Environment

```bash
# Copy environment file
cp .env.lb.example .env

# Edit configuration
nano .env
```

Update the following:
```bash
# Stats credentials (CHANGE THESE!)
HAPROXY_STATS_USER=admin
HAPROXY_STATS_PASSWORD=your_secure_password_here

# Backend server IPs (UPDATE WITH ACTUAL IPs)
PRIMARY_SERVER_IP=192.168.1.10    # Server A IP
REPLICA_SERVER_IP=192.168.1.11    # Server B IP
```

- [ ] `.env` file created
- [ ] Stats password changed from default
- [ ] Primary server IP configured correctly
- [ ] Replica server IP configured correctly

### Step 4: Configure HAProxy

```bash
# Review HAProxy configuration
nano haproxy/haproxy.cfg
```

Verify/update these sections:

**Keycloak Backend:**
```
backend keycloak_backend
    server keycloak-primary <PRIMARY_IP>:8080 check inter 5s fall 3 rise 2
    server keycloak-replica <REPLICA_IP>:8081 check inter 5s fall 3 rise 2 backup
```

**PostgreSQL Backend:**
```
backend postgres_backend
    server postgres-primary ${PRIMARY_SERVER_IP}:5432 check inter 3s fall 3 rise 2
    server postgres-replica ${REPLICA_SERVER_IP}:5433 check inter 3s fall 3 rise 2 backup
```

- [ ] Keycloak backend IPs verified
- [ ] PostgreSQL backend IPs verified
- [ ] Port numbers correct

### Step 5: Setup SSL Certificate

**Option A: Self-Signed (Testing)**
```bash
cd haproxy/scripts
./generate-cert.sh keycloak.local
cd ../..
```

**Option B: Let's Encrypt (Production)**
```bash
# Install Certbot
sudo apt-get install certbot -y

# Obtain certificate
sudo certbot certonly --standalone \
  -d keycloak.yourdomain.com \
  --email admin@yourdomain.com \
  --agree-tos

# Combine for HAProxy
sudo cat /etc/letsencrypt/live/keycloak.yourdomain.com/fullchain.pem \
         /etc/letsencrypt/live/keycloak.yourdomain.com/privkey.pem \
         > haproxy/certs/keycloak.pem

# Set permissions
sudo chmod 600 haproxy/certs/keycloak.pem
```

- [ ] SSL certificate generated/installed
- [ ] Certificate file exists at `haproxy/certs/keycloak.pem`
- [ ] Certificate permissions set to 600

### Step 6: Configure Firewall

```bash
# Allow incoming traffic
sudo ufw allow 80/tcp    # HTTP
sudo ufw allow 443/tcp   # HTTPS
sudo ufw allow 5432/tcp  # PostgreSQL
sudo ufw allow 8404/tcp  # Stats (restrict in production)

# Enable firewall
sudo ufw enable
```

- [ ] Firewall rules configured
- [ ] Ports 80, 443, 5432, 8404 allowed

### Step 7: Validate Configuration

```bash
# Run validation script
./haproxy/scripts/validate-config.sh
```

Expected output: All checks should pass or show warnings only.

- [ ] HAProxy configuration syntax valid
- [ ] SSL certificate valid
- [ ] Backend connectivity verified
- [ ] Environment variables set

### Step 8: Deploy HAProxy

```bash
# Run deployment script
cd haproxy/scripts
./deploy-haproxy.sh
```

The script will:
1. Check prerequisites
2. Verify configuration
3. Start HAProxy container
4. Verify health checks

- [ ] Deployment script completed successfully
- [ ] HAProxy container running
- [ ] No errors in logs

### Step 9: Verify Deployment

```bash
# Check container status
docker ps | grep haproxy

# Check logs
docker logs haproxy-lb

# Check backend health
./haproxy/scripts/check-backends.sh
```

- [ ] HAProxy container is running
- [ ] No errors in logs
- [ ] All backends showing UP

### Step 10: Test Connectivity

```bash
# Get server IP
SERVER_IP=$(hostname -I | awk '{print $1}')

# Test HTTP (should redirect to HTTPS)
curl -I http://$SERVER_IP/

# Test HTTPS
curl -k -I https://$SERVER_IP/

# Test stats page
curl -u admin:password http://$SERVER_IP:8404/stats
```

- [ ] HTTP redirects to HTTPS (301/302)
- [ ] HTTPS returns 200 or 302
- [ ] Stats page accessible

## End-to-End Testing Checklist

### Test 1: Keycloak Access Through HAProxy

```bash
# Access Keycloak through HAProxy
curl -k https://<haproxy-ip>/

# Or open in browser
https://<haproxy-ip>/
```

- [ ] Keycloak welcome page loads
- [ ] No SSL errors (if using valid certificate)
- [ ] Response time acceptable

### Test 2: Keycloak Admin Login

```bash
# Open in browser
https://<haproxy-ip>/admin

# Login with admin credentials
```

- [ ] Admin console accessible
- [ ] Login successful
- [ ] Dashboard loads correctly

### Test 3: PostgreSQL Connection Through HAProxy

```bash
# Test PostgreSQL connection
psql -h <haproxy-ip> -p 5432 -U keycloak -d keycloak -c "SELECT 1;"

# Check connection in HAProxy stats
curl -u admin:password http://<haproxy-ip>:8404/stats
```

- [ ] PostgreSQL connection successful
- [ ] Query executes correctly
- [ ] Connection shows in HAProxy stats

### Test 4: Keycloak Failover Test

```bash
# Run failover test script
./haproxy/scripts/test-failover.sh keycloak
```

Expected behavior:
1. Primary Keycloak stops
2. HAProxy detects failure (within 15 seconds)
3. Traffic routes to replica
4. Keycloak remains accessible

- [ ] Primary Keycloak stopped successfully
- [ ] HAProxy detected failure
- [ ] Traffic routed to replica
- [ ] Keycloak still accessible
- [ ] Failover time < 20 seconds

### Test 5: PostgreSQL Failover Test

```bash
# Run PostgreSQL failover test
./haproxy/scripts/test-failover.sh postgres
```

Expected behavior:
1. Primary PostgreSQL stops
2. HAProxy detects failure (within 9 seconds)
3. Traffic routes to replica
4. Database queries still work (read-only)

- [ ] Primary PostgreSQL stopped successfully
- [ ] HAProxy detected failure
- [ ] Traffic routed to replica
- [ ] Database queries work
- [ ] Failover time < 15 seconds

### Test 6: Integration Tests

```bash
# Run full integration test suite
./haproxy/scripts/integration-test.sh
```

- [ ] All integration tests pass
- [ ] No failures reported

### Test 7: Load Testing (Optional)

```bash
# Run load test
./haproxy/scripts/load-test.sh
```

- [ ] Load test completes without errors
- [ ] Response times acceptable
- [ ] No connection failures
- [ ] HAProxy handles load well

### Test 8: Monitoring and Logging

```bash
# Check stats page
# Open in browser: http://<haproxy-ip>:8404/stats

# Check Prometheus metrics
curl http://<haproxy-ip>:8404/metrics

# Check logs
docker logs haproxy-lb --tail 100
```

- [ ] Stats page shows all backends UP
- [ ] Metrics endpoint working
- [ ] Logs show normal operation
- [ ] No errors in logs

## Post-Deployment Tasks

### DNS Configuration

```bash
# Update DNS records to point to HAProxy server
# Example:
# keycloak.yourdomain.com -> <haproxy-ip>
```

- [ ] DNS A record created/updated
- [ ] DNS propagation verified
- [ ] Domain resolves to HAProxy IP

### Monitoring Setup

- [ ] Prometheus scraping configured (if using)
- [ ] Grafana dashboard created (if using)
- [ ] Alert rules configured
- [ ] Notification channels set up

### Documentation

- [ ] Network diagram updated
- [ ] Runbook created/updated
- [ ] Team trained on HAProxy operations
- [ ] Emergency procedures documented

### Security Hardening

- [ ] Stats page access restricted by IP (production)
- [ ] Strong passwords configured
- [ ] SSL certificate from trusted CA (production)
- [ ] Firewall rules reviewed
- [ ] Security audit completed

## Rollback Plan

If deployment fails or issues occur:

```bash
# Stop HAProxy
docker compose -f docker-compose-lb.yml stop

# Or rollback to previous configuration
./haproxy/scripts/rollback-haproxy.sh

# Restore direct access to backends
# Update DNS or application configuration
```

- [ ] Rollback procedure tested
- [ ] Rollback time documented
- [ ] Team knows rollback procedure

## Maintenance Schedule

### Daily
- [ ] Check backend health: `./haproxy/scripts/check-backends.sh`
- [ ] Review logs for errors
- [ ] Verify stats page accessible

### Weekly
- [ ] Check SSL certificate expiration
- [ ] Review stats for anomalies
- [ ] Check disk space

### Monthly
- [ ] Update Docker images
- [ ] Review and rotate logs
- [ ] Test failover procedures
- [ ] Review security settings

### Quarterly
- [ ] Renew SSL certificates (if needed)
- [ ] Perform load testing
- [ ] Review and update documentation
- [ ] Security audit

## Troubleshooting

If issues occur, refer to:
- [HAPROXY-TROUBLESHOOTING.md](../HAPROXY-TROUBLESHOOTING.md)
- [QUICK-REFERENCE.md](./QUICK-REFERENCE.md)

Common issues:
1. **Backends showing DOWN**: Check network connectivity and backend services
2. **SSL errors**: Verify certificate validity and format
3. **Cannot access stats**: Check credentials and firewall rules
4. **High latency**: Review HAProxy logs and backend performance

## Sign-Off

Deployment completed by: ___________________

Date: ___________________

Verified by: ___________________

Date: ___________________

Notes:
_________________________________________________________________
_________________________________________________________________
_________________________________________________________________

---

**Checklist Version:** 1.0  
**Last Updated:** 2024
