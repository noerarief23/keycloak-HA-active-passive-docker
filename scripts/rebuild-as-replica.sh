#!/bin/bash
#
# Rebuild Primary as Replica Script
# Use this after primary fails and replica is promoted
# This script reconfigures the old primary to become a replica
#

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}=========================================="
echo "Rebuild Primary as Replica"
echo -e "==========================================${NC}"
echo ""

# Check if running as root
if [ "$EUID" -eq 0 ]; then 
    echo -e "${RED}ERROR: Do not run this script as root${NC}"
    echo "Run as regular user with Docker permissions"
    exit 1
fi

# Confirm action
echo -e "${YELLOW}WARNING: This will:${NC}"
echo "  1. Stop all services on this server"
echo "  2. Remove all PostgreSQL data"
echo "  3. Reconfigure this server as a replica"
echo "  4. Connect to the NEW primary server for replication"
echo ""
echo -e "${RED}This is a DESTRUCTIVE operation!${NC}"
echo ""
read -p "Are you sure you want to continue? (type 'yes' to confirm): " confirm

if [ "$confirm" != "yes" ]; then
    echo -e "${YELLOW}Operation cancelled${NC}"
    exit 0
fi

# Get new primary server details
echo ""
echo -e "${BLUE}Enter NEW Primary Server Details:${NC}"
read -p "New Primary Server IP: " NEW_PRIMARY_IP
read -p "New Primary PostgreSQL Port [5432]: " NEW_PRIMARY_PORT
NEW_PRIMARY_PORT=${NEW_PRIMARY_PORT:-5432}

echo ""
echo -e "${YELLOW}Configuration:${NC}"
echo "  New Primary IP: $NEW_PRIMARY_IP"
echo "  New Primary Port: $NEW_PRIMARY_PORT"
echo ""
read -p "Is this correct? (yes/no): " confirm2

if [ "$confirm2" != "yes" ]; then
    echo -e "${YELLOW}Operation cancelled${NC}"
    exit 0
fi

# Step 1: Stop all services
echo ""
echo -e "${BLUE}Step 1: Stopping all services...${NC}"
if [ -f "docker-compose-primary.yml" ]; then
    docker compose -f docker-compose-primary.yml down
    echo -e "${GREEN}✓ Services stopped${NC}"
else
    echo -e "${YELLOW}⚠ docker-compose-primary.yml not found, skipping${NC}"
fi

# Step 2: Backup old data
echo ""
echo -e "${BLUE}Step 2: Backing up old data...${NC}"
BACKUP_DATE=$(date +%Y%m%d_%H%M%S)

# Get volume names
PRIMARY_DATA_VOLUME=$(docker volume ls -q | grep postgres-primary-data || echo "")
PRIMARY_ARCHIVE_VOLUME=$(docker volume ls -q | grep postgres-primary-archive || echo "")

if [ -n "$PRIMARY_DATA_VOLUME" ]; then
    echo "Creating backup of $PRIMARY_DATA_VOLUME..."
    # Create a temporary container to backup
    docker run --rm -v ${PRIMARY_DATA_VOLUME}:/source -v $(pwd):/backup alpine \
        tar czf /backup/postgres-primary-data-backup-${BACKUP_DATE}.tar.gz -C /source .
    echo -e "${GREEN}✓ Data backed up to: postgres-primary-data-backup-${BACKUP_DATE}.tar.gz${NC}"
else
    echo -e "${YELLOW}⚠ No primary data volume found${NC}"
fi

# Step 3: Remove old volumes
echo ""
echo -e "${BLUE}Step 3: Removing old PostgreSQL data...${NC}"
if [ -n "$PRIMARY_DATA_VOLUME" ]; then
    docker volume rm ${PRIMARY_DATA_VOLUME} || echo "Volume already removed"
    echo -e "${GREEN}✓ Data volume removed${NC}"
fi

if [ -n "$PRIMARY_ARCHIVE_VOLUME" ]; then
    docker volume rm ${PRIMARY_ARCHIVE_VOLUME} || echo "Volume already removed"
    echo -e "${GREEN}✓ Archive volume removed${NC}"
fi

# Step 4: Update configuration
echo ""
echo -e "${BLUE}Step 4: Updating configuration...${NC}"

# Backup current .env
if [ -f ".env" ]; then
    cp .env .env.backup-${BACKUP_DATE}
    echo -e "${GREEN}✓ Current .env backed up to .env.backup-${BACKUP_DATE}${NC}"
fi

# Update .env file
if [ -f ".env.replica.example" ]; then
    cp .env.replica.example .env
    
    # Update PRIMARY_SERVER_IP
    if grep -q "PRIMARY_SERVER_IP=" .env; then
        sed -i "s/PRIMARY_SERVER_IP=.*/PRIMARY_SERVER_IP=${NEW_PRIMARY_IP}/" .env
    else
        echo "PRIMARY_SERVER_IP=${NEW_PRIMARY_IP}" >> .env
    fi
    
    # Update PRIMARY_POSTGRES_PORT
    if grep -q "PRIMARY_POSTGRES_PORT=" .env; then
        sed -i "s/PRIMARY_POSTGRES_PORT=.*/PRIMARY_POSTGRES_PORT=${NEW_PRIMARY_PORT}/" .env
    else
        echo "PRIMARY_POSTGRES_PORT=${NEW_PRIMARY_PORT}" >> .env
    fi
    
    echo -e "${GREEN}✓ Configuration updated${NC}"
    echo ""
    echo -e "${YELLOW}IMPORTANT: Review and update the following in .env:${NC}"
    echo "  - All passwords (must match new primary)"
    echo "  - POSTGRES_REPLICA_PORT (if needed)"
    echo "  - KEYCLOAK_REPLICA_HTTP_PORT (if needed)"
    echo ""
    read -p "Press Enter after reviewing .env file..."
else
    echo -e "${RED}ERROR: .env.replica.example not found${NC}"
    exit 1
fi

# Step 5: Use replica compose file
echo ""
echo -e "${BLUE}Step 5: Switching to replica configuration...${NC}"

if [ -f "docker-compose-primary.yml" ]; then
    mv docker-compose-primary.yml docker-compose-primary.yml.backup-${BACKUP_DATE}
    echo -e "${GREEN}✓ Backed up docker-compose-primary.yml${NC}"
fi

if [ -f "docker-compose-replica.yml" ]; then
    cp docker-compose-replica.yml docker-compose-primary.yml
    echo -e "${GREEN}✓ Using replica configuration${NC}"
else
    echo -e "${RED}ERROR: docker-compose-replica.yml not found${NC}"
    exit 1
fi

# Step 6: Start PostgreSQL as replica
echo ""
echo -e "${BLUE}Step 6: Starting PostgreSQL as replica...${NC}"
docker compose -f docker-compose-primary.yml up -d postgres-replica

echo ""
echo -e "${YELLOW}Waiting for PostgreSQL to initialize (this may take 1-2 minutes)...${NC}"
sleep 10

# Wait for healthy
for i in {1..30}; do
    if docker ps --format '{{.Names}}\t{{.Status}}' | grep postgres-replica | grep -q "healthy"; then
        echo -e "${GREEN}✓ PostgreSQL replica is healthy${NC}"
        break
    fi
    echo -n "."
    sleep 5
done
echo ""

# Step 7: Verify replication
echo ""
echo -e "${BLUE}Step 7: Verifying replication...${NC}"

# Check if replica is in recovery mode
RECOVERY_STATUS=$(docker exec postgres-replica psql -U postgres -t -c "SELECT pg_is_in_recovery();" 2>/dev/null | xargs || echo "error")

if [ "$RECOVERY_STATUS" = "t" ]; then
    echo -e "${GREEN}✓ PostgreSQL is in recovery mode (replica)${NC}"
    
    # Check replication lag
    LAG=$(docker exec postgres-replica psql -U postgres -t -c \
        "SELECT EXTRACT(EPOCH FROM (now() - pg_last_xact_replay_timestamp()));" 2>/dev/null | xargs || echo "N/A")
    
    if [ "$LAG" != "N/A" ]; then
        echo -e "${GREEN}✓ Replication lag: ${LAG} seconds${NC}"
    fi
else
    echo -e "${RED}✗ PostgreSQL is NOT in recovery mode${NC}"
    echo "Check logs: docker logs postgres-replica"
fi

# Step 8: Summary
echo ""
echo -e "${BLUE}=========================================="
echo "Rebuild Complete"
echo -e "==========================================${NC}"
echo ""
echo -e "${GREEN}✓ Old primary is now configured as replica${NC}"
echo -e "${GREEN}✓ Replicating from: ${NEW_PRIMARY_IP}:${NEW_PRIMARY_PORT}${NC}"
echo ""
echo -e "${YELLOW}Next Steps:${NC}"
echo "  1. Verify replication on new primary:"
echo "     ssh ${NEW_PRIMARY_IP}"
echo "     docker exec postgres-primary psql -U postgres -c \"SELECT client_addr, state FROM pg_stat_replication;\""
echo ""
echo "  2. Start Keycloak replica (if needed):"
echo "     docker compose -f docker-compose-primary.yml up -d keycloak-replica"
echo ""
echo "  3. Monitor replication lag:"
echo "     ./scripts/verify-replication.sh"
echo ""
echo -e "${YELLOW}Backup files created:${NC}"
echo "  - .env.backup-${BACKUP_DATE}"
echo "  - docker-compose-primary.yml.backup-${BACKUP_DATE}"
echo "  - postgres-primary-data-backup-${BACKUP_DATE}.tar.gz"
echo ""
