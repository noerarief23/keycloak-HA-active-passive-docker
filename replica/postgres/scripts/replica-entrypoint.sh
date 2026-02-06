#!/bin/bash
set -e

echo "Initializing PostgreSQL Replica Server..."

# Wait for primary to be ready
echo "Waiting for primary server to be ready..."
until PGPASSWORD=${REPLICATION_PASSWORD} pg_isready -h ${PRIMARY_HOST:-postgres-primary} -p ${PRIMARY_PORT:-5432} -U postgres 2>/dev/null; do
    echo "${PRIMARY_HOST:-postgres-primary}:${PRIMARY_PORT:-5432} - waiting..."
    sleep 2
done
echo "${PRIMARY_HOST:-postgres-primary}:${PRIMARY_PORT:-5432} - accepting connections"

# Check if data directory is empty or needs initialization
if [ ! -f "$PGDATA/PG_VERSION" ]; then
    echo "Primary server is ready. Starting base backup..."
    
    # Clean up any existing data
    if [ -d "$PGDATA" ]; then
        echo "Removing existing data directory contents..."
        rm -rf "$PGDATA"/*
    fi
    
    # Perform base backup from primary
    PGPASSWORD=${REPLICATION_PASSWORD} pg_basebackup \
        -h ${PRIMARY_HOST:-postgres-primary} \
        -p ${PRIMARY_PORT:-5432} \
        -U replicator \
        -D "$PGDATA" \
        -Fp \
        -Xs \
        -P \
        -R
    
    echo "Base backup completed successfully!"
    
    # Set proper ownership
    chown -R postgres:postgres "$PGDATA"
    chmod 700 "$PGDATA"
    
    echo "Replica server initialized successfully!"
fi

# Start PostgreSQL as postgres user (not root)
echo "Starting PostgreSQL as postgres user..."
exec gosu postgres postgres \
    -c config_file=/etc/postgresql/postgresql.conf \
    -c hba_file=/etc/postgresql/pg_hba.conf
