# HAProxy Troubleshooting Guide

This guide helps diagnose and resolve common issues with HAProxy load balancer.

## Table of Contents

- [Quick Diagnostics](#quick-diagnostics)
- [HAProxy Won't Start](#haproxy-wont-start)
- [Backend Servers Showing DOWN](#backend-servers-showing-down)
- [SSL/TLS Certificate Issues](#ssltls-certificate-issues)
- [Health Check Failures](#health-check-failures)
- [Connection Issues](#connection-issues)
- [Performance Problems](#performance-problems)
- [Failover Not Working](#failover-not-working)
- [Stats Page Issues](#stats-page-issues)

## Quick Diagnostics

Run these commands first to gather information:

```bash
# Check HAProxy container status
docker ps | grep haproxy

# View recent logs
docker logs --tail 50 haproxy-lb

# Check backend health
cd haproxy/scripts
./check-backends.sh

# View stats page
curl -u admin:password http://localhost:8404/stats
```

## HAProxy Won't Start

### Symptom
Container exits immediately or fails to start.

### Diagnosis

```bash
# Check container logs
docker logs haproxy-lb

# Validate configuration
docker run --rm -v $(pwd)/haproxy:/usr/local/etc/haproxy:ro \
  haproxy:2.9-alpine haproxy -c -f /usr/local/etc/haproxy/haproxy.cfg
```

### Common Causes & Solutions

#### 1. Configuration Syntax Error

**Error Message:**
```
[ALERT] parsing [/usr/local/etc/haproxy/haproxy.cfg:45] : unknown keyword 'bindd'
```

**Solution:**
```bash
# Fix typo in haproxy.cfg
nano haproxy/haproxy.cfg

# Validate again
docker run --rm -v $(pwd)/haproxy:/usr/local/etc/haproxy:ro \
  haproxy:2.9-alpine haproxy -c -f /usr/local/etc/haproxy/haproxy.cfg
```

#### 2. SSL Certificate Not Found

**Error Message:**
```
[ALERT] parsing [/usr/local/etc/haproxy/haproxy.cfg:60] : 'bind *:443' : unable to load SSL certificate file '/etc/haproxy/certs/keycloak.pem'
```

**Solution:**
```bash
# Check if certificate exists
ls -la haproxy/certs/keycloak.pem

# If missing, generate or copy certificate
cd haproxy/scripts
./generate-cert.sh keycloak.local

# Or combine existing certificate
./combine-cert.sh /path/to/cert.crt /path/to/key.key
```

#### 3. Port Already in Use

**Error Message:**
```
[ALERT] Starting frontend http_frontend: cannot bind socket (Address already in use)
```

**Solution:**
```bash
# Check what's using the port
sudo netstat -tulpn | grep :80
sudo netstat -tulpn | grep :443

# Stop conflicting service
sudo systemctl stop nginx  # or apache2

# Or change HAProxy ports in docker-compose-lb.yml
```

#### 4. Permission Issues

**Error Message:**
```
[ALERT] Cannot open configuration file/directory /usr/local/etc/haproxy/haproxy.cfg : Permission denied
```

**Solution:**
```bash
# Fix file permissions
chmod 644 haproxy/haproxy.cfg
chmod 755 haproxy/

# Restart HAProxy
docker compose -f docker-compose-lb.yml restart haproxy
```

## Backend Servers Showing DOWN

### Symptom
Stats page shows backends as DOWN or health checks failing.

### Diagnosis

```bash
# Check backend status
./haproxy/scripts/check-backends.sh

# Test connectivity manually
ping <backend-ip>
telnet <backend-ip> 8080  # For Keycloak
telnet <backend-ip> 5432  # For PostgreSQL

# Check HAProxy logs
docker logs haproxy-lb | grep -i "health check"
```

### Common Causes & Solutions

#### 1. Backend Service Not Running

**Solution:**
```bash
# On backend server, check services
docker ps | grep keycloak
docker ps | grep postgres

# Start if stopped
docker start keycloak-primary
docker start postgres-primary
```

#### 2. Network Connectivity Issues

**Solution:**
```bash
# From HAProxy server, test connectivity
ping 192.168.1.10  # Primary server
ping 192.168.1.11  # Replica server

# Test specific ports
nc -zv 192.168.1.10 8080  # Keycloak
nc -zv 192.168.1.10 5432  # PostgreSQL

# Check firewall rules
sudo ufw status
sudo iptables -L
```

#### 3. Incorrect IP Addresses

**Solution:**
```bash
# Verify IP addresses in configuration
cat .env | grep SERVER_IP

# Update if incorrect
nano .env

# Restart HAProxy
docker compose -f docker-compose-lb.yml restart haproxy
```

#### 4. Health Check Endpoint Not Responding

**For Keycloak:**
```bash
# Test health endpoint directly
curl http://192.168.1.10:8080/health/ready

# Should return HTTP 200
```

**For PostgreSQL:**
```bash
# Test PostgreSQL connection
psql -h 192.168.1.10 -p 5432 -U postgres -c "SELECT 1;"

# Check if haproxy_check user exists
psql -h 192.168.1.10 -p 5432 -U postgres -c "\du haproxy_check"

# Create if missing
psql -h 192.168.1.10 -p 5432 -U postgres -c "CREATE USER haproxy_check WITH LOGIN;"
```

#### 5. Firewall Blocking Connections

**Solution:**
```bash
# On backend servers, allow HAProxy IP
sudo ufw allow from 192.168.1.12 to any port 8080
sudo ufw allow from 192.168.1.12 to any port 5432

# Reload firewall
sudo ufw reload
```

## SSL/TLS Certificate Issues

### Symptom
HTTPS not working, browser shows certificate errors, or HAProxy fails to start.

### Diagnosis

```bash
# Check certificate files
ls -la haproxy/certs/

# Verify certificate
openssl x509 -in haproxy/certs/keycloak.crt -noout -text

# Check certificate expiration
openssl x509 -in haproxy/certs/keycloak.crt -noout -enddate

# Test SSL connection
openssl s_client -connect localhost:443 -servername keycloak.local
```

### Common Causes & Solutions

#### 1. Certificate and Key Mismatch

**Diagnosis:**
```bash
# Check if certificate and key match
CERT_MD5=$(openssl x509 -noout -modulus -in haproxy/certs/keycloak.crt | openssl md5)
KEY_MD5=$(openssl rsa -noout -modulus -in haproxy/certs/keycloak.key | openssl md5)
echo "Certificate: $CERT_MD5"
echo "Key:         $KEY_MD5"
```

**Solution:**
```bash
# If they don't match, regenerate or get correct pair
cd haproxy/scripts
./generate-cert.sh keycloak.local

# Or combine correct certificate and key
./combine-cert.sh /path/to/correct/cert.crt /path/to/correct/key.key
```

#### 2. Certificate Expired

**Solution:**
```bash
# Check expiration
openssl x509 -in haproxy/certs/keycloak.crt -noout -enddate

# Renew certificate
# For Let's Encrypt:
sudo certbot renew

# For self-signed:
cd haproxy/scripts
./generate-cert.sh keycloak.local

# Reload HAProxy
docker exec haproxy-lb kill -HUP 1
```

#### 3. Wrong Certificate Format

**Solution:**
```bash
# HAProxy needs PEM format with certificate + key
# Recreate PEM file
cat haproxy/certs/keycloak.crt haproxy/certs/keycloak.key > haproxy/certs/keycloak.pem

# Set permissions
chmod 600 haproxy/certs/keycloak.pem

# Reload HAProxy
docker exec haproxy-lb kill -HUP 1
```

#### 4. Missing DH Parameters

**Solution:**
```bash
# Generate DH parameters
openssl dhparam -out haproxy/certs/dhparam.pem 2048

# Reload HAProxy
docker exec haproxy-lb kill -HUP 1
```

#### 5. Certificate Name Mismatch

**Diagnosis:**
```bash
# Check certificate CN/SAN
openssl x509 -in haproxy/certs/keycloak.crt -noout -subject -ext subjectAltName
```

**Solution:**
Generate new certificate with correct domain name or add domain to /etc/hosts for testing.

## Health Check Failures

### Symptom
Backends intermittently show as DOWN, or health checks timing out.

### Diagnosis

```bash
# Check health check timing in logs
docker logs haproxy-lb | grep "Health check"

# Test health endpoints manually
curl -v http://192.168.1.10:8080/health/ready
psql -h 192.168.1.10 -p 5432 -U haproxy_check -c "SELECT 1;"
```

### Solutions

#### 1. Increase Health Check Timeouts

Edit `haproxy/haproxy.cfg`:

```
# Increase timeout for slow backends
timeout check 5000ms  # Default is 3000ms
```

#### 2. Adjust Health Check Intervals

```
# In backend configuration
server keycloak-primary 172.20.0.11:8080 check inter 10s fall 5 rise 3
```

- `inter 10s`: Check every 10 seconds (instead of 5)
- `fall 5`: Mark down after 5 failures (instead of 3)
- `rise 3`: Mark up after 3 successes (instead of 2)

#### 3. Backend Performance Issues

```bash
# Check backend resource usage
docker stats keycloak-primary
docker stats postgres-primary

# Check backend logs for errors
docker logs keycloak-primary | grep -i error
docker logs postgres-primary | grep -i error
```

## Connection Issues

### Symptom
Clients cannot connect to services through HAProxy.

### Diagnosis

```bash
# Test from client
curl -v http://<haproxy-ip>/
curl -v https://<haproxy-ip>/
psql -h <haproxy-ip> -p 5432 -U keycloak -d keycloak

# Check HAProxy is listening
sudo netstat -tulpn | grep haproxy
docker exec haproxy-lb netstat -tulpn
```

### Solutions

#### 1. HAProxy Not Listening on Correct Interface

**Check docker-compose-lb.yml:**
```yaml
# For host network mode
network_mode: host

# Or for bridge mode, ensure ports are exposed
ports:
  - "80:80"
  - "443:443"
  - "5432:5432"
  - "8404:8404"
```

#### 2. Firewall Blocking Connections

```bash
# Check firewall rules
sudo ufw status

# Allow required ports
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
sudo ufw allow 5432/tcp
sudo ufw allow 8404/tcp

# Reload firewall
sudo ufw reload
```

#### 3. DNS Issues

```bash
# Test with IP address
curl http://192.168.1.12/

# If works, it's a DNS issue
# Update DNS or /etc/hosts
echo "192.168.1.12 keycloak.local" | sudo tee -a /etc/hosts
```

## Performance Problems

### Symptom
Slow response times, high latency, or connection timeouts.

### Diagnosis

```bash
# Check HAProxy stats
curl -u admin:password http://localhost:8404/stats

# Check resource usage
docker stats haproxy-lb

# Check connection counts
docker exec haproxy-lb netstat -an | grep ESTABLISHED | wc -l
```

### Solutions

#### 1. Increase Connection Limits

Edit `haproxy/haproxy.cfg`:

```
global
    maxconn 8192  # Increase from 4096
```

#### 2. Tune Timeouts

```
defaults
    timeout connect 10000ms  # Increase if needed
    timeout client  60000ms
    timeout server  60000ms
```

#### 3. Enable HTTP Keep-Alive

```
defaults
    option http-keep-alive
    timeout http-keep-alive 30000ms
```

#### 4. Add More Resources

```yaml
# In docker-compose-lb.yml
services:
  haproxy:
    deploy:
      resources:
        limits:
          cpus: '2'
          memory: 2G
```

## Failover Not Working

### Symptom
Traffic not switching to backup server when primary fails.

### Diagnosis

```bash
# Test failover
cd haproxy/scripts
./test-failover.sh keycloak

# Check backend configuration
docker exec haproxy-lb cat /usr/local/etc/haproxy/haproxy.cfg | grep -A 5 "backend"
```

### Solutions

#### 1. Backup Server Not Configured

Ensure `backup` keyword is present:

```
server keycloak-replica 172.20.0.21:8080 check inter 5s fall 3 rise 2 backup
```

#### 2. Backup Server Not Running

```bash
# Start backup server
docker start keycloak-replica
```

#### 3. Health Checks Too Slow

Reduce detection time:

```
server keycloak-primary 172.20.0.11:8080 check inter 2s fall 2 rise 2
```

## Stats Page Issues

### Symptom
Cannot access stats page or authentication fails.

### Solutions

#### 1. Wrong Credentials

```bash
# Check credentials in .env
cat .env | grep HAPROXY_STATS

# Update if needed
nano .env

# Restart HAProxy
docker compose -f docker-compose-lb.yml restart haproxy
```

#### 2. Stats Port Not Accessible

```bash
# Check if port is open
sudo ufw allow 8404/tcp

# Test locally first
curl -u admin:password http://localhost:8404/stats

# Then test remotely
curl -u admin:password http://<haproxy-ip>:8404/stats
```

#### 3. Stats Not Enabled

Check `haproxy/haproxy.cfg`:

```
frontend stats_frontend
    bind *:8404
    stats enable
    stats uri /stats
    stats auth ${HAPROXY_STATS_USER}:${HAPROXY_STATS_PASSWORD}
```

## Getting Help

If issues persist:

1. **Collect Information:**
   ```bash
   # Save logs
   docker logs haproxy-lb > haproxy-logs.txt
   
   # Save configuration
   docker exec haproxy-lb cat /usr/local/etc/haproxy/haproxy.cfg > haproxy-config.txt
   
   # Save stats
   curl -u admin:password http://localhost:8404/stats\;csv > haproxy-stats.csv
   ```

2. **Check Documentation:**
   - [HAProxy Documentation](https://www.haproxy.com/documentation/)
   - [HAProxy Configuration Manual](https://cbonte.github.io/haproxy-dconv/)

3. **Community Support:**
   - [HAProxy Discourse](https://discourse.haproxy.org/)
   - [Stack Overflow](https://stackoverflow.com/questions/tagged/haproxy)

4. **Contact Support:**
   - Include logs, configuration, and steps to reproduce
   - Describe expected vs actual behavior
   - List troubleshooting steps already tried

---

**Version:** 1.0  
**Last Updated:** 2024
