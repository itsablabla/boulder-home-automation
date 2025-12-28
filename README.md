# Boulder Home Automation

**Node-RED + MQTT home automation stack - no rate limits, full history, replicable across properties**

## 🎯 Why This Approach?

Home Assistant + UniFi Protect has **severe rate limit issues**:
- UniFi Protect enforces strict login attempt limits
- Home Assistant polls frequently for camera updates  
- Result: **Account lockout for 5-15 minutes** blocking access to your own cameras

This stack **eliminates rate limits entirely** by using:
- ✅ **RTSP streams** from UniFi Protect (no auth polling)
- ✅ **Webhooks** for event notifications (push, not pull)
- ✅ **API keys** instead of username/password auth where needed

## 📦 Stack Components

```
UniFi Protect (192.168.10.49)
    │
    ├─ RTSP streams → Frigate (AI object detection)
    │
    └─ Webhooks → MQTT → Node-RED
                           │
                           ├─ Abode alarm integration
                           ├─ PostgreSQL logging (unlimited retention)
                           └─ HTTP API for GARZA OS MCP
```

**Services:**
- **Mosquitto** - MQTT message broker
- **Node-RED** - Visual automation flows & orchestration
- **Frigate** - AI object detection (person/car/package detection on camera streams)
- **PostgreSQL** - Historical data storage with custom retention
- **Nginx** (optional) - Reverse proxy for external access

## ✨ Features

✅ **Zero Rate Limits** - RTSP + webhooks, no auth polling  
✅ **Full History** - PostgreSQL with configurable retention (365+ days)  
✅ **Replicable** - Docker Compose, copy to Boulder #2, Shoulder house, etc.  
✅ **MCP Integration** - Node-RED exposes HTTP endpoints for GARZA OS  
✅ **AI Detection** - Frigate identifies people, cars, packages on camera feeds  

## 🚀 Quick Start

### Prerequisites
- Boulder Mac Mini (192.168.10.x)
- Docker & Docker Compose installed
- UniFi Protect NVR at 192.168.10.49
- 22 cameras configured in UniFi Protect

### Installation

```bash
# Clone the repo
git clone https://github.com/itsablabla/boulder-home-automation.git
cd boulder-home-automation

# Copy environment template
cp .env.example .env

# Edit .env with your credentials
nano .env

# Start the stack
docker-compose up -d

# Check logs
docker-compose logs -f
```

### Access URLs

- **Node-RED**: http://localhost:1880
- **Frigate**: http://localhost:5000
- **MQTT**: localhost:1883

## 📁 Directory Structure

```
boulder-home-automation/
├── docker-compose.yml          # Main stack definition
├── .env.example                # Environment template
├── mosquitto/
│   └── config/
│       └── mosquitto.conf      # MQTT broker config
├── node-red/
│   ├── flows/                  # Automation flows
│   └── settings.js             # Node-RED config
├── frigate/
│   └── config.yml              # AI detection config
├── postgres/
│   └── init.sql                # Database initialization
└── docs/
    ├── ARCHITECTURE.md         # Detailed architecture
    ├── UNIFI-INTEGRATION.md    # UniFi Protect setup
    ├── ABODE-INTEGRATION.md    # Abode alarm setup
    └── MCP-INTEGRATION.md      # GARZA OS MCP setup
```

## 🔧 Configuration

### UniFi Protect RTSP Streams

Each camera exposes 3 RTSP streams:
```
rtsp://192.168.10.49:7447/[camera-id]?enableSrtp       # High quality
rtsp://192.168.10.49:7447/[camera-id]_sub?enableSrtp   # Medium quality
rtsp://192.168.10.49:7447/[camera-id]_low?enableSrtp   # Low quality (recording)
```

No authentication polling = no rate limits.

### Frigate AI Detection

Frigate analyzes RTSP streams for:
- **People** - Person detection with zones
- **Vehicles** - Car detection for driveway
- **Packages** - Package delivery detection
- **Animals** - Pet detection (optional)

### Historical Data Retention

PostgreSQL stores:
- All MQTT messages (events, state changes)
- Frigate detection events
- Node-RED flow execution logs
- Abode alarm state changes

**Default retention:** 365 days (configurable in `postgres/init.sql`)

## 🏠 Multi-Property Deployment

**Replicable template design:**

```bash
# Copy stack to new property
cp -r boulder-home-automation/ boulder2-home-automation/
cd boulder2-home-automation/

# Update .env for new property
nano .env  # Change IPs, credentials, etc.

# Deploy
docker-compose up -d
```

Each property gets its own isolated stack with identical capabilities.

## 🔗 GARZA OS Integration

Node-RED exposes HTTP endpoints for MCP tools:

```javascript
// Example: Get camera snapshot
POST http://localhost:1880/api/camera/snapshot
{
  "camera_id": "front-door"
}

// Example: Trigger automation
POST http://localhost:1880/api/automation/trigger
{
  "automation": "away-mode"
}
```

Full API docs: [docs/MCP-INTEGRATION.md](docs/MCP-INTEGRATION.md)

## 🛡️ Security

- MQTT uses authentication (username/password in `.env`)
- Node-RED admin interface password-protected
- Frigate web UI accessible only on local network
- PostgreSQL credentials isolated in `.env`
- No external ports exposed (use Cloudflare Tunnel for remote access)

## 📊 Monitoring

**Health checks:**
```bash
# Check all services
docker-compose ps

# View logs
docker-compose logs -f node-red
docker-compose logs -f frigate
docker-compose logs -f mosquitto

# PostgreSQL stats
docker-compose exec postgres psql -U homeautomation -c "SELECT COUNT(*) FROM events;"
```

## 🐛 Troubleshooting

### RTSP Stream Issues
```bash
# Test RTSP stream directly
ffplay rtsp://192.168.10.49:7447/[camera-id]
```

### MQTT Connection Issues
```bash
# Test MQTT broker
mosquitto_sub -h localhost -p 1883 -u [username] -P [password] -t '#'
```

### Frigate Not Detecting
- Check camera in Frigate UI (http://localhost:5000)
- Verify RTSP stream quality
- Adjust detection zones in `frigate/config.yml`

## 📝 License

MIT

## 🙏 Credits

Built as part of **GARZA OS** - unified intelligence platform integrating home automation, messaging, knowledge management, and infrastructure control.

---

**Repository:** https://github.com/itsablabla/boulder-home-automation  
**Issues:** https://github.com/itsablabla/boulder-home-automation/issues