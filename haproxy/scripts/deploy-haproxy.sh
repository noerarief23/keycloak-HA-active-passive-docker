#!/bin/bash
#
# HAProxy Deployment Script
# Automated deployment of HAProxy load balancer
#

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}HAProxy Deployment Script${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# Step 1: Check Prerequisites
echo -e "${YELLOW}Step 1: Checking Prerequisites${NC}"
echo "----------------------------------------"

ERRORS=0

# Check Docker
if command -v docker &> /dev/null; then
    DOCKER_VERSION=$(docker --version | cut -d' ' -f3 | cut -d',' -f1)
    echo -e "${GREEN}✓${NC} Docker is installed (version $DOCKER_VERSION)"
else
    echo -e "${RED}✗${NC} Docker is not installed"
    ((ERRORS++))
fi

# Check Docker Compose
if docker compose version &> /dev/null; then
    COMPOSE_VERSION=$(docker compose version | cut -d' ' -f4)
    echo -e "${GREEN}✓${NC} Docker Compose is installed (version $COMPOSE_VERSION)"
else
    echo -e "${RED}✗${NC} Docker Compose is not installed"
    ((ERRORS++))
fi

# Check if running as root or in docker group
if [ "$EUID" -eq 0 ] || groups | grep -q docker; then
    echo -e "${GREEN}✓${NC} User has Docker permissions"
else
    echo -e "${RED}✗${NC} User does not have Docker permissions"
    echo "  Run: sudo usermod -aG docker \$USER && newgrp docker"
    ((ERRORS++))
fi

if [ $ERRORS -gt 0 ]; then
    echo ""
    echo -e "${RED}Prerequisites check failed. Please fix the errors above.${NC}"
    exit 1
fi

echo ""

# Step 2: Create Directory Structure
echo -e "${YELLOW}Step 2: Verifying Directory Structure${NC}"
echo "----------------------------------------"

mkdir -p haproxy/certs
mkdir -p haproxy/errors
mkdir -p haproxy/scripts

echo -e "${GREEN}✓${NC} Directory structure verified"
echo ""

# Step 3: Check Configuration Files
echo -e "${YELLOW}Step 3: Checking Configuration Files${NC}"
echo "----------------------------------------"

if [ ! -f "haproxy/haproxy.cfg" ]; then
    echo -e "${RED}✗${NC} haproxy.cfg not found"
    exit 1
fi
echo -e "${GREEN}✓${NC} haproxy.cfg exists"

if [ ! -f "docker-compose-lb.yml" ]; then
    echo -e "${RED}✗${NC} docker-compose-lb.yml not found"
    exit 1
fi
echo -e "${GREEN}✓${NC} docker-compose-lb.yml exists"

if [ ! -f ".env" ]; then
    echo -e "${YELLOW}⚠${NC} .env file not found"
    echo "  Creating from .env.lb.example..."
    
    if [ -f ".env.lb.example" ]; then
        cp .env.lb.example .env
        echo -e "${GREEN}✓${NC} .env file created"
        echo ""
        echo -e "${YELLOW}IMPORTANT: Edit .env file and update the following:${NC}"
        echo "  - HAPROXY_STATS_PASSWORD (change from default)"
        echo "  - PRIMARY_SERVER_IP (set to your primary server IP)"
        echo "  - REPLICA_SERVER_IP (set to your replica server IP)"
        echo ""
        read -p "Press Enter after updating .env file..."
    else
        echo -e "${RED}✗${NC} .env.lb.example not found"
        exit 1
    fi
else
    echo -e "${GREEN}✓${NC} .env file exists"
fi

echo ""

# Step 4: Generate or Validate SSL Certificates
echo -e "${YELLOW}Step 4: SSL Certificate Setup${NC}"
echo "----------------------------------------"

if [ -f "haproxy/certs/keycloak.pem" ]; then
    echo -e "${GREEN}✓${NC} SSL certificate exists"
    
    # Check if certificate is valid
    if openssl x509 -in haproxy/certs/keycloak.pem -noout -checkend 0 > /dev/null 2>&1; then
        EXPIRY=$(openssl x509 -in haproxy/certs/keycloak.pem -noout -enddate | cut -d= -f2)
        echo -e "${GREEN}✓${NC} Certificate is valid (expires: $EXPIRY)"
    else
        echo -e "${RED}✗${NC} Certificate has expired"
        read -p "Generate new self-signed certificate? (y/n) " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            cd haproxy/scripts
            ./generate-cert.sh keycloak.local
            cd ../..
        fi
    fi
else
    echo -e "${YELLOW}⚠${NC} SSL certificate not found"
    read -p "Generate self-signed certificate? (y/n) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        cd haproxy/scripts
        ./generate-cert.sh keycloak.local
        cd ../..
    else
        echo ""
        echo "Please provide SSL certificate before deploying."
        echo "Place certificate at: haproxy/certs/keycloak.pem"
        exit 1
    fi
fi

echo ""

# Step 5: Validate HAProxy Configuration
echo -e "${YELLOW}Step 5: Validating HAProxy Configuration${NC}"
echo "----------------------------------------"

if docker run --rm -v "$(pwd)/haproxy:/usr/local/etc/haproxy:ro" \
    haproxy:2.9-alpine haproxy -c -f /usr/local/etc/haproxy/haproxy.cfg > /dev/null 2>&1; then
    echo -e "${GREEN}✓${NC} HAProxy configuration is valid"
else
    echo -e "${RED}✗${NC} HAProxy configuration has errors"
    echo ""
    echo "Running validation with details:"
    docker run --rm -v "$(pwd)/haproxy:/usr/local/etc/haproxy:ro" \
        haproxy:2.9-alpine haproxy -c -f /usr/local/etc/haproxy/haproxy.cfg
    exit 1
fi

echo ""

# Step 6: Check Network Connectivity
echo -e "${YELLOW}Step 6: Checking Backend Connectivity${NC}"
echo "----------------------------------------"

# Load environment variables
if [ -f .env ]; then
    source .env
fi

PRIMARY_SERVER_IP="${PRIMARY_SERVER_IP:-192.168.1.10}"
REPLICA_SERVER_IP="${REPLICA_SERVER_IP:-192.168.1.11}"

echo "Testing connectivity to backend servers..."

# Test primary Keycloak
if timeout 3 bash -c "cat < /dev/null > /dev/tcp/$PRIMARY_SERVER_IP/8080" 2>/dev/null; then
    echo -e "${GREEN}✓${NC} Primary Keycloak is reachable ($PRIMARY_SERVER_IP:8080)"
else
    echo -e "${YELLOW}⚠${NC} Primary Keycloak is not reachable ($PRIMARY_SERVER_IP:8080)"
fi

# Test replica Keycloak
if timeout 3 bash -c "cat < /dev/null > /dev/tcp/$REPLICA_SERVER_IP/8081" 2>/dev/null; then
    echo -e "${GREEN}✓${NC} Replica Keycloak is reachable ($REPLICA_SERVER_IP:8081)"
else
    echo -e "${YELLOW}⚠${NC} Replica Keycloak is not reachable ($REPLICA_SERVER_IP:8081)"
fi

# Test primary PostgreSQL
if timeout 3 bash -c "cat < /dev/null > /dev/tcp/$PRIMARY_SERVER_IP/5432" 2>/dev/null; then
    echo -e "${GREEN}✓${NC} Primary PostgreSQL is reachable ($PRIMARY_SERVER_IP:5432)"
else
    echo -e "${YELLOW}⚠${NC} Primary PostgreSQL is not reachable ($PRIMARY_SERVER_IP:5432)"
fi

# Test replica PostgreSQL
if timeout 3 bash -c "cat < /dev/null > /dev/tcp/$REPLICA_SERVER_IP/5433" 2>/dev/null; then
    echo -e "${GREEN}✓${NC} Replica PostgreSQL is reachable ($REPLICA_SERVER_IP:5433)"
else
    echo -e "${YELLOW}⚠${NC} Replica PostgreSQL is not reachable ($REPLICA_SERVER_IP:5433)"
fi

echo ""

# Step 7: Pull Docker Image
echo -e "${YELLOW}Step 7: Pulling HAProxy Docker Image${NC}"
echo "----------------------------------------"

docker compose -f docker-compose-lb.yml pull

echo -e "${GREEN}✓${NC} Docker image pulled"
echo ""

# Step 8: Start HAProxy Container
echo -e "${YELLOW}Step 8: Starting HAProxy Container${NC}"
echo "----------------------------------------"

# Check if container is already running
if docker ps | grep -q haproxy-lb; then
    echo -e "${YELLOW}⚠${NC} HAProxy container is already running"
    read -p "Restart container? (y/n) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        docker compose -f docker-compose-lb.yml restart haproxy
        echo -e "${GREEN}✓${NC} HAProxy container restarted"
    fi
else
    docker compose -f docker-compose-lb.yml up -d
    echo -e "${GREEN}✓${NC} HAProxy container started"
fi

echo ""

# Step 9: Wait for HAProxy to be Ready
echo -e "${YELLOW}Step 9: Waiting for HAProxy to be Ready${NC}"
echo "----------------------------------------"

echo "Waiting for HAProxy to start..."
sleep 5

# Check container status
if docker ps | grep -q haproxy-lb; then
    echo -e "${GREEN}✓${NC} HAProxy container is running"
else
    echo -e "${RED}✗${NC} HAProxy container failed to start"
    echo ""
    echo "Container logs:"
    docker logs haproxy-lb
    exit 1
fi

echo ""

# Step 10: Verify Health Checks
echo -e "${YELLOW}Step 10: Verifying Health Checks${NC}"
echo "----------------------------------------"

echo "Waiting for health checks to stabilize..."
sleep 10

if [ -f "haproxy/scripts/check-backends.sh" ]; then
    cd haproxy/scripts
    if ./check-backends.sh; then
        echo -e "${GREEN}✓${NC} All backends are healthy"
    else
        echo -e "${YELLOW}⚠${NC} Some backends are not healthy"
        echo "  This is normal if backend services are not running yet"
    fi
    cd ../..
else
    echo -e "${YELLOW}⚠${NC} check-backends.sh not found, skipping health check verification"
fi

echo ""

# Step 11: Display Access Information
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Deployment Complete!${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# Get server IP
SERVER_IP=$(hostname -I | awk '{print $1}')

echo "HAProxy is now running and accessible at:"
echo ""
echo "  HTTP:       http://$SERVER_IP/"
echo "  HTTPS:      https://$SERVER_IP/"
echo "  PostgreSQL: $SERVER_IP:5432"
echo "  Stats Page: http://$SERVER_IP:8404/stats"
echo "  Metrics:    http://$SERVER_IP:8404/metrics"
echo "  Health:     http://$SERVER_IP:8404/health"
echo ""

if [ -f .env ]; then
    source .env
    echo "Stats Page Credentials:"
    echo "  Username: ${HAPROXY_STATS_USER:-admin}"
    echo "  Password: ${HAPROXY_STATS_PASSWORD:-[check .env file]}"
    echo ""
fi

echo "Next Steps:"
echo "  1. Update DNS to point to this server: $SERVER_IP"
echo "  2. Test connectivity: curl -k https://$SERVER_IP/"
echo "  3. Check stats page: http://$SERVER_IP:8404/stats"
echo "  4. Run integration tests: ./haproxy/scripts/integration-test.sh"
echo "  5. Test failover: ./haproxy/scripts/test-failover.sh"
echo ""

echo "Useful Commands:"
echo "  View logs:    docker logs -f haproxy-lb"
echo "  Stop:         docker compose -f docker-compose-lb.yml stop"
echo "  Restart:      docker compose -f docker-compose-lb.yml restart"
echo "  Remove:       docker compose -f docker-compose-lb.yml down"
echo ""

echo -e "${GREEN}✓ HAProxy deployment successful!${NC}"
