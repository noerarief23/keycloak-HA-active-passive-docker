#!/bin/bash
#
# HAProxy Backend Health Check Script
# Queries HAProxy stats API and displays backend server status
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

# Check if curl is available
if ! command -v curl &> /dev/null; then
    echo -e "${RED}Error: curl is not installed${NC}"
    exit 1
fi

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}HAProxy Backend Health Check${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# Fetch stats
STATS=$(curl -s -u "$HAPROXY_STATS_USER:$HAPROXY_STATS_PASSWORD" "$HAPROXY_STATS_URL")

if [ -z "$STATS" ]; then
    echo -e "${RED}Error: Could not fetch stats from HAProxy${NC}"
    echo "Check:"
    echo "  - HAProxy is running"
    echo "  - Stats URL is correct: $HAPROXY_STATS_URL"
    echo "  - Credentials are correct"
    exit 1
fi

# Function to display backend info
display_backend() {
    local backend=$1
    local title=$2
    
    echo -e "${YELLOW}$title${NC}"
    echo "----------------------------------------"
    
    # Get backend data
    local backend_data=$(echo "$STATS" | grep "^$backend,")
    
    if [ -z "$backend_data" ]; then
        echo -e "${RED}Backend not found: $backend${NC}"
        return
    fi
    
    # Parse and display each server
    echo "$backend_data" | while IFS=',' read -r pxname svname qcur qmax scur smax slim stot bin bout dreq dresp ereq econ eresp wretr wredis status weight act bck chkfail chkdown lastchg downtime qlimit pid iid sid throttle lbtot tracked type rate rate_lim rate_max check_status check_code check_duration hrsp_1xx hrsp_2xx hrsp_3xx hrsp_4xx hrsp_5xx hrsp_other hanafail req_rate req_rate_max req_tot cli_abrt srv_abrt comp_in comp_out comp_byp comp_rsp lastsess last_chk last_agt qtime ctime rtime ttime agent_status agent_code agent_duration check_desc agent_desc check_rise check_fall check_health agent_rise agent_fall agent_health addr cookie mode algo conn_rate conn_rate_max conn_tot intercepted dcon dses wrew connect reuse cache_lookups cache_hits tls_version tls_cipher_suite rest; do
        
        # Skip BACKEND summary line
        if [ "$svname" = "BACKEND" ]; then
            continue
        fi
        
        # Determine status color
        local status_color=$RED
        if [ "$status" = "UP" ]; then
            status_color=$GREEN
        elif [ "$status" = "DOWN" ]; then
            status_color=$RED
        elif [[ "$status" == *"MAINT"* ]]; then
            status_color=$YELLOW
        fi
        
        # Display server info
        printf "  %-25s ${status_color}%-10s${NC} " "$svname" "$status"
        printf "Sessions: %-5s " "$scur"
        printf "Total: %-8s " "$stot"
        
        if [ -n "$check_status" ] && [ "$check_status" != "" ]; then
            printf "Check: %-15s " "$check_status"
        fi
        
        if [ -n "$check_duration" ] && [ "$check_duration" != "" ]; then
            printf "(%sms)" "$check_duration"
        fi
        
        echo ""
    done
    
    echo ""
}

# Display Keycloak backend
display_backend "keycloak_backend" "Keycloak Backend"

# Display PostgreSQL backend
display_backend "postgres_backend" "PostgreSQL Backend"

# Check for any DOWN servers
DOWN_COUNT=$(echo "$STATS" | grep -c ",DOWN," || true)

if [ "$DOWN_COUNT" -gt 0 ]; then
    echo -e "${RED}⚠ Warning: $DOWN_COUNT server(s) are DOWN${NC}"
    echo ""
    exit 1
else
    echo -e "${GREEN}✓ All servers are healthy${NC}"
    echo ""
    exit 0
fi
