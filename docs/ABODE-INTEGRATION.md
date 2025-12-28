# Abode Alarm Integration Guide

## Overview

This integration connects your Abode security system with the Boulder Home Automation stack via **GARZA Home MCP** and **MQTT**.

## Architecture

```
Abode Cloud API
    │
    ▼
GARZA Home MCP (polling every 5 min)
    │
    ▼
MQTT Broker (mosquitto)
    │
    ▼
Node-RED (automation logic)
    │
    ├─► PostgreSQL (state history)
    └─► Automations (trigger on alarm state)
```

## Integration Method

### Via GARZA Home MCP

The GARZA Home MCP already has Abode integration built-in. Instead of direct API calls from Node-RED, we use the existing MCP as a bridge.

**Workflow:**

1. GARZA Home MCP polls Abode every 5 minutes
2. On state change, publishes to MQTT: `abode/status`
3. Node-RED subscribes to `abode/status`
4. Node-RED processes state changes and triggers automations

## MQTT Topics

### Status Updates (Published by MCP)

**Topic:** `abode/status`

**Payload:**
```json
{
  "mode": "home",
  "armed": true,
  "changed_at": "2025-12-28T12:00:00Z",
  "devices": [
    {
      "id": "door-sensor-1",
      "name": "Front Door",
      "type": "door",
      "state": "closed"
    },
    {
      "id": "motion-sensor-1", 
      "name": "Living Room",
      "type": "motion",
      "state": "idle"
    }
  ]
}
```

**Modes:**
- `standby` - Disarmed
- `home` - Home mode (perimeter sensors only)
- `away` - Away mode (all sensors armed)

### Mode Changes (Published by Node-RED)

**Topic:** `abode/set_mode`

**Payload:**
```json
{
  "mode": "away",
  "requested_by": "automation",
  "requested_at": "2025-12-28T12:00:00Z"
}
```

## Node-RED Flows

### Subscribe to Abode Status

```json
[
  {
    "id": "abode-status-sub",
    "type": "mqtt in",
    "name": "Abode Status Updates",
    "topic": "abode/status",
    "qos": "2",
    "datatype": "json",
    "broker": "mqtt-broker",
    "wires": [["process-abode-status"]]
  },
  {
    "id": "process-abode-status",
    "type": "function",
    "name": "Process Status",
    "func": "const status = msg.payload;\n\n// Log to PostgreSQL\nmsg.topic = `\n  INSERT INTO abode_state (mode, devices, metadata)\n  VALUES ($1, $2, $3)\n`;\n\nmsg.params = [\n  status.mode,\n  JSON.stringify(status.devices),\n  JSON.stringify({changed_at: status.changed_at})\n];\n\nreturn msg;",
    "wires": [["postgres-log"]]
  }
]
```

### Publish Mode Change Request

```json
[
  {
    "id": "set-away-mode",
    "type": "inject",
    "name": "Set Away Mode",
    "props": [],
    "topic": "abode/set_mode",
    "payload": "{\"mode\":\"away\",\"requested_by\":\"manual\"}",
    "payloadType": "json",
    "wires": [["mqtt-publish"]]
  }
]
```

### Automation: Away Mode on Door Lock

```json
[
  {
    "id": "door-locked",
    "type": "mqtt in",
    "name": "Front Door Locked",
    "topic": "abode/devices/door-sensor-1/locked",
    "wires": [["check-time"]]
  },
  {
    "id": "check-time",
    "type": "function",
    "name": "Check Time of Day",
    "func": "const hour = new Date().getHours();\n\n// Only set away mode between 8 AM and 10 PM\nif (hour >= 8 && hour <= 22) {\n  msg.payload = {\n    mode: 'away',\n    requested_by: 'door_lock_automation'\n  };\n  msg.topic = 'abode/set_mode';\n  return msg;\n}\nreturn null;",
    "wires": [["mqtt-publish"]]
  }
]
```

## API Integration

### Node-RED HTTP Endpoints

**Get Abode Status:**
```javascript
// GET /api/abode/status
[
  {
    "id": "api-abode-status",
    "type": "http in",
    "url": "/abode/status",
    "method": "get",
    "wires": [["query-latest-status"]]
  },
  {
    "id": "query-latest-status",
    "type": "function",
    "name": "Get Latest Status",
    "func": "// Query PostgreSQL for latest status\nmsg.topic = `\n  SELECT mode, devices, metadata, timestamp\n  FROM abode_state\n  ORDER BY timestamp DESC\n  LIMIT 1\n`;\nreturn msg;",
    "wires": [["postgres-query"]]
  },
  {
    "id": "postgres-query",
    "type": "postgres",
    "name": "Query DB",
    "wires": [["format-response"]]
  },
  {
    "id": "format-response",
    "type": "function",
    "name": "Format Response",
    "func": "const data = msg.payload[0];\nmsg.payload = {\n  mode: data.mode,\n  armed: data.mode !== 'standby',\n  devices: data.devices,\n  updated_at: data.timestamp\n};\nreturn msg;",
    "wires": [["http-response"]]
  }
]
```

**Set Abode Mode:**
```javascript
// POST /api/abode/set_mode
[
  {
    "id": "api-set-mode",
    "type": "http in",
    "url": "/abode/set_mode",
    "method": "post",
    "wires": [["validate-mode"]]
  },
  {
    "id": "validate-mode",
    "type": "function",
    "name": "Validate Mode",
    "func": "const validModes = ['standby', 'home', 'away'];\nconst mode = msg.payload.mode;\n\nif (!validModes.includes(mode)) {\n  msg.statusCode = 400;\n  msg.payload = {error: 'Invalid mode'};\n  return [null, msg];\n}\n\nmsg.payload = {\n  mode: mode,\n  requested_by: 'api',\n  requested_at: new Date().toISOString()\n};\nmsg.topic = 'abode/set_mode';\nreturn [msg, null];",
    "outputs": 2,
    "wires": [["mqtt-publish"], ["error-response"]]
  }
]
```

## GARZA Home MCP Integration

The MCP needs to:

1. Poll Abode API every 5 minutes
2. Publish status changes to MQTT
3. Listen for mode change requests on MQTT
4. Execute mode changes via Abode API

### MCP Flow Example

```javascript
// In GARZA Home MCP

// Poll Abode every 5 minutes
setInterval(async () => {
  const status = await abode.getStatus();
  
  // Publish to MQTT
  await mqtt.publish('abode/status', JSON.stringify({
    mode: status.mode,
    armed: status.mode !== 'standby',
    changed_at: new Date().toISOString(),
    devices: status.devices
  }));
}, 5 * 60 * 1000);

// Listen for mode change requests
mqtt.subscribe('abode/set_mode', async (message) => {
  const { mode } = JSON.parse(message);
  
  // Execute via Abode API
  await abode.setMode(mode);
  
  // Publish updated status
  const status = await abode.getStatus();
  await mqtt.publish('abode/status', JSON.stringify(status));
});
```

## Automations

### Example: Set Away Mode When Leaving

**Trigger:** All family members leave (detected via UniFi presence)

```javascript
{
  "id": "everyone-left",
  "type": "function",
  "name": "Check All Gone",
  "func": "// Check if all phones disconnected from WiFi\nconst devices = flow.get('known_devices') || [];\nconst connected = devices.filter(d => d.connected);\n\nif (connected.length === 0) {\n  msg.payload = {\n    mode: 'away',\n    requested_by: 'presence_automation'\n  };\n  msg.topic = 'abode/set_mode';\n  return msg;\n}\nreturn null;"
}
```

### Example: Set Home Mode When Arriving

**Trigger:** Any family member arrives (UniFi presence)

```javascript
{
  "id": "someone-arrived",
  "type": "function",
  "name": "Check Arrival",
  "func": "const device = msg.payload;\n\nif (device.connected && device.is_family) {\n  msg.payload = {\n    mode: 'home',\n    requested_by: 'presence_automation'\n  };\n  msg.topic = 'abode/set_mode';\n  return msg;\n}\nreturn null;"
}
```

### Example: Notify on Door Open While Armed

**Trigger:** Door sensor opens while system is armed

```javascript
{
  "id": "door-alert",
  "type": "function",
  "name": "Check Armed State",
  "func": "const device = msg.payload;\nconst mode = flow.get('abode_mode') || 'standby';\n\nif (device.type === 'door' && \n    device.state === 'open' && \n    mode === 'away') {\n  msg.payload = {\n    alert: 'Door opened while armed!',\n    device: device.name,\n    mode: mode,\n    timestamp: new Date().toISOString()\n  };\n  return msg;\n}\nreturn null;"
}
```

## Security Considerations

### Credentials

```bash
# Store in .env
ABODE_USERNAME=your-email@example.com
ABODE_PASSWORD=your-secure-password

# GARZA Home MCP will use these to authenticate
```

### MQTT Security

- Use authentication on MQTT broker
- Encrypt messages if needed (not required on local network)
- Use TLS for remote access

### Rate Limiting

- Abode API has rate limits
- Polling every 5 minutes is safe
- Don't poll more frequently than every 1 minute

## Monitoring

### PostgreSQL Queries

**Recent mode changes:**
```sql
SELECT mode, timestamp 
FROM abode_state 
ORDER BY timestamp DESC 
LIMIT 10;
```

**Time in each mode (last 30 days):**
```sql
SELECT 
  mode,
  SUM(
    EXTRACT(EPOCH FROM (
      LEAD(timestamp) OVER (ORDER BY timestamp) - timestamp
    ))
  ) / 3600 as hours
FROM abode_state
WHERE timestamp > NOW() - INTERVAL '30 days'
GROUP BY mode;
```

**Device activity:**
```sql
SELECT 
  devices->>'name' as device_name,
  devices->>'state' as state,
  COUNT(*) as changes
FROM abode_state, 
     jsonb_array_elements(devices) as devices
WHERE timestamp > NOW() - INTERVAL '7 days'
GROUP BY device_name, state
ORDER BY changes DESC;
```

## Troubleshooting

### Status Not Updating

```bash
# Check GARZA Home MCP logs
docker logs -f garza-home-mcp

# Check MQTT messages
mosquitto_sub -h localhost -p 1883 -u user -P pass -t 'abode/#' -v

# Check Node-RED debug
# Open Node-RED UI, check debug panel
```

### Mode Changes Not Working

```bash
# Test MQTT publish manually
mosquitto_pub -h localhost -p 1883 -u user -P pass \
  -t 'abode/set_mode' \
  -m '{"mode":"away","requested_by":"test"}'

# Check Abode API directly (via GARZA Home MCP)
# Call MCP tool to verify Abode is reachable
```

### Authentication Errors

- Verify Abode credentials in `.env`
- Check if Abode account is locked (too many login attempts)
- Verify MCP has valid session token

## Next Steps

1. ✅ Configure Abode credentials in GARZA Home MCP
2. ✅ Set up MQTT publishing in MCP
3. ✅ Create Node-RED flows for status processing
4. ✅ Set up automations (presence-based, time-based, etc.)
5. ✅ Test mode changes via API
6. ✅ Monitor status changes in PostgreSQL