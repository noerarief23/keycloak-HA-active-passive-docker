#!/bin/bash
#
# HAProxy Load Testing Script
# Tests performance under load using Apache Bench (ab) or wrk
#

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
HAPROXY_HOST="${HAPROXY_HOST:-localhost}"
REQUESTS="${REQUESTS:-1000}"
CONCURRENCY="${CONCURRENCY:-10}"
TEST_DURATION="${TEST_DURATION:-30}"

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}HAProxy Load Testing${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# Check which tool is available
USE_TOOL=""

if command -v wrk &> /dev/null; then
    USE_TOOL="wrk"
    echo -e "${GREEN}Using wrk for load testing${NC}"
elif command -v ab &> /dev/null; then
    USE_TOOL="ab"
    echo -e "${GREEN}Using Apache Bench (ab) for load testing${NC}"
else
    echo -e "${RED}Error: Neither wrk nor Apache Bench (ab) is installed${NC}"
    echo ""
    echo "Install one of the following:"
    echo "  Ubuntu/Debian: sudo apt-get install apache2-utils"
    echo "  CentOS/RHEL:   sudo yum install httpd-tools"
    echo "  macOS:         brew install wrk"
    exit 1
fi

echo ""

# Test 1: HTTP Load Test
echo -e "${YELLOW}Test 1: HTTP Load Test${NC}"
echo "----------------------------------------"
echo "Target: http://$HAPROXY_HOST/"
echo "Requests: $REQUESTS"
echo "Concurrency: $CONCURRENCY"
echo ""

if [ "$USE_TOOL" = "wrk" ]; then
    wrk -t$CONCURRENCY -c$CONCURRENCY -d${TEST_DURATION}s --latency "http://$HAPROXY_HOST/"
elif [ "$USE_TOOL" = "ab" ]; then
    ab -n $REQUESTS -c $CONCURRENCY "http://$HAPROXY_HOST/"
fi

echo ""
echo -e "${GREEN}✓ HTTP load test completed${NC}"
echo ""

# Test 2: HTTPS Load Test
echo -e "${YELLOW}Test 2: HTTPS Load Test${NC}"
echo "----------------------------------------"
echo "Target: https://$HAPROXY_HOST/"
echo "Requests: $REQUESTS"
echo "Concurrency: $CONCURRENCY"
echo ""

if [ "$USE_TOOL" = "wrk" ]; then
    wrk -t$CONCURRENCY -c$CONCURRENCY -d${TEST_DURATION}s --latency "https://$HAPROXY_HOST/"
elif [ "$USE_TOOL" = "ab" ]; then
    ab -n $REQUESTS -c $CONCURRENCY "https://$HAPROXY_HOST/"
fi

echo ""
echo -e "${GREEN}✓ HTTPS load test completed${NC}"
echo ""

# Test 3: PostgreSQL Connection Pool Test
echo -e "${YELLOW}Test 3: PostgreSQL Connection Pool Test${NC}"
echo "----------------------------------------"

if command -v pgbench &> /dev/null; then
    echo "Testing PostgreSQL connection pooling..."
    echo ""
    
    # Check if we can connect
    if psql -h "$HAPROXY_HOST" -p 5432 -U keycloak -d keycloak -c "SELECT 1;" &> /dev/null; then
        echo "Running pgbench..."
        pgbench -h "$HAPROXY_HOST" -p 5432 -U keycloak -d keycloak -c $CONCURRENCY -j $CONCURRENCY -t 100
        echo ""
        echo -e "${GREEN}✓ PostgreSQL load test completed${NC}"
    else
        echo -e "${YELLOW}⚠ Cannot connect to PostgreSQL through HAProxy${NC}"
        echo "Skipping PostgreSQL load test"
    fi
else
    echo -e "${YELLOW}⚠ pgbench not installed, skipping PostgreSQL load test${NC}"
    echo "Install with: sudo apt-get install postgresql-contrib"
fi

echo ""

# Test 4: Monitor HAProxy During Load
echo -e "${YELLOW}Test 4: HAProxy Stats During Load${NC}"
echo "----------------------------------------"

if [ -n "$HAPROXY_STATS_USER" ] && [ -n "$HAPROXY_STATS_PASSWORD" ]; then
    echo "Fetching HAProxy statistics..."
    
    STATS=$(curl -s -u "$HAPROXY_STATS_USER:$HAPROXY_STATS_PASSWORD" "http://$HAPROXY_HOST:8404/stats;csv")
    
    if [ -n "$STATS" ]; then
        echo ""
        echo "Backend Statistics:"
        echo "-------------------"
        
        # Parse Keycloak backend stats
        KEYCLOAK_STATS=$(echo "$STATS" | grep "keycloak_backend,BACKEND")
        if [ -n "$KEYCLOAK_STATS" ]; then
            TOTAL_SESSIONS=$(echo "$KEYCLOAK_STATS" | cut -d',' -f5)
            TOTAL_REQUESTS=$(echo "$KEYCLOAK_STATS" | cut -d',' -f8)
            echo "Keycloak Backend:"
            echo "  Total Sessions: $TOTAL_SESSIONS"
            echo "  Total Requests: $TOTAL_REQUESTS"
        fi
        
        # Parse PostgreSQL backend stats
        POSTGRES_STATS=$(echo "$STATS" | grep "postgres_backend,BACKEND")
        if [ -n "$POSTGRES_STATS" ]; then
            TOTAL_SESSIONS=$(echo "$POSTGRES_STATS" | cut -d',' -f5)
            TOTAL_REQUESTS=$(echo "$POSTGRES_STATS" | cut -d',' -f8)
            echo "PostgreSQL Backend:"
            echo "  Total Sessions: $TOTAL_SESSIONS"
            echo "  Total Requests: $TOTAL_REQUESTS"
        fi
        
        echo ""
        echo -e "${GREEN}✓ Statistics retrieved successfully${NC}"
    else
        echo -e "${YELLOW}⚠ Could not retrieve statistics${NC}"
    fi
else
    echo -e "${YELLOW}⚠ Stats credentials not set, skipping${NC}"
fi

echo ""

# Test 5: Failover Under Load (Optional)
echo -e "${YELLOW}Test 5: Failover Under Load (Optional)${NC}"
echo "----------------------------------------"
echo "This test simulates a primary server failure during load."
echo "It requires manual intervention to stop/start services."
echo ""
echo "To run this test:"
echo "  1. Start a load test in another terminal:"
echo "     wrk -t10 -c10 -d60s https://$HAPROXY_HOST/"
echo "  2. While load test is running, stop primary Keycloak:"
echo "     docker stop keycloak-primary"
echo "  3. Observe HAProxy stats page for failover"
echo "  4. Restart primary:"
echo "     docker start keycloak-primary"
echo ""
echo "Press Enter to skip this test, or Ctrl+C to exit and run manually"
read -r

echo ""

# Summary
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Load Testing Summary${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""
echo -e "${GREEN}✓ Load testing completed${NC}"
echo ""
echo "Review the results above to assess HAProxy performance."
echo ""
echo "Key metrics to monitor:"
echo "  - Requests per second"
echo "  - Average latency"
echo "  - Error rate (should be 0%)"
echo "  - Connection failures"
echo ""
echo "For continuous monitoring, check:"
echo "  - HAProxy stats page: http://$HAPROXY_HOST:8404/stats"
echo "  - Prometheus metrics: http://$HAPROXY_HOST:8404/metrics"
echo ""
