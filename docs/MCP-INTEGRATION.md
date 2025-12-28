# GARZA OS MCP Integration Guide

## Overview

This document explains how to integrate the Boulder Home Automation stack with **GARZA OS** via **Model Context Protocol (MCP)** HTTP endpoints exposed by Node-RED.

## Architecture

```
┌──────────────────────────────────────────────────────────┐
│                      GARZA OS                             │
│                  (Claude + MCP)                           │
└─────────────────────┬────────────────────────────────────┘
                      │
                      │ HTTP API Calls
                      │
┌─────────────────────▼────────────────────────────────────┐
│                   Node-RED                                │
│              (192.168.10.x:1880)                         │
│                                                           │
│  HTTP Endpoints:                                         │
│  • GET  /api/camera/snapshot?camera_id=front_door        │
│  • POST /api/automation/trigger                          │
│  • GET  /api/events/history?hours=24                     │
│  • GET  /api/abode/status                                │
│  • POST /api/abode/set_mode                              │
│  • GET  /api/camera/list                                 │
│  • GET  /api/detection/recent?limit=10                   │
└───────────────────────────────────────────────────────────┘
```

## API Endpoints

### 1. Get Camera Snapshot

**Endpoint:** `GET /api/camera/snapshot`

**Query Parameters:**
- `camera_id` (required) - Camera name from Frigate config

**Example:**
```bash
curl "http://192.168.10.x:1880/api/camera/snapshot?camera_id=front_door"
```

**Response:**
- Content-Type: `image/jpeg`
- Body: JPEG image data

**GARZA Home MCP Tool:**
```javascript
// Add to GARZA Home MCP
{
  name: "get_camera_snapshot",
  description: "Get current snapshot from a camera",
  parameters: {
    camera_id: {
      type: "string",
      description: "Camera ID (front_door, back_door, etc.)",
      required: true
    }
  },
  handler: async ({ camera_id }) => {
    const response = await fetch(
      `http://192.168.10.x:1880/api/camera/snapshot?camera_id=${camera_id}`
    );
    const imageBuffer = await response.arrayBuffer();
    return {
      image: Buffer.from(imageBuffer).toString('base64'),
      camera_id
    };
  }
}
```

### 2. Trigger Automation

**Endpoint:** `POST /api/automation/trigger`

**Request Body:**
```json
{
  "automation": "away_mode",
  "parameters": {
    "delay": 60
  }
}
```

**Response:**
```json
{
  "success": true,
  "automation": "away_mode",
  "triggered_at": "2025-12-28T12:00:00Z"
}
```

**Example:**
```bash
curl -X POST http://192.168.10.x:1880/api/automation/trigger \
  -H "Content-Type: application/json" \
  -d '{"automation": "away_mode"}'
```

**GARZA Home MCP Tool:**
```javascript
{
  name: "trigger_automation",
  description: "Trigger a home automation",
  parameters: {
    automation: {
      type: "string",
      enum: ["away_mode", "home_mode", "night_mode", "guest_mode"],
      required: true
    }
  },
  handler: async ({ automation }) => {
    const response = await fetch(
      `http://192.168.10.x:1880/api/automation/trigger`,
      {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ automation })
      }
    );
    return await response.json();
  }
}
```

### 3. Get Event History

**Endpoint:** `GET /api/events/history`

**Query Parameters:**
- `hours` (optional, default: 24) - Hours of history to retrieve
- `event_type` (optional) - Filter by event type
- `camera` (optional) - Filter by camera name

**Example:**
```bash
curl "http://192.168.10.x:1880/api/events/history?hours=6&event_type=person&camera=front_door"
```

**Response:**
```json
{
  "events": [
    {
      "timestamp": "2025-12-28T11:45:00Z",
      "camera": "front_door",
      "object": "person",
      "confidence": 0.92,
      "zone": "entrance",
      "snapshot_url": "http://frigate:5000/api/events/abc123/snapshot.jpg"
    }
  ],
  "total": 1,
  "hours": 6
}
```

### 4. Get Abode Alarm Status

**Endpoint:** `GET /api/abode/status`

**Response:**
```json
{
  "mode": "home",
  "armed": true,
  "devices": [
    {
      "id": "door-sensor-1",
      "name": "Front Door",
      "type": "door",
      "state": "closed"
    }
  ],
  "updated_at": "2025-12-28T12:00:00Z"
}
```

**Example:**
```bash
curl "http://192.168.10.x:1880/api/abode/status"
```

### 5. Set Abode Alarm Mode

**Endpoint:** `POST /api/abode/set_mode`

**Request Body:**
```json
{
  "mode": "away"
}
```

**Valid Modes:**
- `standby` - Disarmed
- `home` - Home mode (perimeter only)
- `away` - Away mode (full alarm)

**Response:**
```json
{
  "success": true,
  "mode": "away",
  "changed_at": "2025-12-28T12:00:00Z"
}
```

### 6. List Cameras

**Endpoint:** `GET /api/camera/list`

**Response:**
```json
{
  "cameras": [
    {
      "id": "front_door",
      "name": "Front Door",
      "status": "online",
      "last_motion": "2025-12-28T11:45:00Z"
    },
    {
      "id": "back_door",
      "name": "Back Door",
      "status": "online",
      "last_motion": "2025-12-28T10:30:00Z"
    }
  ],
  "total": 22
}
```

### 7. Get Recent Detections

**Endpoint:** `GET /api/detection/recent`

**Query Parameters:**
- `limit` (optional, default: 10) - Number of detections to return
- `object_type` (optional) - Filter by object (person, car, package, etc.)

**Response:**
```json
{
  "detections": [
    {
      "timestamp": "2025-12-28T11:45:00Z",
      "camera": "front_door",
      "object": "person",
      "confidence": 0.92,
      "zone": "entrance"
    }
  ],
  "total": 1
}
```

## Node-RED Implementation

### Example Flow: Camera Snapshot

```json
[
  {
    "id": "api-snapshot",
    "type": "http in",
    "name": "GET /api/camera/snapshot",
    "url": "/camera/snapshot",
    "method": "get",
    "wires": [["validate-camera-id"]]
  },
  {
    "id": "validate-camera-id",
    "type": "function",
    "name": "Validate Camera ID",
    "func": "const cameraId = msg.req.query.camera_id;\n\nif (!cameraId) {\n  msg.statusCode = 400;\n  msg.payload = {error: 'camera_id required'};\n  return [null, msg];\n}\n\nmsg.cameraId = cameraId;\nreturn [msg, null];",
    "outputs": 2,
    "wires": [["fetch-snapshot"], ["error-response"]]
  },
  {
    "id": "fetch-snapshot",
    "type": "http request",
    "name": "Get from Frigate",
    "method": "GET",
    "ret": "bin",
    "url": "http://frigate:5000/api/{{cameraId}}/latest.jpg",
    "wires": [["return-image"]]
  },
  {
    "id": "return-image",
    "type": "function",
    "name": "Set Headers",
    "func": "msg.headers = {'Content-Type': 'image/jpeg'};\nreturn msg;",
    "wires": [["image-response"]]
  },
  {
    "id": "image-response",
    "type": "http response",
    "name": "Return Image"
  },
  {
    "id": "error-response",
    "type": "http response",
    "name": "Return Error"
  }
]
```

## GARZA Home MCP Integration

### Add New MCP Server

**File:** `garza-home-mcp/src/boulder-home.js`

```javascript
import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";

const BOULDER_API = "http://192.168.10.x:1880/api";

// Tool: Get Camera Snapshot
server.addTool({
  name: "boulder_get_snapshot",
  description: "Get current snapshot from Boulder house camera",
  parameters: {
    camera_id: {
      type: "string",
      description: "Camera ID (front_door, back_door, driveway, etc.)",
      required: true
    }
  },
  handler: async ({ camera_id }) => {
    const response = await fetch(
      `${BOULDER_API}/camera/snapshot?camera_id=${camera_id}`
    );
    
    if (!response.ok) {
      throw new Error(`Failed to get snapshot: ${response.statusText}`);
    }
    
    const imageBuffer = await response.arrayBuffer();
    return {
      content: [{
        type: "image",
        data: Buffer.from(imageBuffer).toString('base64'),
        mimeType: "image/jpeg"
      }],
      isError: false
    };
  }
});

// Tool: Trigger Automation
server.addTool({
  name: "boulder_trigger_automation",
  description: "Trigger Boulder house automation",
  parameters: {
    automation: {
      type: "string",
      enum: ["away_mode", "home_mode", "night_mode", "guest_mode"],
      required: true
    }
  },
  handler: async ({ automation }) => {
    const response = await fetch(`${BOULDER_API}/automation/trigger`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ automation })
    });
    
    const result = await response.json();
    return {
      content: [{
        type: "text",
        text: JSON.stringify(result, null, 2)
      }],
      isError: false
    };
  }
});

// Tool: Get Recent Events
server.addTool({
  name: "boulder_get_events",
  description: "Get recent detection events from Boulder house",
  parameters: {
    hours: {
      type: "number",
      description: "Hours of history (default 24)",
      required: false
    },
    camera: {
      type: "string",
      description: "Filter by camera ID",
      required: false
    }
  },
  handler: async ({ hours = 24, camera }) => {
    let url = `${BOULDER_API}/events/history?hours=${hours}`;
    if (camera) url += `&camera=${camera}`;
    
    const response = await fetch(url);
    const data = await response.json();
    
    return {
      content: [{
        type: "text",
        text: JSON.stringify(data, null, 2)
      }],
      isError: false
    };
  }
});

// Tool: Abode Status
server.addTool({
  name: "boulder_abode_status",
  description: "Get Boulder house Abode alarm status",
  handler: async () => {
    const response = await fetch(`${BOULDER_API}/abode/status`);
    const data = await response.json();
    
    return {
      content: [{
        type: "text",
        text: JSON.stringify(data, null, 2)
      }],
      isError: false
    };
  }
});

// Tool: Set Abode Mode
server.addTool({
  name: "boulder_abode_set_mode",
  description: "Set Boulder house Abode alarm mode",
  parameters: {
    mode: {
      type: "string",
      enum: ["standby", "home", "away"],
      required: true
    }
  },
  handler: async ({ mode }) => {
    const response = await fetch(`${BOULDER_API}/abode/set_mode`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ mode })
    });
    
    const result = await response.json();
    return {
      content: [{
        type: "text",
        text: JSON.stringify(result, null, 2)
      }],
      isError: false
    };
  }
});
```

## Example Claude Interactions

### Get Camera Snapshot

**User:** "Show me what's at the front door"

**Claude:** *calls boulder_get_snapshot with camera_id="front_door"*

**Result:** Image of front door displayed

### Check Recent Activity

**User:** "Any deliveries in the last 6 hours?"

**Claude:** *calls boulder_get_events with hours=6, filters for package detections*

**Response:** "Yes, a package was detected at the front door at 2:34 PM with 94% confidence."

### Set Alarm Mode

**User:** "Set the house to away mode"

**Claude:** *calls boulder_abode_set_mode with mode="away"*

**Response:** "Alarm set to away mode. All sensors armed."

## Security

### API Authentication (Optional)

Add authentication to Node-RED HTTP endpoints:

```javascript
// In Node-RED settings.js
httpNodeAuth: {
  user: process.env.API_USER,
  pass: process.env.API_PASSWORD
}

// Then in MCP tool calls
const response = await fetch(url, {
  headers: {
    'Authorization': `Basic ${Buffer.from('user:pass').toString('base64')}`
  }
});
```

### Network Security

- API accessible only on local network (192.168.10.x)
- Use Cloudflare Tunnel for remote access
- Rate limiting in Node-RED (optional)

## Testing

```bash
# Test all endpoints
curl http://192.168.10.x:1880/api/camera/list
curl http://192.168.10.x:1880/api/camera/snapshot?camera_id=front_door > test.jpg
curl http://192.168.10.x:1880/api/events/history?hours=1
curl http://192.168.10.x:1880/api/abode/status

curl -X POST http://192.168.10.x:1880/api/automation/trigger \
  -H "Content-Type: application/json" \
  -d '{"automation": "away_mode"}'
```

## Next Steps

1. ✅ Deploy Node-RED with API endpoints
2. ✅ Add Boulder Home integration to GARZA Home MCP
3. ✅ Test all API endpoints
4. ✅ Configure authentication (optional)
5. ✅ Set up Cloudflare Tunnel for remote access
6. ✅ Add error handling and logging