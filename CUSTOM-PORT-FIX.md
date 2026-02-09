# Quick Fix: Custom PostgreSQL Port Configuration

## Problem

When you change PostgreSQL primary port (e.g., from 5432 to 5434), the replica still tries to connect to port 5432.

## Root Cause

The replica initialization script and docker-compose configuration need to know the primary port for replication connection.

## Solution

### Step 1: Update Primary Server

Edit `.env` on primary server:

```bash
POSTGRES_PRIMARY_PORT=5434
```

Restart primary:

```bash
docker compose -f docker-compose-primary.yml down
docker compose -f docker-compose-primary.yml up -d
```

### Step 2: Update Replica Server

Edit `.env` on replica server and add:

```bash
# Must match primary port
PRIMARY_POSTGRES_PORT=5434
```

### Step 3: Reinitialize Replica

If replica was already initialized with wrong port, you need to reinitialize:

```bash
# Stop replica
docker compose -f docker-compose-replica.yml down

# Remove old data
docker volume rm postgres-replica-data

# Start replica (will reinitialize with correct port)
docker compose -f docker-compose-replica.yml up -d postgres-replica
```

### Step 4: Verify Connection

Check replica logs:

```bash
docker logs postgres-replica
```

You should see:
```
Connecting to primary at postgres-primary:5434
Primary server is ready. Starting base backup...
Base backup completed successfully!
```

Verify replication:

```bash
./scripts/verify-replication.sh
```

## For HAProxy Users

If using HAProxy, also update `.env` on HAProxy server:

```bash
PRIMARY_POSTGRES_PORT=5434
HAPROXY_POSTGRES_PORT=5434
```

Restart HAProxy:

```bash
docker compose -f docker-compose-lb.yml restart haproxy
```

## Environment Variables Summary

### Primary Server (.env)
```bash
POSTGRES_PRIMARY_PORT=5434
```

### Replica Server (.env)
```bash
POSTGRES_REPLICA_PORT=5435
PRIMARY_POSTGRES_PORT=5434  # ← Must match primary!
```

### HAProxy Server (.env)
```bash
HAPROXY_POSTGRES_PORT=5434
PRIMARY_POSTGRES_PORT=5434
REPLICA_POSTGRES_PORT=5435
```

## Verification Checklist

- [ ] Primary PostgreSQL running on custom port
- [ ] Replica `.env` has `PRIMARY_POSTGRES_PORT` set
- [ ] Replica successfully connects to primary
- [ ] Replication is working (check with `verify-replication.sh`)
- [ ] HAProxy can connect to both backends (if using HAProxy)

## Common Mistakes

1. ❌ Forgetting to set `PRIMARY_POSTGRES_PORT` on replica
2. ❌ Port mismatch between primary and replica config
3. ❌ Not reinitializing replica after port change
4. ❌ Firewall blocking the new port

## Need Help?

Check logs:
```bash
# Primary
docker logs postgres-primary

# Replica
docker logs postgres-replica

# HAProxy (if using)
docker logs haproxy-lb
```

Test connectivity:
```bash
# From replica server
telnet ${PRIMARY_SERVER_IP} ${PRIMARY_POSTGRES_PORT}
```
