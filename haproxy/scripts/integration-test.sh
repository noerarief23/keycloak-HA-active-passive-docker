#!/bin/bash
#
# HAProxy Integration Test Script
# Tests HTTP, HTTPS, PostgreSQL connectivity, and health checks
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
HAPROXY_STATS_USER="${HAPROXY_STATS_USER:-admin}"
HAPROXY_STATS_PASSWORD="${HAPROXY_STATS_PASSWORD:-changeme}"

# Load environment variables if .env exists
if [ -f .env ]; then
    source .env
fi

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}HAProxy Integration Tests${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

PASSED=0
FAILED=0

# Function to print test result
test_result() {
    local status=$1
    local test_name=$2
    local details=$3
    
    if [ "$status" = "PASS" ]; then
        echo -e "${GREEN}✓ PASS${NC} - $test_name"
        if [ -n "$details" ]; then
            echo "  $details"
        fi
        ((PASSED++))
    else
        echo -e "${RED}✗ FAIL${NC} - $test_name"
        if [ -n "$details" ]; then
            echo "  $details"
        fi
        ((FAILED++))
    fi
    echo ""
}

# Check prerequisites
echo -e "${YELLOW}Checking Prerequisites${NC}"
echo "----------------------------------------"

if ! command -v curl &> /dev/null; then
    echo -e "${RED}Error: curl is not installed${NC}"
    exit 1
fi

if ! command -v docker &> /dev/null; then
    echo -e "${RED}Error: docker is not installed${NC}"
    exit 1
fi

echo -e "${GREEN}✓ Prerequisites met${NC}"
echo ""

# Test 1: HAProxy Container Running
echo -e "${YELLOW}Test 1: HAProxy Container Status${NC}"
echo "----------------------------------------"

if docker ps | grep -q haproxy-lb; then
    test_result "PASS" "HAProxy container is running"
else
    test_result "FAIL" "HAProxy container is not running" "Start with: docker compose -f docker-compose-lb.yml up -d"
fi

# Test 2: HTTP Connectivity (Port 80)
echo -e "${YELLOW}Test 2: HTTP Connectivity${NC}"
echo "----------------------------------------"

HTTP_RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" -L "http://$HAPROXY_HOST/" 2>/dev/null || echo "000")

if [ "$HTTP_RESPONSE" = "301" ] || [ "$HTTP_RESPONSE" = "302" ]; then
    test_result "PASS" "HTTP redirects to HTTPS (HTTP $HTTP_RESPONSE)"
elif [ "$HTTP_RESPONSE" = "200" ]; then
    test_result "PASS" "HTTP connection successful (HTTP $HTTP_RESPONSE)"
else
    test_result "FAIL" "HTTP connection failed (HTTP $HTTP_RESPONSE)" "Check if HAProxy is listening on port 80"
fi

# Test 3: HTTPS Connectivity (Port 443)
echo -e "${YELLOW}Test 3: HTTPS Connectivity${NC}"
echo "----------------------------------------"

HTTPS_RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" -k "https://$HAPROXY_HOST/" 2>/dev/null || echo "000")

if [ "$HTTPS_RESPONSE" = "200" ] || [ "$HTTPS_RESPONSE" = "302" ] || [ "$HTTPS_RESPONSE" = "303" ]; then
    test_result "PASS" "HTTPS connection successful (HTTP $HTTPS_RESPONSE)"
else
    test_result "FAIL" "HTTPS connection failed (HTTP $HTTPS_RESPONSE)" "Check if HAProxy is listening on port 443 and SSL certificate is valid"
fi

# Test 4: SSL Certificate Verification
echo -e "${YELLOW}Test 4: SSL Certificate${NC}"
echo "----------------------------------------"

SSL_INFO=$(echo | openssl s_client -connect "$HAPROXY_HOST:443" -servername "$HAPROXY_HOST" 2>/dev/null | openssl x509 -noout -subject -dates 2>/dev/null || echo "")

if [ -n "$SSL_INFO" ]; then
    test_result "PASS" "SSL certificate is valid" "$SSL_INFO"
else
    test_result "FAIL" "SSL certificate validation failed" "Check certificate configuration"
fi

# Test 5: Security Headers
echo -e "${YELLOW}Test 5: Security Headers${NC}"
echo "----------------------------------------"

HEADERS=$(curl -s -k -I "https://$HAPROXY_HOST/" 2>/dev/null || echo "")

HSTS_FOUND=false
XFRAME_FOUND=false
XCONTENT_FOUND=false

if echo "$HEADERS" | grep -qi "Strict-Transport-Security"; then
    HSTS_FOUND=true
fi

if echo "$HEADERS" | grep -qi "X-Frame-Options"; then
    XFRAME_FOUND=true
fi

if echo "$HEADERS" | grep -qi "X-Content-Type-Options"; then
    XCONTENT_FOUND=true
fi

if [ "$HSTS_FOUND" = true ] && [ "$XFRAME_FOUND" = true ] && [ "$XCONTENT_FOUND" = true ]; then
    test_result "PASS" "Security headers are present" "HSTS, X-Frame-Options, X-Content-Type-Options"
else
    MISSING=""
    [ "$HSTS_FOUND" = false ] && MISSING="$MISSING HSTS"
    [ "$XFRAME_FOUND" = false ] && MISSING="$MISSING X-Frame-Options"
    [ "$XCONTENT_FOUND" = false ] && MISSING="$MISSING X-Content-Type-Options"
    test_result "FAIL" "Some security headers are missing" "Missing:$MISSING"
fi

# Test 6: PostgreSQL Connectivity (Port 5432)
echo -e "${YELLOW}Test 6: PostgreSQL Connectivity${NC}"
echo "----------------------------------------"

if timeout 5 bash -c "cat < /dev/null > /dev/tcp/$HAPROXY_HOST/5432" 2>/dev/null; then
    test_result "PASS" "PostgreSQL port is accessible"
else
    test_result "FAIL" "PostgreSQL port is not accessible" "Check if HAProxy is listening on port 5432"
fi

# Test 7: Stats Page Authentication
echo -e "${YELLOW}Test 7: Stats Page${NC}"
echo "----------------------------------------"

STATS_RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" -u "$HAPROXY_STATS_USER:$HAPROXY_STATS_PASSWORD" "http://$HAPROXY_HOST:8404/stats" 2>/dev/null || echo "000")

if [ "$STATS_RESPONSE" = "200" ]; then
    test_result "PASS" "Stats page is accessible with authentication"
else
    test_result "FAIL" "Stats page authentication failed (HTTP $STATS_RESPONSE)" "Check HAPROXY_STATS_USER and HAPROXY_STATS_PASSWORD"
fi

# Test 8: Prometheus Metrics Endpoint
echo -e "${YELLOW}Test 8: Prometheus Metrics${NC}"
echo "----------------------------------------"

METRICS_RESPONSE=$(curl -s "http://$HAPROXY_HOST:8404/metrics" 2>/dev/null || echo "")

if echo "$METRICS_RESPONSE" | grep -q "haproxy_"; then
    test_result "PASS" "Prometheus metrics endpoint is working"
else
    test_result "FAIL" "Prometheus metrics endpoint is not responding" "Check HAProxy configuration"
fi

# Test 9: Health Check Endpoint
echo -e "${YELLOW}Test 9: Health Check Endpoint${NC}"
echo "----------------------------------------"

HEALTH_RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" "http://$HAPROXY_HOST:8404/health" 2>/dev/null || echo "000")

if [ "$HEALTH_RESPONSE" = "200" ]; then
    test_result "PASS" "Health check endpoint is responding"
else
    test_result "FAIL" "Health check endpoint failed (HTTP $HEALTH_RESPONSE)"
fi

# Test 10: Backend Health Status
echo -e "${YELLOW}Test 10: Backend Health Status${NC}"
echo "----------------------------------------"

STATS_CSV=$(curl -s -u "$HAPROXY_STATS_USER:$HAPROXY_STATS_PASSWORD" "http://$HAPROXY_HOST:8404/stats;csv" 2>/dev/null || echo "")

if [ -n "$STATS_CSV" ]; then
    KEYCLOAK_UP=$(echo "$STATS_CSV" | grep "keycloak_backend" | grep -c ",UP," || echo "0")
    POSTGRES_UP=$(echo "$STATS_CSV" | grep "postgres_backend" | grep -c ",UP," || echo "0")
    
    if [ "$KEYCLOAK_UP" -gt 0 ] && [ "$POSTGRES_UP" -gt 0 ]; then
        test_result "PASS" "Backend servers are healthy" "Keycloak: $KEYCLOAK_UP UP, PostgreSQL: $POSTGRES_UP UP"
    else
        test_result "FAIL" "Some backend servers are down" "Keycloak: $KEYCLOAK_UP UP, PostgreSQL: $POSTGRES_UP UP"
    fi
else
    test_result "FAIL" "Could not retrieve backend status" "Check stats authentication"
fi

# Test 11: X-Forwarded-For Header
echo -e "${YELLOW}Test 11: X-Forwarded-For Header${NC}"
echo "----------------------------------------"

# This test requires a backend that echoes headers
# For now, we'll just check if the header is configured in HAProxy
if docker exec haproxy-lb cat /usr/local/etc/haproxy/haproxy.cfg | grep -q "X-Forwarded-For"; then
    test_result "PASS" "X-Forwarded-For header is configured"
else
    test_result "FAIL" "X-Forwarded-For header is not configured"
fi

# Test 12: Connection Timeout Handling
echo -e "${YELLOW}Test 12: Timeout Configuration${NC}"
echo "----------------------------------------"

if docker exec haproxy-lb cat /usr/local/etc/haproxy/haproxy.cfg | grep -q "timeout connect"; then
    test_result "PASS" "Timeout configuration is present"
else
    test_result "FAIL" "Timeout configuration is missing"
fi

# Summary
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Test Summary${NC}"
echo -e "${BLUE}========================================${NC}"

TOTAL=$((PASSED + FAILED))
PASS_RATE=$((PASSED * 100 / TOTAL))

echo "Total Tests: $TOTAL"
echo -e "${GREEN}Passed: $PASSED${NC}"
echo -e "${RED}Failed: $FAILED${NC}"
echo "Pass Rate: $PASS_RATE%"
echo ""

if [ $FAILED -eq 0 ]; then
    echo -e "${GREEN}✓ All integration tests passed!${NC}"
    exit 0
else
    echo -e "${RED}✗ Some integration tests failed${NC}"
    echo "Review the failures above and fix the issues."
    exit 1
fi
