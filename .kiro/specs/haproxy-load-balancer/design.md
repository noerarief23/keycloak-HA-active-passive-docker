# HAProxy Load Balancer Design Document

## Overview

This design document describes the integration of HAProxy as a load balancer for the existing Keycloak High Availability setup with PostgreSQL streaming replication. HAProxy will provide a single entry point for all client connections, perform health checks on backend services, and automatically route traffic to healthy nodes during failover scenarios.

### Design Goals

1. **High Availability**: Ensure continuous service availability during node failures
2. **Transparent Failover**: Automatic detection and routing without manual intervention
3. **Performance**: Minimal latency overhead from load balancing
4. **Observability**: Comprehensive monitoring and logging capabilities
5. **Security**: SSL/TLS termination and secure access controls
6. **Simplicity**: Easy to deploy, configure, and maintain

### Architecture Decision

We chose HAProxy over alternatives (Nginx, Kong, Traefik) because:
- **Mature and Stable**: Battle-tested in production environments for 20+ years
- **Lightweight**: Minimal resource footprint (~10MB memory)
- **Advanced Health Checks**: Native PostgreSQL health checking with `pgsql-check`
- **High Performance**: Can handle 100k+ concurrent connections
- **Simple Configuration**: Clear, declarative configuration syntax
- **Active/Passive Optimized**: Excellent support for failover scenarios

## Architecture

### Network Topology

```
                                    Internet/Clients
                                           │
                                           │
                                           ▼
                              ┌────────────────────────┐
                              │   Server C (New)       │
                              │                        │
                              │   ┌────────────────┐   │
                              │   │   HAProxy      │   │
                              │   │                │   │
                              │   │  HTTP: 80/443  │   │
                              │   │  PG: 5432      │   │
                              │   │  Stats: 8404   │   │
                              │   └────────┬───────┘   │
                              └────────────┼───────────┘
                                           │
                    ┌──────────────────────┼──────────────────────┐
                    │                      │                      │
                    ▼                      ▼                      ▼
         ┌──────────────────┐   ┌──────────────────┐   ┌──────────────────┐
         │   Server A       │   │   Server B       │   │   Health Checks  │
         │   (Primary)      │   │   (Replica)      │   │                  │
         │                  │   │                  │   │  Keycloak:       │
         │  Keycloak:8080   │   │  Keycloak:8081   │   │  /health/ready   │
         │  PostgreSQL:5432 │   │  PostgreSQL:5433 │   │                  │
         │                  │   │                  │   │  PostgreSQL:     │
         │  [ACTIVE]        │   │  [STANDBY]       │   │  pgsql-check     │
         └──────────────────┘   └──────────────────┘   └──────────────────┘
```

### Component Placement

**Server C (Load Balancer Server)**
- HAProxy container
- SSL certificates storage
- Configuration files
- Log aggregation point

**Server A (Primary)**
- Keycloak primary (active)
- PostgreSQL primary (read/write)
- Registered as primary backend in HAProxy

**Server B (Replica)**
- Keycloak replica (standby, started during failover)
- PostgreSQL replica (read-only, promoted during failover)
- Registered as backup backend in HAProxy

## Components and Interfaces

### 1. HAProxy Container

**Image**: `haproxy:2.9-alpine`
- Latest stable version with Alpine Linux for minimal size
- Includes all necessary modules for HTTP and TCP load balancing
- Native PostgreSQL health check support

**Exposed Ports**:
- `80`: HTTP frontend for Keycloak (redirects to HTTPS)
- `443`: HTTPS frontend for Keycloak (SSL termination)
- `5432`: PostgreSQL frontend for database connections
- `8404`: Statistics and monitoring interface

**Volumes**:
- `./haproxy/haproxy.cfg:/usr/local/etc/haproxy/haproxy.cfg:ro` - Main configuration
- `./haproxy/certs:/etc/haproxy/certs:ro` - SSL certificates
- `./haproxy/errors:/etc/haproxy/errors:ro` - Custom error pages

**Environment Variables**:
- `HAPROXY_STATS_USER`: Username for stats page authentication
- `HAPROXY_STATS_PASSWORD`: Password for stats page authentication

### 2. HAProxy Configuration Structure

The `haproxy.cfg` file will be organized into the following sections:

#### Global Section
```
global
    log stdout format raw local0
    maxconn 4096
    ssl-default-bind-ciphers ECDHE-RSA-AES128-GCM-SHA256:...
    ssl-default-bind-options ssl-min-ver TLSv1.2
    stats socket /var/run/haproxy.sock mode 660 level admin
    stats timeout 30s
```

#### Defaults Section
```
defaults
    log     global
    mode    http
    option  httplog
    option  dontlognull
    timeout connect 5000ms
    timeout client  50000ms
    timeout server  50000ms
```

#### Frontend Sections

**HTTP Frontend (Port 80)**
- Redirects all traffic to HTTPS
- Captures X-Forwarded-For headers
- Logs all requests

**HTTPS Frontend (Port 443)**
- SSL/TLS termination
- Routes to Keycloak backend
- Adds security headers
- Session affinity (not useful for failover but good for performance)

**PostgreSQL Frontend (Port 5432)**
- TCP mode
- Routes to PostgreSQL backend
- Connection timeout: 10 seconds
- Client timeout: 1 hour

**Stats Frontend (Port 8404)**
- HTTP basic authentication
- Read-only access to statistics
- JSON API endpoint available

#### Backend Sections

**Keycloak Backend**
```
backend keycloak_backend
    mode http
    balance roundrobin
    option httpchk GET /health/ready
    http-check expect status 200
    
    server keycloak-primary 172.20.0.11:8080 check inter 5s fall 3 rise 2
    server keycloak-replica 172.20.0.21:8080 check inter 5s fall 3 rise 2 backup
```

**PostgreSQL Backend**
```
backend postgres_backend
    mode tcp
    balance roundrobin
    option pgsql-check user haproxy_check
    
    server postgres-primary <SERVER_A_IP>:5432 check inter 3s fall 3 rise 2
    server postgres-replica <SERVER_B_IP>:5433 check inter 3s fall 3 rise 2 backup
```

### 3. Health Check Mechanisms

#### Keycloak Health Checks

**Method**: HTTP GET request to `/health/ready`

**Check Parameters**:
- `inter 5s`: Check every 5 seconds
- `fall 3`: Mark down after 3 consecutive failures
- `rise 2`: Mark up after 2 consecutive successes
- `timeout 3s`: Health check timeout

**Expected Response**: HTTP 200 OK

**Failure Scenarios**:
- Keycloak container stopped
- Keycloak not fully started
- Database connection lost
- Application error

#### PostgreSQL Health Checks

**Method**: Native `pgsql-check` with dedicated check user

**Check Parameters**:
- `inter 3s`: Check every 3 seconds (faster than Keycloak)
- `fall 3`: Mark down after 3 consecutive failures
- `rise 2`: Mark up after 2 consecutive successes
- `timeout 2s`: Health check timeout

**Check User**: `haproxy_check` (read-only user with minimal privileges)

**Verification**:
1. TCP connection successful
2. PostgreSQL accepts authentication
3. Database is not in recovery mode (for primary)

**Failure Scenarios**:
- PostgreSQL container stopped
- Network connectivity lost
- Database in recovery mode (replica not yet promoted)
- Too many connections

### 4. SSL/TLS Configuration

#### Certificate Structure

**Directory**: `./haproxy/certs/`

**Files**:
- `keycloak.pem`: Combined certificate and private key for Keycloak domain
- `dhparam.pem`: Diffie-Hellman parameters for forward secrecy (2048-bit)

**Certificate Format**:
```
-----BEGIN CERTIFICATE-----
[Certificate content]
-----END CERTIFICATE-----
-----BEGIN PRIVATE KEY-----
[Private key content]
-----END PRIVATE KEY-----
```

#### TLS Configuration

**Supported Protocols**: TLS 1.2, TLS 1.3

**Cipher Suites** (in order of preference):
1. `ECDHE-RSA-AES128-GCM-SHA256`
2. `ECDHE-RSA-AES256-GCM-SHA384`
3. `ECDHE-RSA-CHACHA20-POLY1305`

**Security Headers** (added by HAProxy):
- `Strict-Transport-Security: max-age=31536000`
- `X-Frame-Options: DENY`
- `X-Content-Type-Options: nosniff`
- `X-XSS-Protection: 1; mode=block`

#### Certificate Management

**Self-Signed Certificates** (for testing):
```bash
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout keycloak.key -out keycloak.crt \
  -subj "/CN=keycloak.local"
cat keycloak.crt keycloak.key > keycloak.pem
```

**Let's Encrypt Certificates** (for production):
- Use Certbot with DNS or HTTP challenge
- Automate renewal with cron job
- Combine fullchain.pem and privkey.pem

### 5. Failover Behavior

#### Scenario 1: Primary Keycloak Failure

**Detection**:
1. HAProxy sends GET request to `/health/ready` on primary
2. Request fails 3 consecutive times (15 seconds total)
3. Primary marked as DOWN

**Action**:
1. HAProxy immediately routes new requests to replica
2. Existing connections to primary are closed
3. Replica must be manually started (as per current architecture)
4. Once replica is UP, it receives all traffic

**Recovery**:
1. Primary comes back online
2. Passes 2 consecutive health checks (10 seconds)
3. Marked as UP
4. Becomes primary again (replica returns to backup role)

#### Scenario 2: Primary PostgreSQL Failure

**Detection**:
1. HAProxy performs `pgsql-check` on primary
2. Check fails 3 consecutive times (9 seconds total)
3. Primary marked as DOWN

**Action**:
1. HAProxy routes new connections to replica
2. Replica must be promoted to primary (manual step)
3. Once promoted and accepting writes, it receives all traffic
4. Existing connections are gracefully closed

**Recovery**:
1. Old primary rebuilt as new replica
2. Passes 2 consecutive health checks (6 seconds)
3. Marked as UP in backup role
4. Ready for next failover

#### Scenario 3: Complete Server Failure

**Detection**:
- All health checks fail (both Keycloak and PostgreSQL)
- Network unreachable

**Action**:
1. HAProxy marks all services on failed server as DOWN
2. Routes all traffic to surviving server
3. Administrator promotes replica services
4. System continues with single server

**Recovery**:
- Failed server repaired and brought back online
- Services registered as backup in HAProxy
- Failback performed during maintenance window

### 6. Monitoring and Observability

#### Statistics Page

**URL**: `http://<haproxy-server>:8404/stats`

**Authentication**: HTTP Basic Auth
- Username: From `HAPROXY_STATS_USER` environment variable
- Password: From `HAPROXY_STATS_PASSWORD` environment variable

**Metrics Displayed**:
- Frontend statistics (requests, errors, bytes)
- Backend statistics (active servers, health status)
- Server statistics (response times, connection counts)
- Health check results and state transitions

**Refresh Rate**: Auto-refresh every 5 seconds

#### Logging

**Log Format** (HTTP):
```
%ci:%cp [%tr] %ft %b/%s %TR/%Tw/%Tc/%Tr/%Ta %ST %B %CC %CS %tsc %ac/%fc/%bc/%sc/%rc %sq/%bq %hr %hs %{+Q}r
```

**Fields**:
- Client IP and port
- Request timestamp
- Frontend and backend names
- Timing information (total, queue, connect, response, active)
- Status code and bytes transferred
- Connection counts
- Request details

**Log Format** (PostgreSQL):
```
%ci:%cp [%t] %ft %b/%s %Tw/%Tc/%Tt %B %ts %ac/%fc/%bc/%sc/%rc %sq/%bq
```

**Log Destination**: Docker stdout (captured by Docker logging driver)

#### Prometheus Metrics

HAProxy exposes Prometheus-compatible metrics on the stats page:

**Endpoint**: `http://<haproxy-server>:8404/metrics`

**Key Metrics**:
- `haproxy_backend_up`: Backend server health status (0=down, 1=up)
- `haproxy_backend_response_time_average_seconds`: Average response time
- `haproxy_backend_current_sessions`: Current active sessions
- `haproxy_backend_http_responses_total`: Total HTTP responses by code
- `haproxy_frontend_http_requests_total`: Total frontend requests

### 7. Network Configuration

#### Docker Networks

**Option 1: Bridge Network with Host Networking**
- HAProxy uses host network mode
- Direct access to backend servers via their IP addresses
- Simplest configuration for multi-server setup

**Option 2: Overlay Network** (if using Docker Swarm)
- Create overlay network spanning all servers
- HAProxy and backends on same network
- Service discovery via DNS

**Option 3: External Network**
- HAProxy on separate network
- Routes to backends via external IPs
- Most flexible for hybrid deployments

**Recommended**: Option 1 for simplicity and performance

#### Firewall Rules

**Server C (HAProxy)**:
- Allow inbound: 80, 443, 5432, 8404
- Allow outbound: 8080, 8081 (to Keycloak servers)
- Allow outbound: 5432, 5433 (to PostgreSQL servers)

**Server A & B**:
- Allow inbound from Server C IP only
- Restrict direct client access

### 8. Configuration Files Structure

```
haproxy/
├── haproxy.cfg                 # Main HAProxy configuration
├── certs/
│   ├── keycloak.pem           # SSL certificate + private key
│   ├── dhparam.pem            # DH parameters
│   └── .gitignore             # Ignore private keys in git
├── errors/
│   ├── 400.http               # Custom 400 error page
│   ├── 403.http               # Custom 403 error page
│   ├── 408.http               # Custom 408 error page
│   ├── 500.http               # Custom 500 error page
│   ├── 502.http               # Custom 502 error page (backend down)
│   ├── 503.http               # Custom 503 error page (no backend)
│   └── 504.http               # Custom 504 error page (timeout)
└── scripts/
    ├── generate-cert.sh       # Generate self-signed certificate
    ├── test-failover.sh       # Test failover scenarios
    └── check-backends.sh      # Verify backend health
```

## Data Models

### HAProxy State

HAProxy maintains internal state for each backend server:

```
Server State {
    name: string                    # Server identifier
    address: string                 # IP:Port
    status: UP | DOWN | MAINT       # Current status
    weight: integer                 # Load balancing weight
    check_status: string            # Last health check result
    check_duration: integer         # Health check response time (ms)
    last_change: timestamp          # Last status change time
    downtime: integer               # Total downtime (seconds)
    current_sessions: integer       # Active connections
    total_sessions: integer         # Lifetime connection count
    bytes_in: integer              # Total bytes received
    bytes_out: integer             # Total bytes sent
    failed_checks: integer         # Consecutive failed checks
    role: primary | backup         # Server role
}
```

### Health Check Result

```
Health Check {
    server: string                  # Server name
    timestamp: datetime             # Check time
    result: PASS | FAIL            # Check outcome
    duration: integer              # Response time (ms)
    error: string?                 # Error message if failed
    check_type: http | tcp | pgsql # Check method
}
```

## Error Handling

### Backend Unavailable

**Scenario**: All backend servers are down

**Response**:
- HTTP 503 Service Unavailable
- Custom error page: "Service temporarily unavailable"
- Retry-After header: 30 seconds
- Log critical error

**Recovery**: Automatic when any backend becomes healthy

### SSL Certificate Error

**Scenario**: Certificate expired or invalid

**Response**:
- HAProxy fails to start
- Error logged to stdout
- Container health check fails

**Recovery**: Replace certificate and restart container

### Configuration Error

**Scenario**: Invalid haproxy.cfg syntax

**Response**:
- HAProxy fails to start
- Detailed error message in logs
- Container exits with error code

**Recovery**: Fix configuration and restart

### Health Check Timeout

**Scenario**: Backend responds slowly or not at all

**Response**:
- Health check marked as failed
- Contributes to fall count
- Logged as warning

**Recovery**: Automatic retry on next check interval

### Connection Limit Reached

**Scenario**: `maxconn` limit exceeded

**Response**:
- New connections queued
- If queue full, return 503
- Log warning

**Recovery**: Automatic as connections close

## Testing Strategy

### Unit Testing

**Configuration Validation**:
```bash
# Test configuration syntax
docker run --rm -v $(pwd)/haproxy:/usr/local/etc/haproxy:ro \
  haproxy:2.9-alpine haproxy -c -f /usr/local/etc/haproxy/haproxy.cfg
```

**Expected Output**: "Configuration file is valid"

### Integration Testing

**Test 1: Basic Connectivity**
```bash
# Test HTTP connection
curl -v http://<haproxy-ip>/

# Test HTTPS connection
curl -v -k https://<haproxy-ip>/

# Test PostgreSQL connection
psql -h <haproxy-ip> -p 5432 -U keycloak -d keycloak -c "SELECT 1;"
```

**Test 2: Health Check Verification**
```bash
# Check stats page
curl -u admin:password http://<haproxy-ip>:8404/stats

# Verify backend status
curl -u admin:password http://<haproxy-ip>:8404/stats\;csv | grep keycloak
```

**Test 3: Failover Simulation**
```bash
# Stop primary Keycloak
docker stop keycloak-primary

# Wait for failover (15 seconds)
sleep 15

# Verify traffic routes to replica
curl -v http://<haproxy-ip>/

# Check HAProxy logs
docker logs haproxy | grep "keycloak-primary.*DOWN"
```

**Test 4: PostgreSQL Failover**
```bash
# Stop primary PostgreSQL
docker stop postgres-primary

# Wait for failover (9 seconds)
sleep 10

# Verify connection routes to replica
psql -h <haproxy-ip> -p 5432 -U keycloak -d keycloak -c "SELECT 1;"

# Check HAProxy logs
docker logs haproxy | grep "postgres-primary.*DOWN"
```

### Load Testing

**Tool**: Apache Bench (ab) or wrk

**Test Scenario 1: HTTP Load**
```bash
# 1000 requests, 10 concurrent
ab -n 1000 -c 10 http://<haproxy-ip>/

# Expected: 0% failed requests, <100ms average response time
```

**Test Scenario 2: PostgreSQL Load**
```bash
# Use pgbench
pgbench -h <haproxy-ip> -p 5432 -U keycloak -d keycloak -c 10 -t 100

# Expected: All transactions successful
```

**Test Scenario 3: Failover Under Load**
```bash
# Start load test in background
ab -n 10000 -c 50 http://<haproxy-ip>/ &

# Wait 5 seconds
sleep 5

# Stop primary
docker stop keycloak-primary

# Wait for test to complete
wait

# Expected: Some failed requests during failover window, then recovery
```

### Security Testing

**Test 1: SSL Configuration**
```bash
# Test SSL/TLS configuration
nmap --script ssl-enum-ciphers -p 443 <haproxy-ip>

# Expected: Only TLS 1.2+ with strong ciphers
```

**Test 2: Stats Page Authentication**
```bash
# Test without credentials
curl http://<haproxy-ip>:8404/stats

# Expected: 401 Unauthorized

# Test with credentials
curl -u admin:password http://<haproxy-ip>:8404/stats

# Expected: 200 OK
```

### Monitoring Testing

**Test 1: Metrics Endpoint**
```bash
# Fetch Prometheus metrics
curl http://<haproxy-ip>:8404/metrics

# Expected: Valid Prometheus format with haproxy_* metrics
```

**Test 2: Log Verification**
```bash
# Generate traffic
curl http://<haproxy-ip>/

# Check logs
docker logs haproxy | tail -n 10

# Expected: Structured log entries with all required fields
```

## Performance Considerations

### Resource Requirements

**CPU**: 0.5-1 core (minimal overhead)
**Memory**: 128-256 MB (depends on maxconn)
**Network**: Minimal latency (<1ms added)
**Disk**: <100 MB (for logs)

### Tuning Parameters

**Connection Limits**:
- `maxconn 4096`: Maximum concurrent connections
- Adjust based on expected load
- Formula: (RAM_MB - 100) * 10

**Timeouts**:
- `timeout connect 5s`: Backend connection timeout
- `timeout client 50s`: Client inactivity timeout
- `timeout server 50s`: Backend inactivity timeout
- `timeout http-keep-alive 10s`: Keep-alive timeout

**Health Check Intervals**:
- Keycloak: 5s (balance between detection speed and overhead)
- PostgreSQL: 3s (faster detection for database)

### Scalability

**Vertical Scaling**:
- Increase `maxconn` for more concurrent connections
- Add more CPU cores for higher throughput
- Increase memory for larger connection tables

**Horizontal Scaling**:
- Deploy multiple HAProxy instances
- Use DNS round-robin or upstream load balancer
- Share SSL certificates via network storage

## Security Considerations

### Access Control

1. **Stats Page**: Protected by HTTP Basic Auth
2. **Backend Access**: Firewall rules restrict direct access
3. **SSL Certificates**: Stored with restricted permissions (600)
4. **Configuration**: Read-only mount in container

### Secrets Management

**Environment Variables**:
- `HAPROXY_STATS_USER`: Non-sensitive, can be in .env
- `HAPROXY_STATS_PASSWORD`: Sensitive, use Docker secrets or vault

**SSL Certificates**:
- Store in `./haproxy/certs/` with `.gitignore`
- Use Docker secrets for production
- Rotate annually or per policy

### Network Security

1. **TLS Only**: Redirect HTTP to HTTPS
2. **Strong Ciphers**: Disable weak algorithms
3. **HSTS**: Force HTTPS for 1 year
4. **Rate Limiting**: Prevent abuse (optional, can be added)

## Deployment Considerations

### Prerequisites

1. Server C with Docker installed
2. Network connectivity to Server A and B
3. SSL certificates (self-signed or CA-signed)
4. Firewall rules configured

### Deployment Steps

1. Create directory structure
2. Generate or copy SSL certificates
3. Configure haproxy.cfg with correct backend IPs
4. Create .env file with credentials
5. Start HAProxy container
6. Verify health checks
7. Update DNS to point to HAProxy
8. Test failover scenarios

### Rollback Plan

1. Update DNS to point directly to Server A
2. Stop HAProxy container
3. Verify direct access works
4. Investigate and fix HAProxy issues
5. Redeploy when ready

## Maintenance

### Regular Tasks

**Daily**:
- Check HAProxy stats page
- Verify all backends are UP
- Review error logs

**Weekly**:
- Test failover procedure
- Review performance metrics
- Check certificate expiration

**Monthly**:
- Update HAProxy image
- Review and optimize configuration
- Load testing

### Certificate Renewal

**Let's Encrypt** (automated):
```bash
# Renew certificate
certbot renew

# Combine files
cat /etc/letsencrypt/live/domain/fullchain.pem \
    /etc/letsencrypt/live/domain/privkey.pem \
    > haproxy/certs/keycloak.pem

# Reload HAProxy
docker kill -s HUP haproxy
```

**Manual Renewal**:
1. Obtain new certificate
2. Combine cert and key into .pem file
3. Replace old certificate
4. Reload HAProxy configuration

### Configuration Updates

```bash
# Edit configuration
nano haproxy/haproxy.cfg

# Validate syntax
docker run --rm -v $(pwd)/haproxy:/usr/local/etc/haproxy:ro \
  haproxy:2.9-alpine haproxy -c -f /usr/local/etc/haproxy/haproxy.cfg

# Reload without downtime
docker kill -s HUP haproxy
```

## Migration Path

### Phase 1: Deploy HAProxy
- Set up Server C with HAProxy
- Configure backends pointing to existing servers
- Test connectivity through HAProxy

### Phase 2: Parallel Operation
- Keep existing direct access available
- Route test traffic through HAProxy
- Monitor and tune configuration

### Phase 3: DNS Cutover
- Update DNS to point to HAProxy
- Monitor for issues
- Keep direct access as backup

### Phase 4: Cleanup
- Remove direct access firewall rules
- Update documentation
- Decommission old access methods

## Future Enhancements

### Potential Improvements

1. **Active-Active Keycloak**: Support multiple active Keycloak instances
2. **Read Replicas**: Route read-only queries to PostgreSQL replicas
3. **Rate Limiting**: Protect against abuse and DDoS
4. **WAF Integration**: Add Web Application Firewall rules
5. **Geo-Routing**: Route based on client location
6. **Auto-Scaling**: Dynamic backend registration
7. **Observability**: Integration with Prometheus/Grafana
8. **Automated Failback**: Automatic return to primary after recovery

### Compatibility

- Compatible with existing Active/Passive architecture
- No changes required to Keycloak or PostgreSQL configuration
- Can be deployed independently without affecting current setup
- Supports future migration to Active-Active if needed
