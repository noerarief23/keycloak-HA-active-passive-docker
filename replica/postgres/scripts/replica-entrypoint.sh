#!/bin/bash
# Deprecated / unused replica entrypoint.
# 
# The replica is initialized via init-replica.sh and the
# docker-entrypoint-initdb.d mechanism. This script is kept only
# as a stub to avoid confusion if referenced accidentally.

echo "replica-entrypoint.sh is deprecated and not used. Initialization is handled by init-replica.sh."

# Exit successfully without performing any actions.
exit 0
