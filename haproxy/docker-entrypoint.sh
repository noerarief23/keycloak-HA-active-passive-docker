#!/bin/sh
set -e

# Set defaults if not provided
HAPROXY_STATS_USER=${HAPROXY_STATS_USER:-admin}
HAPROXY_STATS_PASSWORD=${HAPROXY_STATS_PASSWORD:-changeme}
PRIMARY_SERVER_IP=${PRIMARY_SERVER_IP:-172.41.1.10}
REPLICA_SERVER_IP=${REPLICA_SERVER_IP:-172.41.2.20}
PRIMARY_KEYCLOAK_PORT=${PRIMARY_KEYCLOAK_PORT:-8080}
REPLICA_KEYCLOAK_PORT=${REPLICA_KEYCLOAK_PORT:-8081}
PRIMARY_POSTGRES_PORT=${PRIMARY_POSTGRES_PORT:-5432}
REPLICA_POSTGRES_PORT=${REPLICA_POSTGRES_PORT:-5433}

echo "Configuring HAProxy with environment variables..."
echo "Stats User: $HAPROXY_STATS_USER"
echo "Primary Server: $PRIMARY_SERVER_IP"
echo "  - Keycloak: $PRIMARY_KEYCLOAK_PORT"
echo "  - PostgreSQL: $PRIMARY_POSTGRES_PORT"
echo "Replica Server: $REPLICA_SERVER_IP"
echo "  - Keycloak: $REPLICA_KEYCLOAK_PORT"
echo "  - PostgreSQL: $REPLICA_POSTGRES_PORT"

# Substitute environment variables in haproxy.cfg using sed
sed -e "s/\${HAPROXY_STATS_USER}/$HAPROXY_STATS_USER/g" \
    -e "s/\${HAPROXY_STATS_PASSWORD}/$HAPROXY_STATS_PASSWORD/g" \
    -e "s/\${PRIMARY_SERVER_IP}/$PRIMARY_SERVER_IP/g" \
    -e "s/\${REPLICA_SERVER_IP}/$REPLICA_SERVER_IP/g" \
    -e "s/\${PRIMARY_KEYCLOAK_PORT}/$PRIMARY_KEYCLOAK_PORT/g" \
    -e "s/\${REPLICA_KEYCLOAK_PORT}/$REPLICA_KEYCLOAK_PORT/g" \
    -e "s/\${PRIMARY_POSTGRES_PORT}/$PRIMARY_POSTGRES_PORT/g" \
    -e "s/\${REPLICA_POSTGRES_PORT}/$REPLICA_POSTGRES_PORT/g" \
    /usr/local/etc/haproxy/haproxy.cfg.template \
    > /usr/local/etc/haproxy/haproxy.cfg

echo "HAProxy configuration generated successfully"

# Validate configuration
haproxy -c -f /usr/local/etc/haproxy/haproxy.cfg

# Start HAProxy
echo "Starting HAProxy..."
exec haproxy -f /usr/local/etc/haproxy/haproxy.cfg "$@"
