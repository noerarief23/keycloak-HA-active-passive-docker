#!/bin/bash
#
# Automatic Failover Script
# Monitors primary PostgreSQL and auto-starts keycloak-replica on failure
#

set -e

# Configuration
PRIMARY_POSTGRES_HOST="${PRIMARY_SERVER_IP}"
PRIMARY_POSTGRES_PORT="${PRIMARY_POSTGRES_PORT:-5432}"
CHECK_INTERVAL=5
FAILURE_THRESHOLD=3
REPLICA_COMPOSE_FILE="docker-compose-replica.yml"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo "=========================================="
echo "PostgreSQL Automatic Failover Monitor"
echo "=========================================="
echo "Primary PostgreSQL: $PRIMARY_POSTGRES_HOST:$PRIMARY_POSTGRES_PORT"
echo "Check interval: ${CHECK_INTERVAL}s"
echo "Failure threshold: $FAILURE_THRESHOLD"
echo ""
echo "NOTE: postgres-replica is already running as standby (streaming replication)"
echo "      This script will only start keycloak-replica when primary PostgreSQL fails"
echo ""

failure_count=0
keycloak_replica_started=false

while true; do
    # Check if primary PostgreSQL is responding
    if pg_isready -h "$PRIMARY_POSTGRES_HOST" -p "$PRIMARY_POSTGRES_PORT" -U postgres > /dev/null 2>&1; then
        # Primary PostgreSQL is UP
        if [ $failure_count -gt 0 ]; then
            echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')] Primary PostgreSQL recovered${NC}"
            failure_count=0
        fi
        
        # If keycloak-replica was started and primary is back, log warning
        if [ "$keycloak_replica_started" = true ]; then
            echo -e "${YELLOW}[$(date '+%Y-%m-%d %H:%M:%S')] Primary PostgreSQL is back. Manual intervention may be needed.${NC}"
            echo -e "${YELLOW}    - Consider stopping keycloak-replica if not needed${NC}"
            echo -e "${YELLOW}    - Or reconfigure replication from primary${NC}"
        fi
    else
        # Primary PostgreSQL is DOWN
        failure_count=$((failure_count + 1))
        echo -e "${RED}[$(date '+%Y-%m-%d %H:%M:%S')] Primary PostgreSQL check failed ($failure_count/$FAILURE_THRESHOLD)${NC}"
        
        if [ $failure_count -ge $FAILURE_THRESHOLD ] && [ "$keycloak_replica_started" = false ]; then
            echo -e "${RED}[$(date '+%Y-%m-%d %H:%M:%S')] PRIMARY POSTGRESQL DOWN! Starting keycloak-replica...${NC}"
            
            # Check if postgres-replica is running
            if docker ps --format '{{.Names}}' | grep -q "postgres-replica"; then
                echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')] postgres-replica is already running (standby mode)${NC}"
            else
                echo -e "${YELLOW}[$(date '+%Y-%m-%d %H:%M:%S')] WARNING: postgres-replica is not running!${NC}"
            fi
            
            # Start Keycloak replica
            echo -e "${YELLOW}[$(date '+%Y-%m-%d %H:%M:%S')] Starting keycloak-replica...${NC}"
            docker compose -f "$REPLICA_COMPOSE_FILE" --profile manual up -d keycloak-replica
            
            if [ $? -eq 0 ]; then
                echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')] Keycloak replica started successfully${NC}"
                keycloak_replica_started=true
                
                echo -e "${YELLOW}[$(date '+%Y-%m-%d %H:%M:%S')] MANUAL ACTION REQUIRED:${NC}"
                echo -e "${YELLOW}    1. Promote postgres-replica to primary: ./scripts/promote-replica.sh${NC}"
                echo -e "${YELLOW}    2. HAProxy will automatically route traffic to replica services${NC}"
                echo -e "${YELLOW}    3. Monitor services: docker compose -f $REPLICA_COMPOSE_FILE ps${NC}"
                
                # Send notification (optional)
                # curl -X POST "https://hooks.slack.com/..." -d '{"text":"PostgreSQL failover triggered - keycloak-replica started"}'
            else
                echo -e "${RED}[$(date '+%Y-%m-%d %H:%M:%S')] Failed to start Keycloak replica!${NC}"
            fi
        fi
    fi
    
    sleep $CHECK_INTERVAL
done
