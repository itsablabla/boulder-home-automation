# Boulder Home Automation - System Architecture

## Overview

This system provides **rate-limit-free home automation** for multi-property deployment with full historical data retention. Built to solve the critical UniFi Protect + Home Assistant rate limiting issue that causes 5-15 minute account lockouts.

## Design Principles

1. **No Authentication Polling** - Use RTSP streams and webhooks instead of frequent API calls
2. **Event-Driven Architecture** - Push events via MQTT, not pull via polling
3. **Unlimited Historical Data** - PostgreSQL with configurable retention (default 365 days)
4. **Replicable Template** - Copy to Boulder #2, Shoulder house, any property
5. **MCP Integration** - HTTP API for GARZA OS control

## System Components

```
┌─────────────────────────────────────────────────────────────────┐
│                     UniFi Protect NVR                           │
│                    (192.168.10.49)                              │
│                                                                  │
│  22 Cameras → RTSP Streams (no auth polling)                   │
│           → Webhooks (push events)                              │
└────────────┬────────────────────────────┬─────────────────────┘
             │                            │
             │                            │
   ┌─────────▼─────────┐       ┌─────────▼──────────┐
   │   Frigate AI      │       │   MQTT Broker      │
   │ Object Detection  │       │   (Mosquitto)      │
   │                   │       │                    │
   │ • Person          │◄──────┤ Message Bus        │
   │ • Car             │       │                    │
   │ • Package         │       │ Topics:            │
   │ • Dog/Cat         │       │ • frigate/events   │
   └─────────┬─────────┘       │ • camera/state     │
             │                 │ • abode/status     │
             │                 │ • automation/*     │
             │                 └──────┬─────────────┘
             │                        │
             │                        │
   ┌─────────▼────────────────────────▼─────────┐
   │           Node-RED                          │
   │     Automation & Orchestration              │
   │                                             │
   │  Flows:                                     │
   │  • Process Frigate detections               │
   │  • Log all events to PostgreSQL             │
   │  • Integrate Abode alarm                    │
   │  • Expose HTTP API for MCP                  │
   │  • Trigger automations                      │
   │                                             │
   │  API Endpoints:                             │
   │  • GET  /api/camera/snapshot                │
   │  • POST /api/automation/trigger             │
   │  • GET  /api/events/history                 │
   │  • GET  /api/abode/status                   │
   └─────────┬───────────────────────────────────┘
             │
             │
   ┌─────────▼─────────┐       ┌──────────────────┐
   │   PostgreSQL      │       │   GARZA OS       │
   │  Historical Data  │       │   MCP Server     │
   │                   │       │                  │
   │ Tables:           │       │ Calls API:       │
   │ • events          │       │ http://mac:1880  │
   │ • frigate_detect  │       │                  │
   │ • camera_state    │       │ "Show me front   │
   │ • abode_state     │       │  door snapshot"  │
   │ • automation_exec │       │                  │
   │                   │       │ "Set alarm to    │
   │ Retention:        │       │  away mode"      │
   │ • Events: 365d    │       │                  │
   │ • Detections: 90d │       └──────────────────┘
   └───────────────────┘
```

## Data Flow

### 1. Camera Motion Detection

```
Camera Movement
    ↓
UniFi Protect RTSP Stream
    ↓
Frigate AI Detection (CPU/GPU)
    ↓
MQTT Publish: frigate/events
    ↓
Node-RED Processing
    ↓
├─ Log to PostgreSQL
├─ Trigger Automation (if high confidence)
└─ Send notification (optional)
```

### 2. Manual API Request (via MCP)

```
Claude (GARZA OS)
    ↓
HTTP POST http://192.168.10.x:1880/api/camera/snapshot?camera_id=front_door
    ↓
Node-RED Flow
    ↓
Fetch from Frigate: http://frigate:5000/api/front_door/latest.jpg
    ↓
Return image to Claude
```

### 3. Alarm State Change

```
Abode Alarm Mode Change
    ↓
GARZA Home MCP polls status (every 5 min)
    ↓
Publish to MQTT: abode/status
    ↓
Node-RED receives event
    ↓
├─ Log to PostgreSQL
├─ Update camera recording settings
└─ Adjust automation rules
```

## Network Architecture

### Container Network

All services run on Docker bridge network `home-automation`:

```
mosquitto:1883      → MQTT broker
node-red:1880       → Automation engine + API
frigate:5000        → AI detection UI
frigate:8554        → RTSP restreaming
postgres:5432       → Database
nginx:8080          → Reverse proxy (optional)
```

### External Access

**Local Network:**
- Direct access to all services via `192.168.10.x` IP

**Remote Access (via Cloudflare Tunnel):**
```
Internet → Cloudflare Tunnel → nginx:80 → Services
```

## Storage Architecture

### Volume Mounts

```
./mosquitto/config  → /mosquitto/config   (MQTT broker config)
./mosquitto/data    → /mosquitto/data     (MQTT persistence)
./mosquitto/log     → /mosquitto/log      (MQTT logs)

./node-red/data     → /data               (Node-RED flows, credentials)

./frigate/config.yml → /config/config.yml (Frigate config)
./frigate/storage   → /media/frigate      (Recordings, snapshots, DB)

./postgres/data     → /var/lib/postgresql/data  (Database files)
./postgres/init.sql → /docker-entrypoint-initdb.d/init.sql
```

### Storage Requirements

**Minimum (7 day video retention):**
- Frigate recordings: ~500GB (22 cameras × 3GB/day × 7 days)
- Frigate snapshots: ~10GB
- PostgreSQL: ~5GB (365 days events)
- Node-RED: ~1GB
- Mosquitto: ~500MB
- **Total: ~520GB**

**Recommended (30 day retention):**
- Frigate recordings: ~2TB
- Total: ~2.5TB

**Boulder Mac Mini Available:** 304GB (need external storage for recordings)

## Security Model

### Authentication Layers

1. **MQTT Broker** - Username/password authentication
2. **Node-RED Admin** - Password-protected web interface
3. **PostgreSQL** - Database credentials
4. **Frigate** - Local network only (no external exposure)
5. **UniFi Protect** - RTSP stream access (no polling = no rate limits)

### Network Security

- All services isolated in Docker network
- No external ports exposed (except via Cloudflare Tunnel)
- RTSP streams use internal network only
- API endpoints require authentication (configure in Node-RED)

### Data Security

- Environment variables in `.env` (git-ignored)
- PostgreSQL credentials separate from application
- MQTT credentials separate per service
- No credentials in code or configs

## Scaling Strategy

### Vertical Scaling (Single Property)

- Add more cameras → Update Frigate config
- More automations → Add Node-RED flows
- More historical data → Increase PostgreSQL retention

### Horizontal Scaling (Multiple Properties)

**Template Deployment:**

```bash
# Property 1: Boulder House
cd boulder-home-automation/
docker-compose up -d

# Property 2: Boulder #2
cp -r boulder-home-automation/ boulder2-home-automation/
cd boulder2-home-automation/
nano .env  # Update IPs, credentials
docker-compose up -d

# Property 3: Shoulder House
cp -r boulder-home-automation/ shoulder-home-automation/
cd shoulder-home-automation/
nano .env  # Update IPs, credentials
docker-compose up -d
```

**Central Monitoring (Future):**

```
┌─────────────────────────────────────────────┐
│         GARZA OS Central Dashboard          │
│                                              │
│  ┌─────────────┐  ┌─────────────┐          │
│  │  Boulder 1  │  │  Boulder 2  │  ...     │
│  │  22 cams    │  │  18 cams    │          │
│  │  http://IP1 │  │  http://IP2 │          │
│  └─────────────┘  └─────────────┘          │
└─────────────────────────────────────────────┘
```

## Performance Characteristics

### Resource Usage (per property)

**CPU:**
- Frigate AI detection: 2-4 cores (or 1 Coral TPU)
- Node-RED: <0.5 core
- PostgreSQL: <0.5 core
- Mosquitto: <0.2 core
- **Total: 3-5 cores**

**RAM:**
- Frigate: 2-4GB
- Node-RED: 512MB
- PostgreSQL: 1-2GB
- Mosquitto: 256MB
- **Total: 4-7GB**

**Disk I/O:**
- Frigate: High (continuous recording)
- PostgreSQL: Medium (frequent inserts)
- Node-RED: Low
- Mosquitto: Low

### Network Usage

- RTSP streams: ~50Mbps (22 cameras × 2-3Mbps each)
- MQTT: <1Mbps
- API calls: <1Mbps
- **Total: ~50Mbps local network**

## Maintenance

### Daily Tasks (Automated)

- PostgreSQL retention cleanup (cleanup_old_data() function)
- MQTT log rotation
- Frigate recording cleanup

### Weekly Tasks

- Review Frigate detection accuracy
- Check disk space usage
- Review automation logs

### Monthly Tasks

- PostgreSQL vacuum analyze (automated)
- Review retention policies
- Update Docker images

## Monitoring & Alerting

### Health Checks

```bash
# All services status
docker-compose ps

# Individual service logs
docker-compose logs -f frigate
docker-compose logs -f node-red
docker-compose logs -f postgres

# Database health
docker-compose exec postgres psql -U homeautomation -c "SELECT COUNT(*) FROM events;"

# MQTT broker status
mosquitto_sub -h localhost -p 1883 -u user -P pass -t '$SYS/#'
```

### Metrics to Monitor

- Frigate detection rate (events/hour)
- PostgreSQL database size (GB)
- Disk space available (GB)
- MQTT message rate (messages/min)
- Node-RED flow execution time (ms)

## Disaster Recovery

### Backup Strategy

**What to Backup:**
1. `.env` file (credentials)
2. `node-red/data/` (flows, credentials)
3. `postgres/data/` (historical database)
4. `frigate/config.yml` (camera configs)

**Backup Schedule:**
- Daily: PostgreSQL database
- Weekly: Node-RED flows
- Monthly: Full system backup

**Recovery Time:**
- Fresh install: ~30 minutes
- Restore from backup: ~1 hour
- Full rebuild: ~3 hours

## Future Enhancements

1. **Coral TPU** - Hardware accelerated AI detection (10x faster)
2. **HA Clustering** - Multi-node Node-RED for redundancy
3. **Time-series DB** - InfluxDB for metrics and grafana dashboards
4. **Voice Control** - Integrate with voice assistants
5. **Mobile App** - Custom mobile interface
6. **Multi-Property Dashboard** - Centralized monitoring