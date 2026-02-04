#!/bin/bash
# Script to verify replication is working correctly
# NOTE: This script assumes both containers are accessible from the same host.
# For separate servers, modify to use remote PostgreSQL connections.

echo "========================================="
echo "PostgreSQL Replication Verification"
echo "========================================="
echo ""

# Create a test table on primary in keycloak database
echo "Step 1: Creating test table on primary (keycloak database)..."
docker exec postgres-primary psql -U postgres -d keycloak -c "CREATE TABLE IF NOT EXISTS replication_test (id SERIAL PRIMARY KEY, test_data TEXT, created_at TIMESTAMP DEFAULT NOW());" 2>/dev/null

# Insert test data on primary
echo "Step 2: Inserting test data on primary..."
TEST_DATA="Test-$(date +%s)"
docker exec postgres-primary psql -U postgres -d keycloak -v test_data="$TEST_DATA" -c "INSERT INTO replication_test (test_data) VALUES (:'test_data');" 2>/dev/null

# Wait for replication
echo "Step 3: Waiting for replication (5 seconds)..."
sleep 5

# Check if data exists on replica
echo "Step 4: Verifying data on replica..."
RESULT=$(docker exec postgres-replica psql -U postgres -d keycloak -t -c "SELECT test_data FROM replication_test WHERE test_data = '${TEST_DATA}';" 2>/dev/null | xargs)

if [ "$RESULT" = "$TEST_DATA" ]; then
    echo "✓ Replication is working correctly!"
    echo "  Data successfully replicated from primary to replica."
else
    echo "✗ Replication verification failed!"
    echo "  Data was not found on replica."
    exit 1
fi

# Clean up
echo "Step 5: Cleaning up test data..."
docker exec postgres-primary psql -U postgres -d keycloak -c "DROP TABLE replication_test;" 2>/dev/null

echo ""
echo "========================================="
echo "Replication verification completed successfully!"
echo "========================================="
echo ""
