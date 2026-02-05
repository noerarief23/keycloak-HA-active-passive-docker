#!/bin/bash
#
# HAProxy Failover Test Script
# Tests automatic failover from primary to replica servers
#

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
HAPROXY_STATS_URL="${HAPROXY_STATS_URL:-http://localhost:8404/stats;csv}"
HAPROXY_STATS_USER="${HAPROXY_STATS_USER:-admin}"
HAPROXY_STATS_PASSWORD="${HAPROXY_STATS_PASSWORD:-changeme}"
KEYCLOAK_URL="${KEYCLOAK_URL:-http://localhost}"
POSTGRES_HOST="${POSTGRES_HOST:-localhost}"
POSTGRES_PORT="${POSTGRES_PORT:-5432}"

# Test type
TEST_TYPE="${1:-keycloak}"  # keycloak or postgres

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}HAProxy Failover Test${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# Function to get backend status from HAProxy stats
get_backend_status() {
    local backend=$1
    local server=$2
    
    curl -s -u "$HAPROXY_STATS_USER:$HAPROXY_STATS_PASSWORD" "$HAPROXY_STATS_URL" | \
        grep "^$backend,$server," | \
        cut -d',' -f18
}

# Function to check Keycloak availability
check_keycloak() {
    if curl -s -f -o /dev/null "$KEYCLOAK_URL/health/ready"; then
        return 0
    else
        return 1
    fi
}

# Function to check PostgreSQL availability
check_postgres() {
    if timeout 5 bash -c "cat < /dev/null > /dev/tcp/$POSTGRES_HOST/$POSTGRES_PORT" 2>/dev/null; then
        return 0
    else
        return 1
    fi
}

# Function to display backend status
show_backend_status() {
    local backend=$1
    echo -e "${YELLOW}Current Backend Status:${NC}"
    curl -s -u "$HAPROXY_STATS_USER:$HAPROXY_STATS_PASSWORD" "$HAPROXY_STATS_URL" | \
        grep "^$backend," | \
        awk -F',' '{printf "  %-25s %-10s %-10s\n", $2, $18, $19}'
    echo ""
}

# Test Keycloak Failover
test_keycloak_failover() {
    echo -e "${GREEN}Testing Keycloak Failover${NC}"
    echo "================================"
    echo ""
    
    # Check initial status
    echo -e "${YELLOW}Step 1: Checking initial status...${NC}"
    show_backend_status "keycloak_backend"
    
    if check_keycloak; then
        echo -e "${GREEN}✓ Keycloak is accessible${NC}"
    else
        echo -e "${RED}✗ Keycloak is not accessible${NC}"
        exit 1
    fi
    
    # Stop primary Keycloak
    echo ""
    echo -e "${YELLOW}Step 2: Stopping primary Keycloak...${NC}"
    if docker ps | grep -q "keycloak-primary"; then
        docker stop keycloak-primary
        echo -e "${GREEN}✓ Primary Keycloak stopped${NC}"
    else
        echo -e "${YELLOW}⚠ Primary Keycloak is not running${NC}"
    fi
    
    # Wait for failover detection
    echo ""
    echo -e "${YELLOW}Step 3: Waiting for failover detection (15 seconds)...${NC}"
    for i in {15..1}; do
        echo -ne "  Waiting: $i seconds\r"
        sleep 1
    done
    echo ""
    
    # Check backend status after failover
    echo -e "${YELLOW}Step 4: Checking backend status after failover...${NC}"
    show_backend_status "keycloak_backend"
    
    # Verify service availability
    echo -e "${YELLOW}Step 5: Verifying service availability...${NC}"
    if check_keycloak; then
        echo -e "${GREEN}✓ Keycloak is still accessible (failover successful!)${NC}"
    else
        echo -e "${RED}✗ Keycloak is not accessible (failover failed!)${NC}"
        echo ""
        echo -e "${YELLOW}Starting primary Keycloak back...${NC}"
        docker start keycloak-primary
        exit 1
    fi
    
    # Measure failover time
    echo ""
    echo -e "${YELLOW}Step 6: Measuring failover time...${NC}"
    START_TIME=$(date +%s)
    
    # Start primary back
    echo ""
    echo -e "${YELLOW}Step 7: Starting primary Keycloak back...${NC}"
    docker start keycloak-primary
    echo -e "${GREEN}✓ Primary Keycloak started${NC}"
    
    # Wait for primary to be healthy
    echo ""
    echo -e "${YELLOW}Step 8: Waiting for primary to be healthy...${NC}"
    for i in {1..30}; do
        if [ "$(get_backend_status 'keycloak_backend' 'keycloak-primary')" = "UP" ]; then
            END_TIME=$(date +%s)
            RECOVERY_TIME=$((END_TIME - START_TIME))
            echo -e "${GREEN}✓ Primary is back UP (recovery time: ${RECOVERY_TIME}s)${NC}"
            break
        fi
        echo -ne "  Checking: attempt $i/30\r"
        sleep 2
    done
    echo ""
    
    # Final status
    echo -e "${YELLOW}Final Backend Status:${NC}"
    show_backend_status "keycloak_backend"
    
    echo ""
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}Keycloak Failover Test Complete!${NC}"
    echo -e "${GREEN}========================================${NC}"
}

# Test PostgreSQL Failover
test_postgres_failover() {
    echo -e "${GREEN}Testing PostgreSQL Failover${NC}"
    echo "================================"
    echo ""
    
    # Check initial status
    echo -e "${YELLOW}Step 1: Checking initial status...${NC}"
    show_backend_status "postgres_backend"
    
    if check_postgres; then
        echo -e "${GREEN}✓ PostgreSQL is accessible${NC}"
    else
        echo -e "${RED}✗ PostgreSQL is not accessible${NC}"
        exit 1
    fi
    
    # Stop primary PostgreSQL
    echo ""
    echo -e "${YELLOW}Step 2: Stopping primary PostgreSQL...${NC}"
    if docker ps | grep -q "postgres-primary"; then
        docker stop postgres-primary
        echo -e "${GREEN}✓ Primary PostgreSQL stopped${NC}"
    else
        echo -e "${YELLOW}⚠ Primary PostgreSQL is not running${NC}"
    fi
    
    # Wait for failover detection
    echo ""
    echo -e "${YELLOW}Step 3: Waiting for failover detection (9 seconds)...${NC}"
    for i in {9..1}; do
        echo -ne "  Waiting: $i seconds\r"
        sleep 1
    done
    echo ""
    
    # Check backend status after failover
    echo -e "${YELLOW}Step 4: Checking backend status after failover...${NC}"
    show_backend_status "postgres_backend"
    
    # Note about replica promotion
    echo ""
    echo -e "${YELLOW}Note: For PostgreSQL failover to work, you need to:${NC}"
    echo "  1. Promote the replica to primary"
    echo "  2. Start Keycloak on the replica server"
    echo "  3. Update application connection strings if needed"
    echo ""
    echo -e "${YELLOW}To promote replica, run:${NC}"
    echo "  ./scripts/promote-replica.sh"
    echo ""
    
    # Start primary back
    echo -e "${YELLOW}Step 5: Starting primary PostgreSQL back...${NC}"
    docker start postgres-primary
    echo -e "${GREEN}✓ Primary PostgreSQL started${NC}"
    
    # Wait for primary to be healthy
    echo ""
    echo -e "${YELLOW}Step 6: Waiting for primary to be healthy...${NC}"
    for i in {1..20}; do
        if [ "$(get_backend_status 'postgres_backend' 'postgres-primary')" = "UP" ]; then
            echo -e "${GREEN}✓ Primary is back UP${NC}"
            break
        fi
        echo -ne "  Checking: attempt $i/20\r"
        sleep 2
    done
    echo ""
    
    # Final status
    echo -e "${YELLOW}Final Backend Status:${NC}"
    show_backend_status "postgres_backend"
    
    echo ""
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}PostgreSQL Failover Test Complete!${NC}"
    echo -e "${GREEN}========================================${NC}"
}

# Main execution
case "$TEST_TYPE" in
    keycloak)
        test_keycloak_failover
        ;;
    postgres)
        test_postgres_failover
        ;;
    all)
        test_keycloak_failover
        echo ""
        echo ""
        test_postgres_failover
        ;;
    *)
        echo "Usage: $0 {keycloak|postgres|all}"
        echo ""
        echo "Examples:"
        echo "  $0 keycloak    # Test Keycloak failover"
        echo "  $0 postgres    # Test PostgreSQL failover"
        echo "  $0 all         # Test both"
        exit 1
        ;;
esac
