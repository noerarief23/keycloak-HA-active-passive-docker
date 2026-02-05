# HAProxy Load Balancer

HAProxy load balancer untuk Keycloak High Availability setup dengan PostgreSQL streaming replication.

## 📁 Struktur Direktori

```
haproxy/
├── certs/              # SSL/TLS certificates
│   ├── README.md       # Certificate management guide
│   └── .gitignore      # Exclude sensitive files
├── errors/             # Custom error pages
│   ├── 400.http
│   ├── 403.http
│   ├── 408.http
│   ├── 500.http
│   ├── 502.http
│   ├── 503.http
│   └── 504.http
├── scripts/            # Operational scripts
│   ├── check-backends.sh       # Monitor backend health
│   ├── combine-cert.sh         # Combine SSL certificates
│   ├── deploy-haproxy.sh       # Automated deployment
│   ├── generate-cert.sh        # Generate self-signed certs
│   ├── integration-test.sh     # Integration tests
│   ├── load-test.sh            # Performance testing
│   ├── rollback-haproxy.sh     # Configuration rollback
│   ├── test-failover.sh        # Failover testing
│   └── validate-config.sh      # Configuration validation
├── haproxy.cfg         # Main HAProxy configuration
├── COMPLETION-SUMMARY.md       # Implementation summary
├── DEPLOYMENT-CHECKLIST.md     # Deployment checklist
├── QUICK-REFERENCE.md          # Quick command reference
├── TESTING-GUIDE.md            # Testing procedures
└── README.md                   # This file
```

## 🚀 Quick Start

### 1. Deploy HAProxy

```bash
cd scripts
./deploy-haproxy.sh
```

### 2. Check Status

```bash
./check-backends.sh
```

### 3. Access Services

- **Stats Page:** http://server-ip:8404/stats
- **Keycloak:** https://server-ip/
- **PostgreSQL:** server-ip:5432
- **Metrics:** http://server-ip:8404/metrics

## 📖 Documentation

### Getting Started
- **[DEPLOYMENT-CHECKLIST.md](DEPLOYMENT-CHECKLIST.md)** - Step-by-step deployment
- **[../HAPROXY.md](../HAPROXY.md)** - Complete deployment guide
- **[QUICK-REFERENCE.md](QUICK-REFERENCE.md)** - Command reference

### Testing
- **[TESTING-GUIDE.md](TESTING-GUIDE.md)** - Comprehensive testing guide
- **[scripts/integration-test.sh](scripts/integration-test.sh)** - Automated tests
- **[scripts/test-failover.sh](scripts/test-failover.sh)** - Failover tests

### Operations
- **[../OPERATIONS.md](../OPERATIONS.md)** - Daily operations
- **[../HAPROXY-TROUBLESHOOTING.md](../HAPROXY-TROUBLESHOOTING.md)** - Troubleshooting
- **[QUICK-REFERENCE.md](QUICK-REFERENCE.md)** - Quick commands

### Reference
- **[COMPLETION-SUMMARY.md](COMPLETION-SUMMARY.md)** - Implementation details
- **[haproxy.cfg](haproxy.cfg)** - Configuration file
- **[certs/README.md](certs/README.md)** - Certificate management

## 🔧 Common Commands

### Deployment
```bash
# Deploy HAProxy
./scripts/deploy-haproxy.sh

# Validate configuration
./scripts/validate-config.sh

# Check backend health
./scripts/check-backends.sh
```

### Management
```bash
# Start HAProxy
docker compose -f ../docker-compose-lb.yml up -d

# Stop HAProxy
docker compose -f ../docker-compose-lb.yml stop

# Restart HAProxy
docker compose -f ../docker-compose-lb.yml restart

# View logs
docker logs haproxy-lb

# Reload configuration (no downtime)
docker exec haproxy-lb kill -HUP 1
```

### Testing
```bash
# Run integration tests
./scripts/integration-test.sh

# Test failover
./scripts/test-failover.sh keycloak
./scripts/test-failover.sh postgres

# Load testing
./scripts/load-test.sh
```

### Monitoring
```bash
# Check backend health
./scripts/check-backends.sh

# View stats (browser)
# http://server-ip:8404/stats

# Get metrics
curl http://localhost:8404/metrics

# Check health
curl http://localhost:8404/health
```

## 🎯 Features

### High Availability
- ✅ Automatic failover detection
- ✅ Health checks every 3-5 seconds
- ✅ Zero-configuration failover
- ✅ Backup server activation

### SSL/TLS
- ✅ SSL/TLS termination
- ✅ TLS 1.2+ only
- ✅ Strong cipher suites
- ✅ HTTP to HTTPS redirect

### Monitoring
- ✅ Real-time stats dashboard
- ✅ Prometheus metrics export
- ✅ Health check endpoint
- ✅ Detailed logging

### Security
- ✅ Security headers (HSTS, X-Frame-Options, etc.)
- ✅ Stats page authentication
- ✅ Secure file permissions
- ✅ Network isolation

## 📊 Architecture

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

## 🔒 Security

### SSL/TLS Configuration
- TLS 1.2 and 1.3 only
- Strong cipher suites (ECDHE, AES-GCM, ChaCha20)
- Forward secrecy (DH parameters)
- Certificate validation

### Security Headers
- Strict-Transport-Security (HSTS)
- X-Frame-Options: DENY
- X-Content-Type-Options: nosniff
- X-XSS-Protection: 1; mode=block

### Access Control
- Stats page authentication
- Secure file permissions (600 for certs)
- Network isolation
- Firewall rules

## 🧪 Testing

### Automated Tests

```bash
# Validate configuration
./scripts/validate-config.sh

# Run integration tests
./scripts/integration-test.sh

# Test failover
./scripts/test-failover.sh keycloak
./scripts/test-failover.sh postgres

# Load testing
./scripts/load-test.sh
```

### Manual Tests

See [TESTING-GUIDE.md](TESTING-GUIDE.md) for:
- Basic connectivity tests
- Keycloak functionality tests
- PostgreSQL connectivity tests
- Failover tests
- Performance tests
- Security tests
- Monitoring tests

## 🚨 Troubleshooting

### Quick Diagnostics

```bash
# Check if HAProxy is running
docker ps | grep haproxy

# View logs
docker logs haproxy-lb

# Check backend health
./scripts/check-backends.sh

# Validate configuration
./scripts/validate-config.sh
```

### Common Issues

1. **Backends showing DOWN**
   - Check backend services: `docker ps`
   - Test connectivity: `ping <backend-ip>`
   - Check firewall: `sudo ufw status`

2. **SSL certificate errors**
   - Check certificate: `ls -la certs/keycloak.pem`
   - Verify expiration: `openssl x509 -in certs/keycloak.pem -noout -enddate`
   - Regenerate: `./scripts/generate-cert.sh keycloak.local`

3. **Cannot access stats**
   - Check credentials in `.env` file
   - Test: `curl -u admin:password http://localhost:8404/stats`
   - Check firewall: `sudo ufw allow 8404/tcp`

See [../HAPROXY-TROUBLESHOOTING.md](../HAPROXY-TROUBLESHOOTING.md) for detailed troubleshooting.

## 📈 Monitoring

### Key Metrics

Monitor these in stats page or Prometheus:
- Backend status (UP/DOWN)
- Response times
- Request rates
- Error rates
- Connection counts
- Health check status

### Access Points

| Service | URL | Auth |
|---------|-----|------|
| Stats Page | http://server-ip:8404/stats | Required |
| Prometheus | http://server-ip:8404/metrics | No |
| Health | http://server-ip:8404/health | No |

## 🔄 Maintenance

### Daily
```bash
./scripts/check-backends.sh
docker logs haproxy-lb --tail 100
```

### Weekly
```bash
# Check certificate expiration
openssl x509 -in certs/keycloak.pem -noout -enddate

# Review stats page
# http://server-ip:8404/stats
```

### Monthly
```bash
# Update Docker image
docker compose -f ../docker-compose-lb.yml pull
docker compose -f ../docker-compose-lb.yml up -d

# Test failover
./scripts/test-failover.sh keycloak
```

### Configuration Updates
```bash
# Edit configuration
nano haproxy.cfg

# Validate
./scripts/validate-config.sh

# Reload (no downtime)
docker exec haproxy-lb kill -HUP 1
```

## 📞 Support

### Documentation
- [DEPLOYMENT-CHECKLIST.md](DEPLOYMENT-CHECKLIST.md) - Deployment guide
- [TESTING-GUIDE.md](TESTING-GUIDE.md) - Testing procedures
- [QUICK-REFERENCE.md](QUICK-REFERENCE.md) - Command reference
- [../HAPROXY.md](../HAPROXY.md) - Complete guide
- [../HAPROXY-TROUBLESHOOTING.md](../HAPROXY-TROUBLESHOOTING.md) - Troubleshooting

### Scripts
All scripts in `scripts/` directory with detailed help:
```bash
./scripts/deploy-haproxy.sh --help
./scripts/validate-config.sh --help
./scripts/integration-test.sh --help
```

### Community
- GitHub: [Repository](https://github.com/noerarief23/keycloak-HA-active-passive-docker)
- HAProxy Docs: [haproxy.com/documentation](https://www.haproxy.com/documentation/)

## ✅ Status

**Implementation:** ✅ COMPLETE  
**Production Ready:** ✅ YES  
**Version:** 1.0  
**Last Updated:** 2024

---

**Ready to deploy!** Start with `./scripts/deploy-haproxy.sh`
