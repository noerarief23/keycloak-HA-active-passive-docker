#!/bin/bash
set -e

echo "Initializing PostgreSQL Replica Server..."

# Wait for primary server to be ready
until PGPASSWORD=${REPLICATION_PASSWORD} pg_isready -h postgres-primary -U replicator; do
  echo "Waiting for primary server to be ready..."
  sleep 5
done

echo "Primary server is ready. Starting base backup..."

# Remove existing data directory if it exists
if [ -d "$PGDATA" ]; then
    echo "Removing existing data directory..."
    rm -rf "$PGDATA"/*
fi

# Perform base backup from primary
PGPASSWORD=${REPLICATION_PASSWORD} pg_basebackup \
    -h postgres-primary \
    -p 5432 \
    -U replicator \
    -D "$PGDATA" \
    -Fp \
    -Xs \
    -P \
    -R

echo "Base backup completed successfully!"

# Create standby.signal file to indicate this is a replica
touch "$PGDATA/standby.signal"

echo "Replica server initialized successfully!"
