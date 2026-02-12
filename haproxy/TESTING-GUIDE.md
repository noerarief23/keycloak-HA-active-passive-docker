# HAProxy Testing Guide

Panduan lengkap untuk testing HAProxy load balancer dalam berbagai skenario.

## Table of Contents

1. [Pre-Testing Setup](#pre-testing-setup)
2. [Basic Connectivity Tests](#basic-connectivity-tests)
3. [Keycloak Functionality Tests](#keycloak-functionality-tests)
4. [PostgreSQL Connectivity Tests](#postgresql-connectivity-tests)
5. [Failover Tests](#failover-tests)
6. [Performance Tests](#performance-tests)
7. [Security Tests](#security-tests)
8. [Monitoring Tests](#monitoring-tests)
9. [Test Results Documentation](#test-results-documentation)

## Pre-Testing Setup

### Prerequisites

Pastikan semua komponen sudah running:

```bash
# Check Server A (Primary)
ssh server-a
docker ps | grep keycloak
docker ps | grep postgres

# Check Server B (Replica)
ssh server-b
docker ps | grep keycloak
docker ps | grep postgres

# Check Server C (HAProxy)
ssh server-c
docker ps | grep haproxy
```

### Environment Variables

```bash
# Set test environment variables
export HAPROXY_IP="<haproxy-ip>"  # Server C IP
export PRIMARY_IP="<server-a-ip>"   # Server A IP
export REPLICA_IP="<server-b-ip>"   # Server B IP
export STATS_USER="admin"
export STATS_PASS="your_password"
```

## Basic Connectivity Tests

### Test 1.1: HTTP Connectivity

**Objective:** Verify HTTP port is accessible and redirects to HTTPS

```bash
# Test HTTP connection
curl -v http://$HAPROXY_IP/

# Expected: HTTP 301 or 302 redirect to HTTPS
```

**Expected Result:**
```
< HTTP/1.1 301 Moved Permanently
< Location: https://...
```

**Pass Criteria:**
- [ ] HTTP port 80 accessible
- [ ] Returns 301/302 redirect
- [ ] Location header points to HTTPS

### Test 1.2: HTTPS Connectivity

**Objective:** Verify HTTPS port is accessible with SSL

```bash
# Test HTTPS connection (skip cert verification for self-signed)
curl -k -v https://$HAPROXY_IP/

# Test with certificate verification (production)
curl -v https://keycloak.yourdomain.com/
```

**Expected Result:**
```
< HTTP/2 200
< strict-transport-security: max-age=31536000; includeSubDomains
```

**Pass Criteria:**
- [ ] HTTPS port 443 accessible
- [ ] SSL handshake successful
- [ ] Returns 200 or 302 status
- [ ] Security headers present

### Test 1.3: PostgreSQL Port

**Objective:** Verify PostgreSQL port is accessible

```bash
# Test PostgreSQL port
nc -zv $HAPROXY_IP 5432

# Or using telnet
telnet $HAPROXY_IP 5432
```

**Expected Result:**
```
Connection to <haproxy-ip> 5432 port [tcp/postgresql] succeeded!
```

**Pass Criteria:**
- [ ] Port 5432 accessible
- [ ] Connection established

### Test 1.4: Stats Page

**Objective:** Verify stats page is accessible

```bash
# Test stats page
curl -u $STATS_USER:$STATS_PASS http://$HAPROXY_IP:8404/stats

# Or open in browser
# http://$HAPROXY_IP:8404/stats
```

**Pass Criteria:**
- [ ] Stats page accessible
- [ ] Authentication works
- [ ] Shows backend status

## Keycloak Functionality Tests

### Test 2.1: Keycloak Welcome Page

**Objective:** Verify Keycloak is accessible through HAProxy

```bash
# Access Keycloak
curl -k https://$HAPROXY_IP/ | grep -i keycloak
```

**Browser Test:**
1. Open `https://$HAPROXY_IP/`
2. Verify Keycloak welcome page loads
3. Check for SSL warnings (should be none with valid cert)

**Pass Criteria:**
- [ ] Keycloak welcome page loads
- [ ] Page renders correctly
- [ ] No connection errors

### Test 2.2: Admin Console Access

**Objective:** Verify admin console is accessible

**Steps:**
1. Open `https://$HAPROXY_IP/admin`
2. Login with admin credentials
3. Navigate through admin console

**Pass Criteria:**
- [ ] Admin console loads
- [ ] Login successful
- [ ] Dashboard displays correctly
- [ ] Can navigate between sections

### Test 2.3: Create Test Realm

**Objective:** Verify Keycloak write operations work

**Steps:**
1. Login to admin console
2. Click "Create Realm"
3. Name: `test-realm`
4. Click "Create"
5. Verify realm created

**Pass Criteria:**
- [ ] Realm creation successful
- [ ] Realm appears in realm list
- [ ] Can access realm settings

### Test 2.4: Create Test User

**Objective:** Verify user management works

**Steps:**
1. Select `test-realm`
2. Go to Users → Add User
3. Username: `testuser`
4. Email: `test@example.com`
5. Click "Save"
6. Set password in Credentials tab

**Pass Criteria:**
- [ ] User created successfully
- [ ] User appears in user list
- [ ] Password set successfully

### Test 2.5: User Login Test

**Objective:** Verify authentication works through HAProxy

**Steps:**
1. Create a test client in `test-realm`
2. Try to authenticate as `testuser`
3. Verify authentication successful

**Pass Criteria:**
- [ ] Authentication request successful
- [ ] Token received
- [ ] No errors in Keycloak logs

## PostgreSQL Connectivity Tests

### Test 3.1: Direct Connection

**Objective:** Verify PostgreSQL connection through HAProxy

```bash
# Test connection
psql -h $HAPROXY_IP -p 5432 -U keycloak -d keycloak -c "SELECT version();"

# Enter password when prompted
```

**Expected Result:**
```
                                                 version
---------------------------------------------------------------------------------------------------------
 PostgreSQL 15.x on x86_64-pc-linux-gnu, compiled by gcc ...
(1 row)
```

**Pass Criteria:**
- [ ] Connection successful
- [ ] Query executes
- [ ] Results returned

### Test 3.2: Read Operations

**Objective:** Verify read queries work

```bash
# Test read query
psql -h $HAPROXY_IP -p 5432 -U keycloak -d keycloak -c \
  "SELECT COUNT(*) FROM realm;"
```

**Pass Criteria:**
- [ ] Query executes successfully
- [ ] Results returned
- [ ] No errors

### Test 3.3: Write Operations

**Objective:** Verify write queries work (should go to primary)

```bash
# Create test table
psql -h $HAPROXY_IP -p 5432 -U keycloak -d keycloak -c \
  "CREATE TABLE IF NOT EXISTS test_table (id SERIAL PRIMARY KEY, data TEXT);"

# Insert test data
psql -h $HAPROXY_IP -p 5432 -U keycloak -d keycloak -c \
  "INSERT INTO test_table (data) VALUES ('test data');"

# Verify data
psql -h $HAPROXY_IP -p 5432 -U keycloak -d keycloak -c \
  "SELECT * FROM test_table;"

# Cleanup
psql -h $HAPROXY_IP -p 5432 -U keycloak -d keycloak -c \
  "DROP TABLE test_table;"
```

**Pass Criteria:**
- [ ] Table created successfully
- [ ] Data inserted successfully
- [ ] Data retrieved successfully
- [ ] Table dropped successfully

### Test 3.4: Connection Pooling

**Objective:** Verify multiple connections work

```bash
# Open multiple connections
for i in {1..10}; do
  psql -h $HAPROXY_IP -p 5432 -U keycloak -d keycloak -c "SELECT $i;" &
done
wait

# Check HAProxy stats for connection count
curl -u $STATS_USER:$STATS_PASS http://$HAPROXY_IP:8404/stats\;csv | \
  grep postgres_backend
```

**Pass Criteria:**
- [ ] All connections successful
- [ ] No connection errors
- [ ] HAProxy stats show connections

## Failover Tests

### Test 4.1: Keycloak Primary Failure

**Objective:** Verify automatic failover to replica Keycloak

**Preparation:**
```bash
# Start replica Keycloak if not running
ssh server-b
docker start keycloak-replica
```

**Test Steps:**

1. **Verify initial state:**
```bash
./haproxy/scripts/check-backends.sh
# Both Keycloak servers should be UP
```

2. **Stop primary Keycloak:**
```bash
ssh server-a
docker stop keycloak-primary
```

3. **Monitor failover:**
```bash
# Watch HAProxy stats
watch -n 1 './haproxy/scripts/check-backends.sh'

# Time the failover
time curl -k https://$HAPROXY_IP/
```

4. **Verify failover:**
```bash
# Check stats page
curl -u $STATS_USER:$STATS_PASS http://$HAPROXY_IP:8404/stats | \
  grep keycloak

# Access Keycloak
curl -k https://$HAPROXY_IP/
```

5. **Restore primary:**
```bash
ssh server-a
docker start keycloak-primary
```

**Expected Results:**
- Failover detection: ~15 seconds (3 failed checks × 5s)
- Keycloak remains accessible during failover
- Traffic routes to replica
- Primary comes back online automatically

**Pass Criteria:**
- [ ] Primary failure detected within 20 seconds
- [ ] Traffic automatically routes to replica
- [ ] Keycloak remains accessible
- [ ] No data loss
- [ ] Primary recovers successfully

### Test 4.2: PostgreSQL Primary Failure

**Objective:** Verify automatic failover to replica PostgreSQL

**Test Steps:**

1. **Verify initial state:**
```bash
./haproxy/scripts/check-backends.sh
# Both PostgreSQL servers should be UP
```

2. **Stop primary PostgreSQL:**
```bash
ssh server-a
docker stop postgres-primary
```

3. **Monitor failover:**
```bash
# Watch HAProxy stats
watch -n 1 './haproxy/scripts/check-backends.sh'

# Test connection
time psql -h $HAPROXY_IP -p 5432 -U keycloak -d keycloak -c "SELECT 1;"
```

4. **Verify failover:**
```bash
# Check stats
curl -u $STATS_USER:$STATS_PASS http://$HAPROXY_IP:8404/stats | \
  grep postgres

# Test read query (should work on replica)
psql -h $HAPROXY_IP -p 5432 -U keycloak -d keycloak -c \
  "SELECT COUNT(*) FROM realm;"
```

5. **Restore primary:**
```bash
ssh server-a
docker start postgres-primary
```

**Expected Results:**
- Failover detection: ~9 seconds (3 failed checks × 3s)
- Read queries work on replica
- Write queries may fail (replica is read-only)
- Primary comes back online automatically

**Pass Criteria:**
- [ ] Primary failure detected within 15 seconds
- [ ] Traffic automatically routes to replica
- [ ] Read queries work on replica
- [ ] Primary recovers successfully

### Test 4.3: Automated Failover Test

**Objective:** Use automated script to test failover

```bash
# Test Keycloak failover
./haproxy/scripts/test-failover.sh keycloak

# Test PostgreSQL failover
./haproxy/scripts/test-failover.sh postgres
```

**Pass Criteria:**
- [ ] Script completes without errors
- [ ] Failover times within acceptable range
- [ ] Services recover automatically

## Performance Tests

### Test 5.1: HTTP Load Test

**Objective:** Measure HAProxy performance under load

```bash
# Using Apache Bench
ab -n 1000 -c 10 https://$HAPROXY_IP/

# Using wrk (if available)
wrk -t10 -c10 -d30s https://$HAPROXY_IP/
```

**Metrics to Record:**
- Requests per second
- Average latency
- 95th percentile latency
- Error rate

**Pass Criteria:**
- [ ] No connection errors
- [ ] Error rate < 1%
- [ ] Average latency < 500ms
- [ ] 95th percentile < 1000ms

### Test 5.2: PostgreSQL Load Test

**Objective:** Test database connection pooling under load

```bash
# Using pgbench (if available)
pgbench -h $HAPROXY_IP -p 5432 -U keycloak -d keycloak \
  -c 10 -j 10 -t 100

# Or manual test
for i in {1..100}; do
  psql -h $HAPROXY_IP -p 5432 -U keycloak -d keycloak \
    -c "SELECT COUNT(*) FROM realm;" &
done
wait
```

**Pass Criteria:**
- [ ] All queries successful
- [ ] No connection errors
- [ ] Acceptable query times

### Test 5.3: Concurrent User Test

**Objective:** Simulate multiple users accessing Keycloak

**Steps:**
1. Use load testing tool (JMeter, Gatling, etc.)
2. Simulate 50-100 concurrent users
3. Perform login operations
4. Monitor HAProxy stats

**Pass Criteria:**
- [ ] All requests successful
- [ ] No authentication errors
- [ ] Response times acceptable
- [ ] HAProxy handles load well

## Security Tests

### Test 6.1: SSL/TLS Configuration

**Objective:** Verify SSL/TLS security

```bash
# Test SSL configuration
nmap --script ssl-enum-ciphers -p 443 $HAPROXY_IP

# Or using testssl.sh
./testssl.sh https://$HAPROXY_IP/
```

**Pass Criteria:**
- [ ] TLS 1.2+ only
- [ ] Strong cipher suites only
- [ ] No SSL/TLS vulnerabilities

### Test 6.2: Security Headers

**Objective:** Verify security headers are present

```bash
# Check security headers
curl -k -I https://$HAPROXY_IP/ | grep -i "strict-transport-security\|x-frame-options\|x-content-type-options"
```

**Expected Headers:**
```
strict-transport-security: max-age=31536000; includeSubDomains
x-frame-options: DENY
x-content-type-options: nosniff
x-xss-protection: 1; mode=block
```

**Pass Criteria:**
- [ ] HSTS header present
- [ ] X-Frame-Options present
- [ ] X-Content-Type-Options present
- [ ] X-XSS-Protection present

### Test 6.3: Stats Page Authentication

**Objective:** Verify stats page requires authentication

```bash
# Test without credentials (should fail)
curl http://$HAPROXY_IP:8404/stats

# Test with wrong credentials (should fail)
curl -u wrong:wrong http://$HAPROXY_IP:8404/stats

# Test with correct credentials (should succeed)
curl -u $STATS_USER:$STATS_PASS http://$HAPROXY_IP:8404/stats
```

**Pass Criteria:**
- [ ] Unauthorized access denied
- [ ] Wrong credentials rejected
- [ ] Correct credentials accepted

## Monitoring Tests

### Test 7.1: Stats Page Functionality

**Objective:** Verify stats page shows correct information

**Steps:**
1. Open `http://$HAPROXY_IP:8404/stats` in browser
2. Login with credentials
3. Verify all backends visible
4. Check backend status
5. Review metrics

**Pass Criteria:**
- [ ] Stats page loads
- [ ] All backends visible
- [ ] Status indicators correct
- [ ] Metrics updating

### Test 7.2: Prometheus Metrics

**Objective:** Verify Prometheus metrics endpoint

```bash
# Get metrics
curl http://$HAPROXY_IP:8404/metrics

# Check specific metrics
curl http://$HAPROXY_IP:8404/metrics | grep haproxy_backend_up
```

**Pass Criteria:**
- [ ] Metrics endpoint accessible
- [ ] Metrics in Prometheus format
- [ ] Backend status metrics present
- [ ] Request metrics present

### Test 7.3: Health Check Endpoint

**Objective:** Verify health check endpoint

```bash
# Test health endpoint
curl http://$HAPROXY_IP:8404/health

# Should return HTTP 200
```

**Pass Criteria:**
- [ ] Health endpoint accessible
- [ ] Returns HTTP 200
- [ ] Response immediate

### Test 7.4: Logging

**Objective:** Verify logging is working

```bash
# Check HAProxy logs
docker logs haproxy-lb --tail 100

# Generate some traffic
curl -k https://$HAPROXY_IP/

# Check logs again
docker logs haproxy-lb --tail 10
```

**Pass Criteria:**
- [ ] Logs are generated
- [ ] HTTP requests logged
- [ ] Backend health checks logged
- [ ] Log format correct

## Test Results Documentation

### Test Summary Template

```
Test Date: _______________
Tester: _______________
Environment: [ ] Test [ ] Staging [ ] Production

HAProxy Version: _______________
Server IPs:
  - HAProxy: _______________
  - Primary: _______________
  - Replica: _______________

Test Results:
  Basic Connectivity:     [ ] Pass [ ] Fail
  Keycloak Functionality: [ ] Pass [ ] Fail
  PostgreSQL Connectivity:[ ] Pass [ ] Fail
  Failover Tests:         [ ] Pass [ ] Fail
  Performance Tests:      [ ] Pass [ ] Fail
  Security Tests:         [ ] Pass [ ] Fail
  Monitoring Tests:       [ ] Pass [ ] Fail

Issues Found:
_________________________________________________________________
_________________________________________________________________
_________________________________________________________________

Recommendations:
_________________________________________________________________
_________________________________________________________________
_________________________________________________________________

Sign-off: _______________  Date: _______________
```

### Performance Metrics Template

```
Load Test Results:

HTTP Performance:
  - Requests/sec: _______________
  - Avg Latency: _______________
  - 95th Percentile: _______________
  - Error Rate: _______________

PostgreSQL Performance:
  - Queries/sec: _______________
  - Avg Query Time: _______________
  - Connection Errors: _______________

Failover Times:
  - Keycloak Failover: _______________
  - PostgreSQL Failover: _______________
```

## Automated Testing Script

Untuk menjalankan semua test secara otomatis:

```bash
# Run all tests
./haproxy/scripts/integration-test.sh

# Run specific test category
./haproxy/scripts/integration-test.sh --category connectivity
./haproxy/scripts/integration-test.sh --category failover
./haproxy/scripts/integration-test.sh --category performance
```

## Troubleshooting Test Failures

Jika test gagal, lihat:
- [HAPROXY-TROUBLESHOOTING.md](../HAPROXY-TROUBLESHOOTING.md)
- [QUICK-REFERENCE.md](./QUICK-REFERENCE.md)
- HAProxy logs: `docker logs haproxy-lb`
- Backend logs: `docker logs keycloak-primary`, `docker logs postgres-primary`

---

**Testing Guide Version:** 1.0  
**Last Updated:** 2024
