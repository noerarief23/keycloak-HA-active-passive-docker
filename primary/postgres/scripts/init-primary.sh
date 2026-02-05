#!/bin/bash
set -e

echo "Initializing PostgreSQL Primary Server..."

# Wait for PostgreSQL to be ready
until pg_isready -U postgres; do
  echo "Waiting for PostgreSQL to be ready..."
  sleep 2
done

# Create replication user
psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<-EOSQL
    -- Create replication user
    DO \$\$
    BEGIN
        IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = 'replicator') THEN
            CREATE ROLE replicator WITH REPLICATION PASSWORD '${REPLICATION_PASSWORD}' LOGIN;
        END IF;
    END
    \$\$;
EOSQL

# Create Keycloak database
# Using \gexec instead of DO block because CREATE DATABASE cannot be run inside a transaction block
psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<-EOSQL
    SELECT 'CREATE DATABASE keycloak'
    WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'keycloak')\gexec
EOSQL

# Create Keycloak user and grant privileges
psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<-EOSQL
    DO \$\$
    BEGIN
        IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = 'keycloak') THEN
            CREATE USER keycloak WITH PASSWORD '${KEYCLOAK_DB_PASSWORD}';
        END IF;
    END
    \$\$;
EOSQL

# Grant privileges on keycloak database
psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "keycloak" <<-EOSQL
    GRANT ALL PRIVILEGES ON DATABASE keycloak TO keycloak;
    GRANT USAGE, CREATE ON SCHEMA public TO keycloak;
EOSQL

# Create replication slot
psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<-EOSQL
    -- Create replication slot if it doesn't already exist
    DO \$\$
    BEGIN
        IF NOT EXISTS (
            SELECT 1 FROM pg_replication_slots WHERE slot_name = 'replica_slot'
        ) THEN
            PERFORM pg_create_physical_replication_slot('replica_slot');
        END IF;
    END
    \$\$;
EOSQL

echo "Primary server initialized successfully!"

# Create haproxy_check user for HAProxy health checks
psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<-EOSQL
    -- Create haproxy_check user for health checks
    DO \$\$
    BEGIN
        IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = 'haproxy_check') THEN
            CREATE USER haproxy_check WITH LOGIN;
        END IF;
    END
    \$\$;
EOSQL

echo "HAProxy health check user created successfully!"
