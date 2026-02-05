#!/bin/bash
set -e

echo "Starting PostgreSQL Replica..."

# Check if this is first run (no data directory)
if [ ! -f "$PGDATA/PG_VERSION" ]; then
    echo "First run detected. Initializing replica from primary..."
    
    # Wait for primary server
    TIMEOUT_SECONDS=300
    START_TIME=$(date +%s)
    until PGPASSWORD=${REPLICATION_PASSWORD} pg_isready -h postgres-primary -U replicator; do
      echo "Waiting for primary server..."
      sleep 5
      CURRENT_TIME=$(date +%s)
      ELAPSED=$(( CURRENT_TIME - START_TIME ))
      if [ "$ELAPSED" -ge "$TIMEOUT_SECONDS" ]; then
        echo "Error: Timeout waiting for primary server" >&2
        exit 1
      fi
    done
    
    echo "Primary server ready. Performing base backup..."
    
    # Perform base backup
    PGPASSWORD=${REPLICATION_PASSWORD} pg_basebackup \
        -h postgres-primary \
        -p 5432 \
        -U replicator \
        -D "$PGDATA" \
        -Fp \
        -Xs \
        -P \
        -R
    
    echo "Base backup completed!"
    
    # Copy custom configuration files
    if [ -f /etc/postgresql/postgresql.conf ]; then
        cp /etc/postgresql/postgresql.conf "$PGDATA/postgresql.conf"
    fi
    
    if [ -f /etc/postgresql/pg_hba.conf ]; then
        cp /etc/postgresql/pg_hba.conf "$PGDATA/pg_hba.conf"
    fi
    
    # Set ownership
    chown -R postgres:postgres "$PGDATA"
    chmod 700 "$PGDATA"
fi

echo "Starting PostgreSQL server..."

# Start PostgreSQL as postgres user
exec gosu postgres postgres \
    -c config_file="$PGDATA/postgresql.conf" \
    -c hba_file="$PGDATA/pg_hba.conf"
