#!/bin/bash
set -e

echo "Initializing PostgreSQL Replica Server..."

# Get primary port from environment variable (default to 5432)
PRIMARY_POSTGRES_PORT=${PRIMARY_POSTGRES_PORT:-5432}

echo "Connecting to primary at postgres-primary:${PRIMARY_POSTGRES_PORT}"

# Wait for primary server to be ready with timeout
TIMEOUT_SECONDS=300  # 5 minutes
START_TIME=$(date +%s)
until PGPASSWORD=${REPLICATION_PASSWORD} pg_isready -h postgres-primary -p ${PRIMARY_POSTGRES_PORT} -U replicator; do
  echo "Waiting for primary server to be ready..."
  sleep 5
  CURRENT_TIME=$(date +%s)
  ELAPSED=$(( CURRENT_TIME - START_TIME ))
  if [ "$ELAPSED" -ge "$TIMEOUT_SECONDS" ]; then
    echo "Error: Timed out after ${TIMEOUT_SECONDS} seconds waiting for primary server to be ready." >&2
    exit 1
  fi
done

echo "Primary server is ready. Starting base backup..."

# Stop the temporary postgres instance started by docker-entrypoint
if [ -f "$PGDATA/postmaster.pid" ]; then
    echo "Stopping temporary postgres instance..."
    pg_ctl -D "$PGDATA" stop -m fast || true
    sleep 2
fi

# Remove existing data directory contents
echo "Removing existing data directory contents..."
rm -rf "$PGDATA"/*

# Perform base backup from primary
PGPASSWORD=${REPLICATION_PASSWORD} pg_basebackup \
    -h postgres-primary \
    -p ${PRIMARY_POSTGRES_PORT} \
    -U replicator \
    -D "$PGDATA" \
    -Fp \
    -Xs \
    -P \
    -R

echo "Base backup completed successfully!"

# Note: The -R flag in pg_basebackup automatically creates standby.signal
# so this file should already exist. No need to create it manually.

echo "Replica server initialized successfully!"
