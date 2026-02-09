# HAProxy Load Balancer Deployment Guide

This guide covers the deployment and configuration of HAProxy as a load balancer for the Keycloak High Availability setup with PostgreSQL streaming replication.

## Table of Contents

- [Overview](#overview)
- [Prerequisites](#prerequisites)
- [Architecture](#architecture)
- [Installation](#installation)
- [Configuration](#configuration)
- [SSL/TLS Setup](#ssltls-setup)
- [Deployment](#deployment)
- [Verification](#verification)
- [Monitoring](#monitoring)
- [Maintenance](#maintenance)

## Overview

HAProxy provides:
- **Single Entry Point**: Clients connect to one IP address
- **Automatic Failover**: Routes traffic to healthy backends
- **Health Checks**: Monitors Keycloak and PostgreSQL instances
- **SSL/TLS Termination**: Centralized certificate management
- **Load Balancing**: Distributes traffic across available servers
- **Observability**: Built-in statistics and metrics

## Prerequisites

### Server Requirements

**Server C (HAProxy Server):**
- Operating System: Linux (Ubuntu 20.04+ or CentOS 8+)
- CPU: 2 cores minimum
- RAM: 2GB minimum
- Disk: 20GB minimum
- Docker Engine 20.10+
- Docker Compose 2.0+

**Network Requirements:**
- Static IP address for HAProxy server
- Network connectivity to Server A (Primary) and Server B (Replica)
- Firewall rules configured (see Network Configuration section)

### Software Requirements

```bash
# Check Docker version
docker --version
# Should be 20.10 or higher

# Check Docker Compose version
docker compose version
# Should be 2.0 or higher
```

## Architecture

```
                    Internet/Clients
                           │
                           ▼
                  ┌─────────────────┐
                  │   HAProxy       │
                  │   (Server C)    │
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
└───────────────┘  └───────────────┘  └──────────────┘
```

## Installation

### Step 1: Clone Repository

```bash
# On Server C (HAProxy server)
git clone https://github.com/noerarief23/keycloak-HA-active-passive-docker.git
cd keycloak-HA-active-passive-docker
```

### Step 2: Verify Directory Structure

```bash
ls -la haproxy/
# Should show:
# - haproxy.cfg
# - certs/
# - errors/
# - scripts/
```

### Step 3: Install Docker (if not already installed)

**Ubuntu/Debian:**
```bash
curl -fsSL https://get.docker.com -o get-docker.sh
sudo sh get-docker.sh
sudo usermod -aG docker $USER
```

**CentOS/RHEL:**
```bash
sudo yum install -y docker
sudo systemctl start docker
sudo systemctl enable docker
sudo usermod -aG docker $USER
```

Log out and back in for group changes to take effect.

## Configuration

### Step 1: Configure Environment Variables

```bash
# Copy example file
cp .env.lb.example .env

# Edit configuration
nano .env
```

Update the following variables:

```bash
# HAProxy stats page credentials
HAPROXY_STATS_USER=admin
HAPROXY_STATS_PASSWORD=your_secure_password_here

# Server IP addresses
PRIMARY_SERVER_IP=192.168.1.10    # Server A IP
REPLICA_SERVER_IP=192.168.1.11    # Server B IP
```

**Important:** Use actual IP addresses of your servers, not localhost or 127.0.0.1.

### Step 2: Update HAProxy Configuration

Edit `haproxy/haproxy.cfg` if needed:

```bash
nano haproxy/haproxy.cfg
```

Key sections to verify:

**Keycloak Backend:**
```
backend keycloak_backend
    server keycloak-primary 172.20.0.11:8080 check inter 5s fall 3 rise 2
    server keycloak-replica 172.20.0.21:8080 check inter 5s fall 3 rise 2 backup
```

**PostgreSQL Backend:**
```
backend postgres_backend
    server postgres-primary ${PRIMARY_SERVER_IP}:5432 check inter 3s fall 3 rise 2
    server postgres-replica ${REPLICA_SERVER_IP}:5433 check inter 3s fall 3 rise 2 backup
```

### Step 3: Network Configuration

**Firewall Rules for Server C (HAProxy):**

```bash
# Allow incoming traffic
sudo ufw allow 80/tcp    # HTTP
sudo ufw allow 443/tcp   # HTTPS
sudo ufw allow 5432/tcp  # PostgreSQL
sudo ufw allow 8404/tcp  # Stats (restrict to admin IPs in production)

# Allow outgoing to backend servers
sudo ufw allow out to 192.168.1.10 port 8080  # Primary Keycloak
sudo ufw allow out to 192.168.1.10 port 5432  # Primary PostgreSQL
sudo ufw allow out to 192.168.1.11 port 8081  # Replica Keycloak
sudo ufw allow out to 192.168.1.11 port 5433  # Replica PostgreSQL
```

**Firewall Rules for Server A & B:**

```bash
# Allow incoming from HAProxy only
sudo ufw allow from 192.168.1.12 to any port 8080  # Keycloak
sudo ufw allow from 192.168.1.12 to any port 5432  # PostgreSQL

# Block direct client access (optional but recommended)
sudo ufw deny 8080/tcp
sudo ufw deny 5432/tcp
```

## SSL/TLS Setup

Choose one of the following options:

### Option 1: Self-Signed Certificate (Testing)

```bash
cd haproxy/scripts
./generate-cert.sh keycloak.local
```

### Option 2: Existing Certificate

If you have a certificate from a CA:

```bash
cd haproxy/scripts
./combine-cert.sh /path/to/certificate.crt /path/to/private.key
```

### Option 3: Let's Encrypt (Production)

```bash
# Install Certbot
sudo apt-get install certbot

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

See `haproxy/certs/README.md` for detailed SSL setup instructions.

## Deployment

### Step 1: Validate Configuration

```bash
# Test HAProxy configuration syntax
docker run --rm -v $(pwd)/haproxy:/usr/local/etc/haproxy:ro \
  haproxy:2.9-alpine haproxy -c -f /usr/local/etc/haproxy/haproxy.cfg
```

Expected output: `Configuration file is valid`

### Step 2: Start HAProxy

```bash
# Start HAProxy container
docker compose -f docker-compose-lb.yml up -d

# Check container status
docker ps | grep haproxy
```

### Step 3: Check Logs

```bash
# View HAProxy logs
docker logs haproxy-lb

# Follow logs in real-time
docker logs -f haproxy-lb
```

Look for:
- `Proxy keycloak_backend started`
- `Proxy postgres_backend started`
- No error messages

## Verification

### Step 1: Check HAProxy Stats Page

Open in browser: `http://<haproxy-ip>:8404/stats`

Login with credentials from `.env` file.

Verify:
- All backends show "UP" status
- Health checks are passing
- No errors in the status column

### Step 2: Test HTTP/HTTPS Access

```bash
# Test HTTP (should redirect to HTTPS)
curl -I http://<haproxy-ip>/

# Test HTTPS
curl -k -I https://<haproxy-ip>/

# Test with domain name
curl -I https://keycloak.yourdomain.com/
```

### Step 3: Test PostgreSQL Connection

```bash
# Test PostgreSQL connection through HAProxy
psql -h <haproxy-ip> -p 5432 -U keycloak -d keycloak -c "SELECT 1;"
```

### Step 4: Test Keycloak Access

Open in browser: `https://<haproxy-ip>/`

You should see the Keycloak welcome page.

### Step 5: Verify Health Checks

```bash
# Use the check-backends script
cd haproxy/scripts
./check-backends.sh
```

Expected output:
```
Keycloak Backend
----------------------------------------
  keycloak-primary      UP         Sessions: 0     Total: 0
  keycloak-replica      UP         Sessions: 0     Total: 0

PostgreSQL Backend
----------------------------------------
  postgres-primary      UP         Sessions: 0     Total: 0
  postgres-replica      UP         Sessions: 0     Total: 0

✓ All servers are healthy
```

## Monitoring

### Stats Page

Access: `http://<haproxy-ip>:8404/stats`

Key metrics to monitor:
- **Status**: Should be "UP" for all servers
- **Sessions**: Current active connections
- **Errors**: Should be 0 or minimal
- **Downtime**: Total time server was down
- **Last Check**: Time since last health check

### Prometheus Metrics

Access: `http://<haproxy-ip>:8404/metrics`

Key metrics:
```
haproxy_backend_up{backend="keycloak_backend"}
haproxy_backend_up{backend="postgres_backend"}
haproxy_backend_response_time_average_seconds
haproxy_frontend_http_requests_total
```

### Logs

```bash
# View all logs
docker logs haproxy-lb

# View last 100 lines
docker logs --tail 100 haproxy-lb

# Follow logs
docker logs -f haproxy-lb

# Filter for errors
docker logs haproxy-lb | grep -i error
```

### Health Check Script

Run regularly (e.g., via cron):

```bash
# Check backend health
./haproxy/scripts/check-backends.sh

# Exit code 0 = all healthy
# Exit code 1 = some servers down
```

## Maintenance

### Reload Configuration

After changing `haproxy.cfg`:

```bash
# Validate configuration first
docker run --rm -v $(pwd)/haproxy:/usr/local/etc/haproxy:ro \
  haproxy:2.9-alpine haproxy -c -f /usr/local/etc/haproxy/haproxy.cfg

# Reload without downtime
docker exec haproxy-lb kill -HUP 1

# Or restart container (brief downtime)
docker compose -f docker-compose-lb.yml restart haproxy
```

### Update HAProxy Image

```bash
# Pull latest image
docker compose -f docker-compose-lb.yml pull

# Restart with new image
docker compose -f docker-compose-lb.yml up -d
```

### Certificate Renewal

For Let's Encrypt certificates:

```bash
# Renew certificate
sudo certbot renew

# Update HAProxy certificate
sudo cat /etc/letsencrypt/live/keycloak.yourdomain.com/fullchain.pem \
         /etc/letsencrypt/live/keycloak.yourdomain.com/privkey.pem \
         > haproxy/certs/keycloak.pem

# Reload HAProxy
docker exec haproxy-lb kill -HUP 1
```

### Backup Configuration

```bash
# Backup HAProxy configuration
tar -czf haproxy-backup-$(date +%Y%m%d).tar.gz \
  haproxy/ \
  docker-compose-lb.yml \
  .env

# Store backup securely
```

### Update Backend Servers

When adding or removing backend servers:

1. Edit `haproxy/haproxy.cfg`
2. Validate configuration
3. Reload HAProxy
4. Verify in stats page

## Troubleshooting

See `HAPROXY-TROUBLESHOOTING.md` for detailed troubleshooting guide.

### Quick Checks

**HAProxy won't start:**
```bash
# Check configuration syntax
docker run --rm -v $(pwd)/haproxy:/usr/local/etc/haproxy:ro \
  haproxy:2.9-alpine haproxy -c -f /usr/local/etc/haproxy/haproxy.cfg

# Check logs
docker logs haproxy-lb
```

**Backends showing DOWN:**
```bash
# Check network connectivity
ping <backend-ip>
telnet <backend-ip> <port>

# Check backend service is running
docker ps | grep keycloak
docker ps | grep postgres

# Check firewall rules
sudo ufw status
```

**SSL certificate errors:**
```bash
# Verify certificate
openssl x509 -in haproxy/certs/keycloak.crt -noout -text

# Check certificate and key match
openssl x509 -noout -modulus -in haproxy/certs/keycloak.crt | openssl md5
openssl rsa -noout -modulus -in haproxy/certs/keycloak.key | openssl md5
```

## Next Steps

1. **Update DNS**: Point your domain to HAProxy server IP
2. **Test Failover**: Run `./haproxy/scripts/test-failover.sh`
3. **Set Up Monitoring**: Configure alerts for backend failures
4. **Document**: Update your runbooks with HAProxy procedures
5. **Train Team**: Ensure team knows how to check HAProxy status

## Additional Resources

- [HAProxy Configuration](haproxy/haproxy.cfg)
- [SSL Certificate Setup](haproxy/certs/README.md)
- [Failover Testing](haproxy/scripts/test-failover.sh)
- [Backend Health Checks](haproxy/scripts/check-backends.sh)
- [HAProxy Documentation](https://www.haproxy.com/documentation/)

---

**Version:** 1.0  
**Last Updated:** 2024  
**Maintainer:** DevOps Team
