#!/bin/bash
# Health check script for monitoring the HA setup

echo "========================================="
echo "Keycloak HA Health Check"
echo "========================================="
echo ""

# Function to check if container is running
check_container() {
    local container_name=$1
    if docker ps --format '{{.Names}}' | grep -q "^${container_name}$"; then
        echo "✓ ${container_name} is running"
        return 0
    else
        echo "✗ ${container_name} is not running"
        return 1
    fi
}

# Function to check PostgreSQL replication status
check_replication() {
    local container_name=$1
    echo ""
    echo "Checking replication status on ${container_name}..."
    
    if check_container "${container_name}"; then
        if docker exec "${container_name}" psql -U postgres -c "SELECT pg_is_in_recovery();" 2>/dev/null | grep -q "t"; then
            echo "  Status: REPLICA (read-only)"
            
            # Check replication lag
            docker exec "${container_name}" psql -U postgres -c "SELECT EXTRACT(EPOCH FROM (now() - pg_last_xact_replay_timestamp())) AS replication_lag_seconds;" 2>/dev/null
        elif docker exec "${container_name}" psql -U postgres -c "SELECT pg_is_in_recovery();" 2>/dev/null | grep -q "f"; then
            echo "  Status: PRIMARY (read-write)"
            
            # Check connected replicas
            docker exec "${container_name}" psql -U postgres -c "SELECT client_addr, state, sync_state FROM pg_stat_replication;" 2>/dev/null
        fi
    fi
}

# Function to check Keycloak health
check_keycloak() {
    local container_name=$1
    local port=$2
    
    if check_container "${container_name}"; then
        if docker exec "${container_name}" curl -sf http://localhost:8080/health/ready > /dev/null 2>&1; then
            echo "  Health: READY"
            echo "  URL: http://localhost:${port}"
        else
            echo "  Health: NOT READY"
        fi
    fi
}

# Check Primary Server
echo "PRIMARY SERVER (Server A):"
echo "--------------------------"
check_container "postgres-primary"
check_container "keycloak-primary"
check_replication "postgres-primary"
echo ""
check_keycloak "keycloak-primary" "8080"

echo ""
echo ""

# Check Replica Server
echo "REPLICA SERVER (Server B):"
echo "--------------------------"
check_container "postgres-replica"
check_container "keycloak-replica"
check_replication "postgres-replica"
echo ""
check_keycloak "keycloak-replica" "8081"

echo ""
echo "========================================="
echo ""
