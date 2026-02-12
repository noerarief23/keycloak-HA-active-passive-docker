# HAProxy Quick Reference Guide

## Quick Commands

### Deployment

```bash
# Deploy HAProxy
cd haproxy/scripts && ./deploy-haproxy.sh

# Validate configuration
./haproxy/scripts/validate-config.sh

# Check backend health
./haproxy/scripts/check-backends.sh
```

### Management

```bash
# Start HAProxy
docker compose -f docker-compose-lb.yml up -d

# Stop HAProxy
docker compose -f docker-compose-lb.yml stop

# Restart HAProxy
docker compose -f docker-compose-lb.yml restart

# View logs
docker logs haproxy-lb
docker logs -f haproxy-lb  # Follow logs

# Reload configuration (no downtime)
docker exec haproxy-lb kill -HUP 1
```

### Testing

```bash
# Run integration tests
./haproxy/scripts/integration-test.sh

# Test failover
./haproxy/scripts/test-failover.sh keycloak
./haproxy/scripts/test-failover.sh postgres

# Load testing
./haproxy/scripts/load-test.sh
```

### Monitoring

```bash
# Stats page (browser)
http://server-ip:8404/stats

# Stats CSV (command line)
curl -u admin:password http://localhost:8404/stats\;csv

# Prometheus metrics
curl http://localhost:8404/metrics

# Health check
curl http://localhost:8404/health
```

## Access Points

| Service | URL/Address | Notes |
|---------|-------------|-------|
| HTTP | http://server-ip/ | Redirects to HTTPS |
| HTTPS | https://server-ip/ | SSL/TLS terminated |
| PostgreSQL | server-ip:5432 | TCP proxy |
| Stats Page | http://server-ip:8404/stats | Requires auth |
| Metrics | http://server-ip:8404/metrics | Prometheus format |
| Health | http://server-ip:8404/health | Returns 200 OK |

## Configuration Files

| File | Purpose |
|------|---------|
| `haproxy/haproxy.cfg` | Main HAProxy configuration |
| `docker-compose-lb.yml` | Docker Compose setup |
| `.env` | Environment variables |
| `haproxy/certs/keycloak.pem` | SSL certificate |

## Environment Variables

```bash
# Stats authentication
HAPROXY_STATS_USER=admin
HAPROXY_STATS_PASSWORD=your_password

# Backend servers
PRIMARY_SERVER_IP=<server-a-ip>
REPLICA_SERVER_IP=<server-b-ip>
```

## Health Check Status

### Keycloak Backend
- **Endpoint:** `/health/ready`
- **Interval:** 5 seconds
- **Fail threshold:** 3 checks (15 seconds)
- **Rise threshold:** 2 checks (10 seconds)

### PostgreSQL Backend
- **Method:** pgsql-check
- **Interval:** 3 seconds
- **Fail threshold:** 3 checks (9 seconds)
- **Rise threshold:** 2 checks (6 seconds)

## Troubleshooting

### HAProxy won't start
```bash
# Check configuration syntax
docker run --rm -v $(pwd)/haproxy:/usr/local/etc/haproxy:ro \
  haproxy:2.9-alpine haproxy -c -f /usr/local/etc/haproxy/haproxy.cfg

# Check logs
docker logs haproxy-lb
```

### Backends showing DOWN
```bash
# Check backend connectivity
ping <server-a-ip>
telnet <server-a-ip> 8080

# Check backend services
docker ps | grep keycloak
docker ps | grep postgres

# Check firewall
sudo ufw status
```

### SSL certificate issues
```bash
# Check certificate
openssl x509 -in haproxy/certs/keycloak.pem -noout -text

# Check expiration
openssl x509 -in haproxy/certs/keycloak.pem -noout -enddate

# Regenerate self-signed
cd haproxy/scripts && ./generate-cert.sh keycloak.local
```

## Maintenance Tasks

### Daily
- Check backend health: `./haproxy/scripts/check-backends.sh`
- Review logs: `docker logs haproxy-lb --tail 100`

### Weekly
- Check certificate expiration
- Review stats page for errors
- Check disk space

### Monthly
- Update Docker image: `docker compose -f docker-compose-lb.yml pull`
- Review and rotate logs
- Test failover procedures

### Quarterly
- Renew SSL certificates
- Review and update configuration
- Perform load testing

## Common Operations

### Update Configuration
```bash
# 1. Edit configuration
nano haproxy/haproxy.cfg

# 2. Validate
./haproxy/scripts/validate-config.sh

# 3. Reload (no downtime)
docker exec haproxy-lb kill -HUP 1
```

### Renew SSL Certificate
```bash
# For Let's Encrypt
sudo certbot renew
sudo cat /etc/letsencrypt/live/domain/fullchain.pem \
         /etc/letsencrypt/live/domain/privkey.pem \
         > haproxy/certs/keycloak.pem
chmod 600 haproxy/certs/keycloak.pem
docker exec haproxy-lb kill -HUP 1
```

### Rollback Configuration
```bash
./haproxy/scripts/rollback-haproxy.sh
```

### Add Backend Server
```bash
# 1. Edit haproxy.cfg
nano haproxy/haproxy.cfg

# Add server line:
# server new-server <new-server-ip>:8080 check inter 5s fall 3 rise 2

# 2. Validate and reload
./haproxy/scripts/validate-config.sh
docker exec haproxy-lb kill -HUP 1
```

## Performance Tuning

### Increase Connection Limits
```ini
# In haproxy.cfg global section
maxconn 8192  # Increase from 4096
```

### Adjust Timeouts
```ini
# In defaults section
timeout connect 10000ms
timeout client  60000ms
timeout server  60000ms
```

### Enable HTTP Keep-Alive
```ini
# In defaults section
option http-keep-alive
timeout http-keep-alive 30000ms
```

## Security Checklist

- [ ] Change default stats password
- [ ] Use production SSL certificates
- [ ] Restrict stats page access by IP
- [ ] Enable firewall rules
- [ ] Set secure file permissions (600 for certs)
- [ ] Regularly update HAProxy image
- [ ] Monitor for security advisories
- [ ] Use strong cipher suites
- [ ] Enable HSTS header
- [ ] Disable unnecessary features

## Useful Links

- [HAProxy Documentation](https://www.haproxy.com/documentation/)
- [HAProxy Configuration Manual](https://cbonte.github.io/haproxy-dconv/)
- [Deployment Guide](../HAPROXY.md)
- [Troubleshooting Guide](../HAPROXY-TROUBLESHOOTING.md)
- [Completion Summary](./COMPLETION-SUMMARY.md)

## Support

For detailed information, see:
- **Deployment:** [HAPROXY.md](../HAPROXY.md)
- **Troubleshooting:** [HAPROXY-TROUBLESHOOTING.md](../HAPROXY-TROUBLESHOOTING.md)
- **Operations:** [OPERATIONS.md](../OPERATIONS.md)

---

**Quick Reference Version:** 1.0  
**Last Updated:** 2024
