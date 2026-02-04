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

# Wait for promotion to complete
sleep 5

# Check if promotion was successful
if docker exec postgres-replica psql -U postgres -c "SELECT pg_is_in_recovery();" | grep -q "f"; then
    echo "✓ PostgreSQL replica successfully promoted to primary!"
else
    echo "✗ Promotion failed. PostgreSQL is still in recovery mode."
    exit 1
fi

echo ""
echo "Step 2: Starting Keycloak on the new primary server..."

# Start Keycloak with the manual profile
docker compose -f docker-compose-replica.yml --profile manual up -d keycloak-replica

# Wait for Keycloak to be ready
echo "Waiting for Keycloak to start..."
sleep 10

# Check Keycloak health
if docker exec keycloak-replica curl -sf http://localhost:8080/health/ready > /dev/null 2>&1; then
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
