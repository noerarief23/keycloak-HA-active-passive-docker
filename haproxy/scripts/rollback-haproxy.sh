#!/bin/bash
#
# HAProxy Rollback Script
# Rolls back HAProxy to a previous configuration
#

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

BACKUP_DIR="./haproxy-backups"

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}HAProxy Rollback Script${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# Check if backup directory exists
if [ ! -d "$BACKUP_DIR" ]; then
    echo -e "${RED}Error: Backup directory not found: $BACKUP_DIR${NC}"
    echo ""
    echo "No backups available to rollback."
    exit 1
fi

# List available backups
echo -e "${YELLOW}Available Backups:${NC}"
echo "----------------------------------------"

BACKUPS=($(ls -1t "$BACKUP_DIR" | grep "haproxy-backup-.*\.tar\.gz"))

if [ ${#BACKUPS[@]} -eq 0 ]; then
    echo -e "${RED}No backups found${NC}"
    exit 1
fi

for i in "${!BACKUPS[@]}"; do
    BACKUP_FILE="${BACKUPS[$i]}"
    BACKUP_DATE=$(echo "$BACKUP_FILE" | sed 's/haproxy-backup-\(.*\)\.tar\.gz/\1/')
    BACKUP_SIZE=$(du -h "$BACKUP_DIR/$BACKUP_FILE" | cut -f1)
    echo "  [$i] $BACKUP_FILE ($BACKUP_SIZE) - $BACKUP_DATE"
done

echo ""

# Prompt user to select backup
read -p "Select backup number to restore (or 'q' to quit): " SELECTION

if [ "$SELECTION" = "q" ]; then
    echo "Rollback cancelled"
    exit 0
fi

# Validate selection
if ! [[ "$SELECTION" =~ ^[0-9]+$ ]] || [ "$SELECTION" -ge ${#BACKUPS[@]} ]; then
    echo -e "${RED}Invalid selection${NC}"
    exit 1
fi

SELECTED_BACKUP="${BACKUPS[$SELECTION]}"
BACKUP_PATH="$BACKUP_DIR/$SELECTED_BACKUP"

echo ""
echo -e "${YELLOW}Selected backup: $SELECTED_BACKUP${NC}"
echo ""

# Confirm rollback
read -p "Are you sure you want to rollback to this backup? (yes/no): " CONFIRM

if [ "$CONFIRM" != "yes" ]; then
    echo "Rollback cancelled"
    exit 0
fi

echo ""

# Step 1: Create backup of current configuration
echo -e "${YELLOW}Step 1: Backing Up Current Configuration${NC}"
echo "----------------------------------------"

CURRENT_BACKUP="haproxy-backup-before-rollback-$(date +%Y%m%d-%H%M%S).tar.gz"

tar -czf "$BACKUP_DIR/$CURRENT_BACKUP" \
    haproxy/ \
    docker-compose-lb.yml \
    .env 2>/dev/null || true

echo -e "${GREEN}✓${NC} Current configuration backed up to: $CURRENT_BACKUP"
echo ""

# Step 2: Stop HAProxy container
echo -e "${YELLOW}Step 2: Stopping HAProxy Container${NC}"
echo "----------------------------------------"

if docker ps | grep -q haproxy-lb; then
    docker compose -f docker-compose-lb.yml stop haproxy
    echo -e "${GREEN}✓${NC} HAProxy container stopped"
else
    echo -e "${YELLOW}⚠${NC} HAProxy container is not running"
fi

echo ""

# Step 3: Extract backup
echo -e "${YELLOW}Step 3: Restoring Configuration from Backup${NC}"
echo "----------------------------------------"

# Create temporary directory
TEMP_DIR=$(mktemp -d)

# Extract backup to temporary directory
tar -xzf "$BACKUP_PATH" -C "$TEMP_DIR"

# Restore files
if [ -d "$TEMP_DIR/haproxy" ]; then
    rm -rf haproxy.old 2>/dev/null || true
    mv haproxy haproxy.old 2>/dev/null || true
    mv "$TEMP_DIR/haproxy" ./
    echo -e "${GREEN}✓${NC} HAProxy configuration restored"
fi

if [ -f "$TEMP_DIR/docker-compose-lb.yml" ]; then
    mv docker-compose-lb.yml docker-compose-lb.yml.old 2>/dev/null || true
    mv "$TEMP_DIR/docker-compose-lb.yml" ./
    echo -e "${GREEN}✓${NC} Docker Compose configuration restored"
fi

if [ -f "$TEMP_DIR/.env" ]; then
    mv .env .env.old 2>/dev/null || true
    mv "$TEMP_DIR/.env" ./
    echo -e "${GREEN}✓${NC} Environment variables restored"
fi

# Clean up temporary directory
rm -rf "$TEMP_DIR"

echo ""

# Step 4: Validate restored configuration
echo -e "${YELLOW}Step 4: Validating Restored Configuration${NC}"
echo "----------------------------------------"

if docker run --rm -v "$(pwd)/haproxy:/usr/local/etc/haproxy:ro" \
    haproxy:2.9-alpine haproxy -c -f /usr/local/etc/haproxy/haproxy.cfg > /dev/null 2>&1; then
    echo -e "${GREEN}✓${NC} Configuration is valid"
else
    echo -e "${RED}✗${NC} Configuration validation failed"
    echo ""
    echo "Rolling back to previous state..."
    
    # Restore from .old files
    rm -rf haproxy 2>/dev/null || true
    mv haproxy.old haproxy 2>/dev/null || true
    mv docker-compose-lb.yml.old docker-compose-lb.yml 2>/dev/null || true
    mv .env.old .env 2>/dev/null || true
    
    echo -e "${RED}Rollback failed. Previous configuration restored.${NC}"
    exit 1
fi

echo ""

# Step 5: Restart HAProxy
echo -e "${YELLOW}Step 5: Restarting HAProxy${NC}"
echo "----------------------------------------"

docker compose -f docker-compose-lb.yml up -d

echo -e "${GREEN}✓${NC} HAProxy container started"
echo ""

# Step 6: Wait and verify
echo -e "${YELLOW}Step 6: Verifying HAProxy${NC}"
echo "----------------------------------------"

echo "Waiting for HAProxy to start..."
sleep 5

if docker ps | grep -q haproxy-lb; then
    echo -e "${GREEN}✓${NC} HAProxy is running"
else
    echo -e "${RED}✗${NC} HAProxy failed to start"
    echo ""
    echo "Container logs:"
    docker logs haproxy-lb
    exit 1
fi

# Check health
echo ""
echo "Checking backend health..."
sleep 5

if [ -f "haproxy/scripts/check-backends.sh" ]; then
    cd haproxy/scripts
    if ./check-backends.sh; then
        echo -e "${GREEN}✓${NC} All backends are healthy"
    else
        echo -e "${YELLOW}⚠${NC} Some backends are not healthy"
    fi
    cd ../..
fi

echo ""

# Step 7: Clean up old files
echo -e "${YELLOW}Step 7: Cleaning Up${NC}"
echo "----------------------------------------"

read -p "Remove old configuration files? (y/n) " -n 1 -r
echo

if [[ $REPLY =~ ^[Yy]$ ]]; then
    rm -rf haproxy.old 2>/dev/null || true
    rm -f docker-compose-lb.yml.old 2>/dev/null || true
    rm -f .env.old 2>/dev/null || true
    echo -e "${GREEN}✓${NC} Old files removed"
else
    echo -e "${YELLOW}⚠${NC} Old files kept (*.old)"
fi

echo ""

# Summary
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Rollback Complete!${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

echo -e "${GREEN}✓ Successfully rolled back to: $SELECTED_BACKUP${NC}"
echo ""

# Get server IP
SERVER_IP=$(hostname -I | awk '{print $1}')

echo "HAProxy is now running with the restored configuration."
echo ""
echo "Access Points:"
echo "  Stats Page: http://$SERVER_IP:8404/stats"
echo "  Health:     http://$SERVER_IP:8404/health"
echo ""

echo "Verify the rollback:"
echo "  1. Check stats page for backend status"
echo "  2. Test connectivity: curl -k https://$SERVER_IP/"
echo "  3. Review logs: docker logs haproxy-lb"
echo ""

echo "If issues persist:"
echo "  - Check logs: docker logs haproxy-lb"
echo "  - Restore from another backup: ./haproxy/scripts/rollback-haproxy.sh"
echo "  - Manual restore from: $BACKUP_DIR/$CURRENT_BACKUP"
echo ""
