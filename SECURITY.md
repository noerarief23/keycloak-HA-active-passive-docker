# Security Best Practices and Checklist

This document outlines security best practices for the Keycloak HA Active/Passive setup.

## Pre-Deployment Security Checklist

### Passwords and Secrets

- [ ] Generate strong, random passwords for all services
  ```bash
  # Use openssl to generate secure passwords
  openssl rand -base64 32
  ```

- [ ] Never commit `.env` files to version control
  - Only commit `.env.example` files
  - Add `.env` to `.gitignore` (already done)

- [ ] Store production passwords in a secure vault
  - HashiCorp Vault
  - AWS Secrets Manager
  - Azure Key Vault
  - 1Password/LastPass for teams

- [ ] Use different passwords for each environment (dev/staging/prod)

- [ ] Rotate passwords regularly (every 90 days minimum)

### Network Security

- [ ] Configure firewall rules
  ```bash
  # On Primary Server
  sudo ufw allow from <replica-ip> to any port 5432
  sudo ufw allow from <trusted-ips> to any port 8080
  
  # On Replica Server
  sudo ufw allow from <primary-ip> to any port 5432
  sudo ufw allow from <trusted-ips> to any port 8081
  ```

- [ ] Use VPN or private network for replication traffic

- [ ] Implement network segmentation
  - Separate network for database replication
  - Separate network for application traffic
  - Isolated management network

- [ ] Enable DDoS protection

- [ ] Use fail2ban or similar tools

### SSL/TLS Configuration

#### PostgreSQL SSL

**On Primary Server:**

1. Generate SSL certificates:
   ```bash
   # Generate CA certificate
   openssl req -new -x509 -days 3650 -nodes -text \
     -out ca.crt -keyout ca.key -subj "/CN=PostgreSQL CA"
   
   # Generate server certificate
   openssl req -new -nodes -text -out server.csr \
     -keyout server.key -subj "/CN=postgres-primary"
   
   # Sign server certificate
   openssl x509 -req -in server.csr -text -days 3650 \
     -CA ca.crt -CAkey ca.key -CAcreateserial \
     -out server.crt
   ```

2. Add to `postgresql.conf`:
   ```ini
   ssl = on
   ssl_cert_file = '/etc/ssl/certs/server.crt'
   ssl_key_file = '/etc/ssl/private/server.key'
   ssl_ca_file = '/etc/ssl/certs/ca.crt'
   ```

3. Update `pg_hba.conf` to require SSL:
   ```
   hostssl  all             all             0.0.0.0/0               md5
   hostssl  replication     replicator      0.0.0.0/0               md5
   ```

4. Update Docker volume mounts to include certificates

#### Keycloak SSL

**Option 1: Use a reverse proxy (recommended)**

```yaml
services:
  nginx:
    image: nginx:alpine
    volumes:
      - ./nginx.conf:/etc/nginx/nginx.conf
      - ./ssl:/etc/nginx/ssl
    ports:
      - "443:443"
    depends_on:
      - keycloak-primary
```

**Option 2: Configure Keycloak directly**

```yaml
environment:
  - KC_HTTPS_ENABLED=true
  - KC_HTTPS_CERTIFICATE_FILE=/opt/keycloak/conf/server.crt
  - KC_HTTPS_CERTIFICATE_KEY_FILE=/opt/keycloak/conf/server.key
```

### Container Security

- [ ] Run containers as non-root user
  ```yaml
  user: "999:999"  # postgres user
  ```

- [ ] Use read-only root filesystem where possible
  ```yaml
  read_only: true
  tmpfs:
    - /tmp
    - /var/run
  ```

- [ ] Limit container capabilities
  ```yaml
  cap_drop:
    - ALL
  cap_add:
    - CHOWN
    - DAC_OVERRIDE
    - SETGID
    - SETUID
  ```

- [ ] Set resource limits
  ```yaml
  deploy:
    resources:
      limits:
        cpus: '2'
        memory: 4G
        pids: 100
  ```

- [ ] Use specific image tags, not `latest`
  ```yaml
  image: postgres:15.4-alpine  # Not postgres:15 or postgres:latest
  ```

- [ ] Scan images for vulnerabilities
  ```bash
  docker scan postgres:15-alpine
  docker scan quay.io/keycloak/keycloak:23.0
  ```

### PostgreSQL Security

- [ ] Disable trust authentication in production
  - Use `md5` or `scram-sha-256` instead of `trust`

- [ ] Implement strong password policy
  ```sql
  ALTER ROLE postgres WITH PASSWORD 'strong_password';
  ALTER ROLE replicator WITH PASSWORD 'strong_password';
  ALTER ROLE keycloak WITH PASSWORD 'strong_password';
  ```

- [ ] Limit connection sources in `pg_hba.conf`
  ```
  # Only allow specific IPs, not entire subnets if possible
  host    all             all             192.168.1.10/32         md5
  ```

- [ ] Enable SSL for all connections

- [ ] Configure connection limits
  ```ini
  max_connections = 100
  ```

- [ ] Enable query logging (but be careful with sensitive data)
  ```ini
  log_statement = 'ddl'  # or 'mod' or 'all'
  log_duration = on
  ```

- [ ] Disable unnecessary extensions
  ```sql
  DROP EXTENSION IF EXISTS plpython3u;
  ```

### Keycloak Security

- [ ] Use strong admin password (20+ characters)

- [ ] Enable brute force protection
  - Configure in Keycloak admin console
  - Realm Settings → Security Defenses → Brute Force Detection

- [ ] Configure password policies
  - Minimum length: 12 characters
  - Require uppercase, lowercase, numbers, special characters
  - Password history: 5
  - Expire passwords: 90 days

- [ ] Enable MFA for admin accounts

- [ ] Configure session timeouts
  - SSO Session Idle: 30 minutes
  - SSO Session Max: 10 hours
  - Access Token Lifespan: 5 minutes

- [ ] Disable unused features
  - Disable user registration if not needed
  - Disable user-managed access if not needed

- [ ] Regular security audits
  - Review user permissions
  - Review client configurations
  - Review realm settings

### Monitoring and Logging

- [ ] Enable audit logging
  ```yaml
  environment:
    - KC_LOG_LEVEL=INFO
    - KC_LOG=console,file
  ```

- [ ] Centralize logs (ELK, Splunk, etc.)
  ```yaml
  logging:
    driver: "syslog"
    options:
      syslog-address: "tcp://logserver:514"
  ```

- [ ] Monitor for suspicious activity
  - Failed login attempts
  - Privilege escalations
  - Unusual database queries
  - Large data exports

- [ ] Set up security alerts
  - Multiple failed login attempts
  - Database connection from unknown IP
  - Replication lag > threshold
  - Disk space critical

- [ ] Regular log review (weekly minimum)

### Backup Security

- [ ] Encrypt backups at rest
  ```bash
  # Encrypt backup
  openssl enc -aes-256-cbc -salt -in backup.sql -out backup.sql.enc
  
  # Decrypt backup
  openssl enc -d -aes-256-cbc -in backup.sql.enc -out backup.sql
  ```

- [ ] Encrypt backups in transit
  - Use SFTP/SCP instead of FTP
  - Use encrypted cloud storage (S3 with encryption)

- [ ] Store backups offsite
  - Different datacenter
  - Different cloud region
  - Physical media in secure location

- [ ] Test backup restoration regularly

- [ ] Implement backup retention policy
  - 7 daily backups
  - 4 weekly backups
  - 12 monthly backups
  - Comply with regulatory requirements

- [ ] Secure backup credentials
  - Don't store with backups
  - Rotate regularly

### Access Control

- [ ] Implement least privilege principle
  - Database users only have necessary permissions
  - Application users only access what they need

- [ ] Use separate accounts for different purposes
  - Admin account (limited use)
  - Application account (keycloak user)
  - Replication account (replicator user)
  - Backup account (separate)

- [ ] Enable audit trail for privileged operations
  ```sql
  CREATE EXTENSION IF NOT EXISTS pgaudit;
  ```

- [ ] Implement 2FA for server access
  - SSH key-based authentication
  - Disable password authentication
  - Use bastion host

- [ ] Regular access reviews
  - Review user accounts monthly
  - Remove unused accounts
  - Verify permissions

### Docker Socket Security

- [ ] Never expose Docker socket to containers
  ```yaml
  # DON'T DO THIS
  volumes:
    - /var/run/docker.sock:/var/run/docker.sock
  ```

- [ ] Use Docker socket proxy if needed
  ```yaml
  services:
    dockerproxy:
      image: tecnativa/docker-socket-proxy
      environment:
        - CONTAINERS=1
  ```

### Compliance

- [ ] Document security controls

- [ ] Maintain compliance certifications
  - SOC 2
  - ISO 27001
  - GDPR
  - HIPAA (if applicable)

- [ ] Regular security assessments
  - Vulnerability scans
  - Penetration testing
  - Code reviews

- [ ] Incident response plan
  - Document procedures
  - Regular drills
  - Clear escalation path

## Security Maintenance

### Daily

- [ ] Review security logs
- [ ] Check for failed login attempts
- [ ] Monitor resource usage for anomalies

### Weekly

- [ ] Review access logs
- [ ] Check for software updates
- [ ] Review firewall logs

### Monthly

- [ ] Update Docker images
- [ ] Update OS packages
- [ ] Review user accounts
- [ ] Test backup restoration
- [ ] Review security policies

### Quarterly

- [ ] Rotate passwords
- [ ] Security audit
- [ ] Review and update firewall rules
- [ ] Penetration testing
- [ ] Update documentation

### Annually

- [ ] Comprehensive security assessment
- [ ] Update SSL certificates
- [ ] Review and update security policies
- [ ] Compliance audit
- [ ] Disaster recovery drill

## Security Incident Response

### When a Security Incident is Detected

1. **Contain**
   - Isolate affected systems
   - Block suspicious IPs
   - Revoke compromised credentials

2. **Assess**
   - Determine scope of breach
   - Identify affected data
   - Document timeline

3. **Eradicate**
   - Remove malware/backdoors
   - Patch vulnerabilities
   - Reset compromised credentials

4. **Recover**
   - Restore from clean backups
   - Verify system integrity
   - Resume normal operations

5. **Document**
   - Write incident report
   - Identify root cause
   - Implement preventive measures

6. **Notify**
   - Internal stakeholders
   - Affected users (if required)
   - Regulatory bodies (if required)

## Security Hardening Script

```bash
#!/bin/bash
# security-hardening.sh

set -e

echo "Running security hardening..."

# Generate secure passwords
echo "Generating secure passwords..."
POSTGRES_PASSWORD=$(openssl rand -base64 32)
REPLICATION_PASSWORD=$(openssl rand -base64 32)
KEYCLOAK_DB_PASSWORD=$(openssl rand -base64 32)
KEYCLOAK_ADMIN_PASSWORD=$(openssl rand -base64 32)

# Save to secure location (not in repo)
# Note: The directory path may require sudo for creation, or use a user-accessible path
# such as $HOME/.keycloak-ha/ instead of /secure/keycloak-ha
if [ -w /secure ] || sudo -n true 2>/dev/null; then
    sudo mkdir -p /secure/keycloak-ha
    sudo bash -c "cat > /secure/keycloak-ha/.env << EOF
POSTGRES_PASSWORD=$POSTGRES_PASSWORD
REPLICATION_PASSWORD=$REPLICATION_PASSWORD
KEYCLOAK_DB_PASSWORD=$KEYCLOAK_DB_PASSWORD
KEYCLOAK_ADMIN_PASSWORD=$KEYCLOAK_ADMIN_PASSWORD
EOF"
    sudo chmod 600 /secure/keycloak-ha/.env
    echo "Passwords generated and saved to /secure/keycloak-ha/.env"
else
    # Fallback to user home directory
    mkdir -p "$HOME/.keycloak-ha"
    cat > "$HOME/.keycloak-ha/.env" << EOF
POSTGRES_PASSWORD=$POSTGRES_PASSWORD
REPLICATION_PASSWORD=$REPLICATION_PASSWORD
KEYCLOAK_DB_PASSWORD=$KEYCLOAK_DB_PASSWORD
KEYCLOAK_ADMIN_PASSWORD=$KEYCLOAK_ADMIN_PASSWORD
EOF
    chmod 600 "$HOME/.keycloak-ha/.env"
    echo "Passwords generated and saved to $HOME/.keycloak-ha/.env"
fi

# Configure firewall
echo "Configuring firewall..."
sudo ufw --force enable
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow ssh
# Add your specific rules here

# Disable root login
echo "Disabling root SSH login..."
sudo sed -i 's/^PermitRootLogin yes/PermitRootLogin no/' /etc/ssh/sshd_config
sudo systemctl restart sshd

# Install fail2ban
echo "Installing fail2ban..."
sudo apt-get update
sudo apt-get install -y fail2ban
sudo systemctl enable fail2ban
sudo systemctl start fail2ban

echo "Security hardening complete!"
echo "IMPORTANT: Save the passwords from /secure/keycloak-ha/.env to your password manager!"
```

## References

- [OWASP Top 10](https://owasp.org/www-project-top-ten/)
- [CIS Docker Benchmark](https://www.cisecurity.org/benchmark/docker)
- [PostgreSQL Security](https://www.postgresql.org/docs/current/security.html)
- [Keycloak Security](https://www.keycloak.org/docs/latest/server_admin/#threat-model-mitigation)
- [NIST Cybersecurity Framework](https://www.nist.gov/cyberframework)
