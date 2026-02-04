#!/bin/bash
# Script to promote PostgreSQL replica to primary
# Run this script on Server B (Replica) during failover

set -e

echo "========================================="
echo "PostgreSQL Replica Promotion Script"
echo "========================================="
echo ""
echo "WARNING: This will promote the replica to become the new primary."
echo "Make sure the original primary is stopped before proceeding."
echo ""
read -p "Are you sure you want to continue? (yes/no): " confirm

if [ "$confirm" != "yes" ]; then
    echo "Promotion cancelled."
    exit 0
fi

echo ""
echo "Step 1: Promoting PostgreSQL replica..."

# Create the promotion trigger file
docker exec postgres-replica touch /tmp/promote_trigger

# Wait for promotion to complete with polling
echo "Waiting for PostgreSQL promotion to complete..."
MAX_WAIT_SECONDS=30
SLEEP_INTERVAL=2
ELAPSED=0
PROMOTED=0

while [ "$ELAPSED" -lt "$MAX_WAIT_SECONDS" ]; do
    # Check if PostgreSQL is out of recovery mode (returns 't' for true when NOT in recovery)
    if docker exec postgres-replica psql -U postgres -t -A -c "SELECT NOT pg_is_in_recovery();" 2>/dev/null | grep -q "^t$"; then
        PROMOTED=1
        break
    fi
    sleep "$SLEEP_INTERVAL"
    ELAPSED=$((ELAPSED + SLEEP_INTERVAL))
done

# Check if promotion was successful
if [ "$PROMOTED" -eq 1 ]; then
    echo "✓ PostgreSQL replica successfully promoted to primary!"
else
    echo "✗ Promotion failed. PostgreSQL is still in recovery mode."
    exit 1
fi

echo ""
echo "Step 2: Starting Keycloak on the new primary server..."

# Start Keycloak with the manual profile
docker compose -f docker-compose-replica.yml --profile manual up -d keycloak-replica

# Wait for Keycloak to be ready (up to 60 seconds to match health check start_period)
echo "Waiting for Keycloak to start..."
MAX_WAIT_SECONDS=60
SLEEP_INTERVAL=5
ELAPSED=0
KEYCLOAK_READY=0

while [ "$ELAPSED" -lt "$MAX_WAIT_SECONDS" ]; do
    if docker exec keycloak-replica curl -sf http://localhost:8080/health/ready > /dev/null 2>&1; then
        KEYCLOAK_READY=1
        break
    fi
    sleep "$SLEEP_INTERVAL"
    ELAPSED=$((ELAPSED + SLEEP_INTERVAL))
done

# Check Keycloak health
if [ "$KEYCLOAK_READY" -eq 1 ]; then
    echo "✓ Keycloak is running and ready!"
else
    echo "⚠ Keycloak may still be starting. Check logs with: docker logs keycloak-replica"
fi

echo ""
echo "========================================="
echo "Failover Complete!"
echo "========================================="
echo ""
echo "Next steps:"
echo "1. Update your load balancer or DNS to point to this server"
echo "2. Monitor the system logs: docker compose -f docker-compose-replica.yml logs -f"
echo "3. Verify Keycloak is accessible at: http://localhost:8081"
echo ""
echo "Note: All active sessions from the original primary will be lost."
echo "Users will need to log in again."
echo ""
