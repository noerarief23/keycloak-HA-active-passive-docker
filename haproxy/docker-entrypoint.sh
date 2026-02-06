#!/bin/sh
set -e

# HAProxy entrypoint script to substitute environment variables in configuration
# This script creates a temporary config file with environment variables substituted
# and then starts HAProxy with the processed configuration

CONFIG_TEMPLATE="/usr/local/etc/haproxy/haproxy.cfg"
CONFIG_PROCESSED="/tmp/haproxy.cfg"

# Check if required environment variables are set
if [ -z "$HAPROXY_STATS_PASSWORD" ]; then
  echo "ERROR: HAPROXY_STATS_PASSWORD environment variable is not set"
  echo "Please set it in your .env.lb file before starting the container"
  exit 1
fi

# Set default values
HAPROXY_STATS_USER="${HAPROXY_STATS_USER:-admin}"

# Use sed to substitute environment variables in the configuration
sed -e "s/\${HAPROXY_STATS_USER}/$HAPROXY_STATS_USER/g" \
    -e "s/\${HAPROXY_STATS_PASSWORD}/$HAPROXY_STATS_PASSWORD/g" \
    "$CONFIG_TEMPLATE" > "$CONFIG_PROCESSED"

echo "HAProxy configuration processed successfully"
echo "Starting HAProxy..."

# Execute HAProxy with the processed configuration
exec haproxy -f "$CONFIG_PROCESSED" "$@"
