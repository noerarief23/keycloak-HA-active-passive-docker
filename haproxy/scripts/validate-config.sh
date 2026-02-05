#!/bin/bash
#
# HAProxy Configuration Validation Script
# Validates HAProxy configuration, SSL certificates, and backend connectivity
#

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
HAPROXY_CFG="${HAPROXY_CFG:-./haproxy/haproxy.cfg}"
CERTS_DIR="${CERTS_DIR:-./haproxy/certs}"
ERRORS_DIR="${ERRORS_DIR:-./haproxy/errors}"

# Load environment variables if .env exists
if [ -f .env ]; then
    source .env
fi

PRIMARY_SERVER_IP="${PRIMARY_SERVER_IP:-192.168.1.10}"
REPLICA_SERVER_IP="${REPLICA_SERVER_IP:-192.168.1.11}"

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}HAProxy Configuration Validation${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

ERRORS=0
WARNINGS=0

# Function to print status
print_status() {
    local status=$1
    local message=$2
    
    if [ "$status" = "OK" ]; then
        echo -e "${GREEN}✓${NC} $message"
    elif [ "$status" = "WARN" ]; then
        echo -e "${YELLOW}⚠${NC} $message"
        ((WARNINGS++))
    else
        echo -e "${RED}✗${NC} $message"
        ((ERRORS++))
    fi
}

# 1. Validate HAProxy configuration syntax
echo -e "${YELLOW}1. Validating HAProxy Configuration Syntax${NC}"
echo "----------------------------------------"

if [ ! -f "$HAPROXY_CFG" ]; then
    print_status "ERROR" "Configuration file not found: $HAPROXY_CFG"
else
    if docker run --rm -v "$(pwd)/haproxy:/usr/local/etc/haproxy:ro" \
        haproxy:2.9-alpine haproxy -c -f /usr/local/etc/haproxy/haproxy.cfg > /dev/null 2>&1; then
        print_status "OK" "HAProxy configuration syntax is valid"
    else
        print_status "ERROR" "HAProxy configuration has syntax errors"
        echo ""
        echo "Run this command to see details:"
        echo "docker run --rm -v \$(pwd)/haproxy:/usr/local/etc/haproxy:ro haproxy:2.9-alpine haproxy -c -f /usr/local/etc/haproxy/haproxy.cfg"
    fi
fi

echo ""

# 2. Check SSL certificate validity
echo -e "${YELLOW}2. Checking SSL Certificates${NC}"
echo "----------------------------------------"

if [ ! -d "$CERTS_DIR" ]; then
    print_status "ERROR" "Certificates directory not found: $CERTS_DIR"
else
    # Check for keycloak.pem
    if [ -f "$CERTS_DIR/keycloak.pem" ]; then
        # Check if certificate is valid
        if openssl x509 -in "$CERTS_DIR/keycloak.pem" -noout -checkend 0 > /dev/null 2>&1; then
            print_status "OK" "SSL certificate is valid"
            
            # Check expiration date
            EXPIRY=$(openssl x509 -in "$CERTS_DIR/keycloak.pem" -noout -enddate | cut -d= -f2)
            EXPIRY_EPOCH=$(date -d "$EXPIRY" +%s 2>/dev/null || date -j -f "%b %d %T %Y %Z" "$EXPIRY" +%s 2>/dev/null)
            NOW_EPOCH=$(date +%s)
            DAYS_LEFT=$(( ($EXPIRY_EPOCH - $NOW_EPOCH) / 86400 ))
            
            if [ $DAYS_LEFT -lt 30 ]; then
                print_status "WARN" "Certificate expires in $DAYS_LEFT days: $EXPIRY"
            else
                print_status "OK" "Certificate expires in $DAYS_LEFT days: $EXPIRY"
            fi
        else
            print_status "ERROR" "SSL certificate has expired"
        fi
        
        # Check certificate permissions
        PERMS=$(stat -c %a "$CERTS_DIR/keycloak.pem" 2>/dev/null || stat -f %A "$CERTS_DIR/keycloak.pem" 2>/dev/null)
        if [ "$PERMS" = "600" ] || [ "$PERMS" = "400" ]; then
            print_status "OK" "Certificate permissions are secure ($PERMS)"
        else
            print_status "WARN" "Certificate permissions should be 600 or 400 (current: $PERMS)"
        fi
    else
        print_status "ERROR" "SSL certificate not found: $CERTS_DIR/keycloak.pem"
        echo ""
        echo "Generate a certificate with:"
        echo "cd haproxy/scripts && ./generate-cert.sh keycloak.local"
    fi
fi

echo ""

# 3. Check error pages
echo -e "${YELLOW}3. Checking Error Pages${NC}"
echo "----------------------------------------"

if [ ! -d "$ERRORS_DIR" ]; then
    print_status "WARN" "Error pages directory not found: $ERRORS_DIR"
else
    ERROR_CODES=(400 403 408 500 502 503 504)
    MISSING_PAGES=0
    
    for code in "${ERROR_CODES[@]}"; do
        if [ -f "$ERRORS_DIR/${code}.http" ]; then
            print_status "OK" "Error page exists: ${code}.http"
        else
            print_status "WARN" "Error page missing: ${code}.http"
            ((MISSING_PAGES++))
        fi
    done
    
    if [ $MISSING_PAGES -gt 0 ]; then
        echo ""
        echo "Note: Error pages are optional but recommended for better user experience"
    fi
fi

echo ""

# 4. Verify backend connectivity
echo -e "${YELLOW}4. Verifying Backend Connectivity${NC}"
echo "----------------------------------------"

# Check primary Keycloak
if timeout 3 bash -c "cat < /dev/null > /dev/tcp/$PRIMARY_SERVER_IP/8080" 2>/dev/null; then
    print_status "OK" "Primary Keycloak is reachable ($PRIMARY_SERVER_IP:8080)"
else
    print_status "WARN" "Primary Keycloak is not reachable ($PRIMARY_SERVER_IP:8080)"
fi

# Check replica Keycloak
if timeout 3 bash -c "cat < /dev/null > /dev/tcp/$REPLICA_SERVER_IP/8081" 2>/dev/null; then
    print_status "OK" "Replica Keycloak is reachable ($REPLICA_SERVER_IP:8081)"
else
    print_status "WARN" "Replica Keycloak is not reachable ($REPLICA_SERVER_IP:8081)"
fi

# Check primary PostgreSQL
if timeout 3 bash -c "cat < /dev/null > /dev/tcp/$PRIMARY_SERVER_IP/5432" 2>/dev/null; then
    print_status "OK" "Primary PostgreSQL is reachable ($PRIMARY_SERVER_IP:5432)"
else
    print_status "WARN" "Primary PostgreSQL is not reachable ($PRIMARY_SERVER_IP:5432)"
fi

# Check replica PostgreSQL
if timeout 3 bash -c "cat < /dev/null > /dev/tcp/$REPLICA_SERVER_IP/5433" 2>/dev/null; then
    print_status "OK" "Replica PostgreSQL is reachable ($REPLICA_SERVER_IP:5433)"
else
    print_status "WARN" "Replica PostgreSQL is not reachable ($REPLICA_SERVER_IP:5433)"
fi

echo ""

# 5. Test health check endpoints
echo -e "${YELLOW}5. Testing Health Check Endpoints${NC}"
echo "----------------------------------------"

# Test Keycloak health endpoint
if command -v curl &> /dev/null; then
    if curl -s -f -m 5 "http://$PRIMARY_SERVER_IP:8080/health/ready" > /dev/null 2>&1; then
        print_status "OK" "Primary Keycloak health endpoint responding"
    else
        print_status "WARN" "Primary Keycloak health endpoint not responding"
    fi
    
    if curl -s -f -m 5 "http://$REPLICA_SERVER_IP:8081/health/ready" > /dev/null 2>&1; then
        print_status "OK" "Replica Keycloak health endpoint responding"
    else
        print_status "WARN" "Replica Keycloak health endpoint not responding"
    fi
else
    print_status "WARN" "curl not installed, skipping health endpoint tests"
fi

echo ""

# 6. Check environment variables
echo -e "${YELLOW}6. Checking Environment Variables${NC}"
echo "----------------------------------------"

if [ -f .env ]; then
    print_status "OK" ".env file exists"
    
    if grep -q "HAPROXY_STATS_USER=" .env; then
        print_status "OK" "HAPROXY_STATS_USER is set"
    else
        print_status "WARN" "HAPROXY_STATS_USER not set in .env"
    fi
    
    if grep -q "HAPROXY_STATS_PASSWORD=" .env; then
        print_status "OK" "HAPROXY_STATS_PASSWORD is set"
    else
        print_status "WARN" "HAPROXY_STATS_PASSWORD not set in .env"
    fi
    
    if grep -q "PRIMARY_SERVER_IP=" .env; then
        print_status "OK" "PRIMARY_SERVER_IP is set"
    else
        print_status "WARN" "PRIMARY_SERVER_IP not set in .env"
    fi
    
    if grep -q "REPLICA_SERVER_IP=" .env; then
        print_status "OK" "REPLICA_SERVER_IP is set"
    else
        print_status "WARN" "REPLICA_SERVER_IP not set in .env"
    fi
else
    print_status "WARN" ".env file not found (copy from .env.lb.example)"
fi

echo ""

# Summary
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Validation Summary${NC}"
echo -e "${BLUE}========================================${NC}"

if [ $ERRORS -eq 0 ] && [ $WARNINGS -eq 0 ]; then
    echo -e "${GREEN}✓ All checks passed!${NC}"
    echo ""
    echo "HAProxy is ready to deploy."
    exit 0
elif [ $ERRORS -eq 0 ]; then
    echo -e "${YELLOW}⚠ Validation completed with $WARNINGS warning(s)${NC}"
    echo ""
    echo "HAProxy can be deployed, but review warnings above."
    exit 0
else
    echo -e "${RED}✗ Validation failed with $ERRORS error(s) and $WARNINGS warning(s)${NC}"
    echo ""
    echo "Fix errors before deploying HAProxy."
    exit 1
fi
