# SSL/TLS Certificate Management for HAProxy

This directory contains SSL/TLS certificates used by HAProxy for HTTPS termination.

## Quick Start

### For Testing (Self-Signed Certificate)

Generate a self-signed certificate using the provided script:

```bash
cd haproxy/scripts
./generate-cert.sh keycloak.local
```

This will create:
- `keycloak.key` - Private key
- `keycloak.crt` - Certificate
- `keycloak.pem` - Combined certificate + key (used by HAProxy)
- `dhparam.pem` - Diffie-Hellman parameters

### For Production (Let's Encrypt)

See the "Let's Encrypt Installation" section below.

### Using Your Own Certificate (.crt and .key files)

If you already have a certificate and private key from a Certificate Authority:

```bash
cd haproxy/scripts
./combine-cert.sh /path/to/your/certificate.crt /path/to/your/private.key
```

See the "Using Existing Certificates" section below for detailed instructions.

---

## Using Existing Certificates

If you already have a certificate (`.crt`) and private key (`.key`) from a Certificate Authority (CA) or your organization, you can use them with HAProxy.

### Option 1: Using the Combine Script (Recommended)

The easiest way is to use the provided script:

```bash
# Navigate to scripts directory
cd haproxy/scripts

# Combine your certificate and key
./combine-cert.sh /path/to/your/certificate.crt /path/to/your/private.key

# Or specify a custom output name
./combine-cert.sh /path/to/your/certificate.crt /path/to/your/private.key mycert
```

**What the script does:**
1. ✓ Verifies the certificate is valid
2. ✓ Verifies the private key is valid
3. ✓ Checks that certificate and key match
4. ✓ Combines them into HAProxy PEM format
5. ✓ Generates DH parameters (if needed)
6. ✓ Sets correct file permissions

**Example output:**
```
Certificate is valid
  Subject: CN=keycloak.yourdomain.com
  Not Before: Jan 1 00:00:00 2024 GMT
  Not After : Dec 31 23:59:59 2024 GMT
Private key is valid
Certificate and key match
Combined PEM created: ../certs/keycloak.pem
```

### Option 2: Manual Setup

If you prefer to do it manually:

```bash
# 1. Copy your files to the certs directory
cp /path/to/your/certificate.crt haproxy/certs/keycloak.crt
cp /path/to/your/private.key haproxy/certs/keycloak.key

# 2. Combine certificate and key into PEM format
cat haproxy/certs/keycloak.crt haproxy/certs/keycloak.key > haproxy/certs/keycloak.pem

# 3. Generate DH parameters (if not already present)
openssl dhparam -out haproxy/certs/dhparam.pem 2048

# 4. Set correct permissions
chmod 600 haproxy/certs/keycloak.key
chmod 600 haproxy/certs/keycloak.pem
chmod 644 haproxy/certs/keycloak.crt
chmod 644 haproxy/certs/dhparam.pem
```

### Certificate with Intermediate CA Chain

If your certificate includes intermediate CA certificates, you need to include them in the correct order:

```bash
# Order: Your certificate → Intermediate CA(s) → Root CA (optional)
cat your-certificate.crt \
    intermediate-ca.crt \
    private.key > haproxy/certs/keycloak.pem
```

Or using the script with a full chain certificate:

```bash
# If your .crt already contains the full chain
./combine-cert.sh fullchain.crt private.key
```

### Verify Your Certificate Setup

After combining your certificate, verify it's correct:

```bash
# Check the certificate details
openssl x509 -in haproxy/certs/keycloak.crt -noout -text

# Verify certificate and key match
CERT_MD5=$(openssl x509 -noout -modulus -in haproxy/certs/keycloak.crt | openssl md5)
KEY_MD5=$(openssl rsa -noout -modulus -in haproxy/certs/keycloak.key | openssl md5)
echo "Certificate: $CERT_MD5"
echo "Key:         $KEY_MD5"
# These should match!

# Check certificate expiration
openssl x509 -in haproxy/certs/keycloak.crt -noout -enddate

# Verify the PEM file contains both certificate and key
openssl x509 -in haproxy/certs/keycloak.pem -noout -subject
openssl rsa -in haproxy/certs/keycloak.pem -check -noout
```

### Common Certificate Formats

Your certificate might come in different formats. Here's how to handle them:

#### PFX/PKCS12 Format (.pfx, .p12)

```bash
# Extract certificate and key from PFX
openssl pkcs12 -in certificate.pfx -out keycloak.pem -nodes

# Copy to certs directory
cp keycloak.pem haproxy/certs/

# Set permissions
chmod 600 haproxy/certs/keycloak.pem
```

#### DER Format (.cer, .der)

```bash
# Convert DER to PEM
openssl x509 -inform der -in certificate.cer -out certificate.crt

# Then use the combine script
./haproxy/scripts/combine-cert.sh certificate.crt private.key
```

### Update HAProxy Configuration

After setting up your certificate, ensure HAProxy configuration references it correctly.

The `haproxy.cfg` should have:

```
frontend https_frontend
    bind *:443 ssl crt /etc/haproxy/certs/keycloak.pem alpn h2,http/1.1
    ...
```

If you used a different name (e.g., `mycert.pem`), update the configuration:

```
bind *:443 ssl crt /etc/haproxy/certs/mycert.pem alpn h2,http/1.1
```

### Start or Reload HAProxy

After setting up the certificate:

```bash
# Start HAProxy
docker compose -f docker-compose-lb.yml up -d

# Or reload without downtime (if already running)
docker exec haproxy-lb kill -HUP 1

# Check HAProxy logs
docker logs haproxy-lb
```

### Test Your SSL Setup

```bash
# Test SSL connection
openssl s_client -connect localhost:443 -servername your-domain.com

# Test with curl
curl -vI https://your-domain.com

# Check certificate details from browser
# Open https://your-domain.com and click the padlock icon
```

---

## Self-Signed Certificate Generation

### Using the Script (Recommended)

```bash
# Generate certificate for your domain
./haproxy/scripts/generate-cert.sh your-domain.com

# Or use default (keycloak.local)
./haproxy/scripts/generate-cert.sh
```

### Manual Generation

If you prefer to generate manually:

```bash
# 1. Generate private key
openssl genrsa -out haproxy/certs/keycloak.key 2048

# 2. Generate certificate
openssl req -new -x509 -days 365 \
  -key haproxy/certs/keycloak.key \
  -out haproxy/certs/keycloak.crt \
  -subj "/C=ID/ST=Jakarta/L=Jakarta/O=Keycloak HA/CN=keycloak.local"

# 3. Combine into PEM format
cat haproxy/certs/keycloak.crt haproxy/certs/keycloak.key > haproxy/certs/keycloak.pem

# 4. Generate DH parameters
openssl dhparam -out haproxy/certs/dhparam.pem 2048

# 5. Set permissions
chmod 600 haproxy/certs/keycloak.key
chmod 600 haproxy/certs/keycloak.pem
chmod 644 haproxy/certs/keycloak.crt
chmod 644 haproxy/certs/dhparam.pem
```

### Verify Certificate

```bash
# View certificate details
openssl x509 -in haproxy/certs/keycloak.crt -noout -text

# Check certificate dates
openssl x509 -in haproxy/certs/keycloak.crt -noout -dates

# Verify certificate and key match
openssl x509 -noout -modulus -in haproxy/certs/keycloak.crt | openssl md5
openssl rsa -noout -modulus -in haproxy/certs/keycloak.key | openssl md5
# The MD5 hashes should match
```

---

## Let's Encrypt Installation

Let's Encrypt provides free, automated SSL certificates that are trusted by all major browsers.

### Prerequisites

1. A public domain name pointing to your HAProxy server
2. Port 80 accessible from the internet (for HTTP-01 challenge)
3. Certbot installed on your server

### Install Certbot

**Ubuntu/Debian:**
```bash
sudo apt-get update
sudo apt-get install certbot
```

**CentOS/RHEL:**
```bash
sudo yum install certbot
```

**Using Docker:**
```bash
docker pull certbot/certbot
```

### Obtain Certificate

#### Method 1: Standalone (HAProxy must be stopped)

```bash
# Stop HAProxy temporarily
docker compose -f docker-compose-lb.yml down

# Obtain certificate
sudo certbot certonly --standalone \
  -d keycloak.yourdomain.com \
  --email admin@yourdomain.com \
  --agree-tos \
  --non-interactive

# Certificates will be in: /etc/letsencrypt/live/keycloak.yourdomain.com/
```

#### Method 2: Webroot (HAProxy can stay running)

```bash
# Create webroot directory
mkdir -p /var/www/certbot

# Configure HAProxy to serve .well-known/acme-challenge
# (Add to haproxy.cfg in http_frontend)
# acl letsencrypt-acl path_beg /.well-known/acme-challenge/
# use_backend letsencrypt-backend if letsencrypt-acl

# Obtain certificate
sudo certbot certonly --webroot \
  -w /var/www/certbot \
  -d keycloak.yourdomain.com \
  --email admin@yourdomain.com \
  --agree-tos \
  --non-interactive
```

#### Method 3: DNS Challenge (No port 80 needed)

```bash
# For Cloudflare DNS
sudo certbot certonly --dns-cloudflare \
  --dns-cloudflare-credentials ~/.secrets/cloudflare.ini \
  -d keycloak.yourdomain.com \
  --email admin@yourdomain.com \
  --agree-tos \
  --non-interactive
```

### Convert Let's Encrypt Certificate for HAProxy

Let's Encrypt certificates need to be combined into a single PEM file:

```bash
# Combine fullchain and private key
sudo cat /etc/letsencrypt/live/keycloak.yourdomain.com/fullchain.pem \
         /etc/letsencrypt/live/keycloak.yourdomain.com/privkey.pem \
         > haproxy/certs/keycloak.pem

# Set permissions
sudo chmod 600 haproxy/certs/keycloak.pem

# Copy DH parameters (if not already generated)
sudo cp /etc/letsencrypt/ssl-dhparams.pem haproxy/certs/dhparam.pem
# Or generate new ones:
# openssl dhparam -out haproxy/certs/dhparam.pem 2048
```

### Reload HAProxy

After installing the certificate:

```bash
# Reload HAProxy without downtime
docker exec haproxy-lb kill -HUP 1

# Or restart the container
docker compose -f docker-compose-lb.yml restart haproxy
```

---

## Certificate Renewal

### Let's Encrypt Auto-Renewal

Let's Encrypt certificates expire after 90 days. Set up automatic renewal:

#### Create Renewal Script

```bash
sudo nano /usr/local/bin/renew-haproxy-cert.sh
```

```bash
#!/bin/bash
# Renew Let's Encrypt certificate and reload HAProxy

# Renew certificate
certbot renew --quiet

# Combine certificates
cat /etc/letsencrypt/live/keycloak.yourdomain.com/fullchain.pem \
    /etc/letsencrypt/live/keycloak.yourdomain.com/privkey.pem \
    > /path/to/haproxy/certs/keycloak.pem

# Set permissions
chmod 600 /path/to/haproxy/certs/keycloak.pem

# Reload HAProxy
docker exec haproxy-lb kill -HUP 1

echo "Certificate renewed and HAProxy reloaded at $(date)"
```

```bash
# Make executable
sudo chmod +x /usr/local/bin/renew-haproxy-cert.sh
```

#### Setup Cron Job

```bash
# Edit crontab
sudo crontab -e

# Add this line to run renewal check daily at 2 AM
0 2 * * * /usr/local/bin/renew-haproxy-cert.sh >> /var/log/cert-renewal.log 2>&1
```

#### Test Renewal

```bash
# Dry run (doesn't actually renew)
sudo certbot renew --dry-run

# Force renewal (for testing)
sudo certbot renew --force-renewal
```

### Self-Signed Certificate Renewal

Self-signed certificates don't auto-renew. Before expiration:

```bash
# Check expiration date
openssl x509 -in haproxy/certs/keycloak.crt -noout -enddate

# Regenerate certificate
./haproxy/scripts/generate-cert.sh your-domain.com

# Reload HAProxy
docker exec haproxy-lb kill -HUP 1
```

---

## Certificate Formats

### PEM Format (Used by HAProxy)

HAProxy requires certificates in PEM format with the following structure:

```
-----BEGIN CERTIFICATE-----
[Certificate content]
-----END CERTIFICATE-----
-----BEGIN CERTIFICATE-----
[Intermediate certificate content - if any]
-----END CERTIFICATE-----
-----BEGIN PRIVATE KEY-----
[Private key content]
-----END PRIVATE KEY-----
```

### Converting Other Formats

#### From PKCS12 (.pfx, .p12)

```bash
# Extract certificate and key
openssl pkcs12 -in certificate.pfx -out keycloak.pem -nodes

# Set permissions
chmod 600 haproxy/certs/keycloak.pem
```

#### From Separate Files

```bash
# If you have separate cert, intermediate, and key files
cat certificate.crt intermediate.crt private.key > haproxy/certs/keycloak.pem
```

---

## Troubleshooting

### Certificate Not Loading

**Symptom:** HAProxy fails to start with SSL error

**Solutions:**

1. Check certificate format:
   ```bash
   openssl x509 -in haproxy/certs/keycloak.pem -noout -text
   ```

2. Verify file permissions:
   ```bash
   ls -la haproxy/certs/
   # keycloak.pem should be readable by HAProxy container
   ```

3. Check HAProxy logs:
   ```bash
   docker logs haproxy-lb
   ```

### Certificate Expired

**Symptom:** Browsers show "Certificate expired" error

**Solutions:**

1. Check expiration:
   ```bash
   openssl x509 -in haproxy/certs/keycloak.crt -noout -dates
   ```

2. Renew certificate (see renewal section above)

### Certificate Mismatch

**Symptom:** Browsers show "Certificate name mismatch" error

**Solutions:**

1. Verify certificate CN matches your domain:
   ```bash
   openssl x509 -in haproxy/certs/keycloak.crt -noout -subject
   ```

2. Generate new certificate with correct domain name

### Private Key Permissions

**Symptom:** HAProxy can't read private key

**Solutions:**

```bash
# Set correct permissions
chmod 600 haproxy/certs/keycloak.key
chmod 600 haproxy/certs/keycloak.pem

# Verify
ls -la haproxy/certs/
```

---

## Security Best Practices

1. **Never commit private keys to version control**
   - The `.gitignore` file excludes `*.key` and `*.pem` files
   - Always keep private keys secure

2. **Use strong key sizes**
   - Minimum 2048-bit RSA keys
   - 4096-bit for higher security

3. **Rotate certificates regularly**
   - Let's Encrypt: Auto-renews every 60 days
   - Self-signed: Renew annually or more frequently

4. **Restrict file permissions**
   - Private keys: 600 (owner read/write only)
   - Certificates: 644 (world-readable)

5. **Use Let's Encrypt in production**
   - Free and trusted by all browsers
   - Automated renewal
   - Better security than self-signed

6. **Monitor certificate expiration**
   - Set up alerts 30 days before expiration
   - Test renewal process regularly

7. **Keep DH parameters updated**
   - Regenerate dhparam.pem annually
   - Use at least 2048-bit parameters

---

## Additional Resources

- [Let's Encrypt Documentation](https://letsencrypt.org/docs/)
- [HAProxy SSL/TLS Configuration](https://www.haproxy.com/documentation/hapee/latest/security/tls/)
- [OpenSSL Documentation](https://www.openssl.org/docs/)
- [Mozilla SSL Configuration Generator](https://ssl-config.mozilla.org/)

---

## Quick Reference

### Check Certificate Expiration
```bash
openssl x509 -in haproxy/certs/keycloak.crt -noout -enddate
```

### Test SSL Configuration
```bash
# Using OpenSSL
openssl s_client -connect localhost:443 -servername keycloak.local

# Using curl
curl -vI https://keycloak.local
```

### Reload HAProxy After Certificate Update
```bash
docker exec haproxy-lb kill -HUP 1
```

### View Certificate Chain
```bash
openssl s_client -connect localhost:443 -showcerts
```
