# UniFi Protect Integration Guide

## Why This Integration Works (No Rate Limits)

Traditional Home Assistant integration **polls UniFi Protect API** every few seconds using username/password authentication. UniFi Protect enforces strict login attempt limits, causing:

❌ **AUTHENTICATION_FAILED_LIMIT_REACHED** (HTTP 429)  
❌ **5-15 minute account lockouts**  
❌ **Blocked access to your own cameras**

This integration uses **RTSP streams and webhooks instead**, eliminating authentication polling entirely.

## Integration Methods

### 1. RTSP Streams (Primary Method)

**How It Works:**
- UniFi Protect exposes RTSP streams for each camera
- Frigate connects directly to RTSP streams
- No authentication polling = no rate limits
- Continuous 24/7 streaming without interruption

**RTSP Stream URLs:**

Each camera has 3 quality levels:

```bash
# High Quality (1080p+ or camera max resolution)
rtsp://192.168.10.49:7447/[CAMERA_ID]?enableSrtp

# Medium Quality (720p)
rtsp://192.168.10.49:7447/[CAMERA_ID]_sub?enableSrtp

# Low Quality (recording/detection)
rtsp://192.168.10.49:7447/[CAMERA_ID]_low?enableSrtp
```

### 2. Get Camera IDs

**Method 1: UniFi Protect Web UI**

1. Open UniFi Protect: `https://192.168.10.49`
2. Click on a camera
3. Look at URL: `https://192.168.10.49/protect/devices/[CAMERA_ID]`
4. The `CAMERA_ID` is the long alphanumeric string

**Method 2: API Call**

```bash
# Get all cameras
curl -k -X GET \
  -H "Authorization: Bearer YOUR_API_TOKEN" \
  https://192.168.10.49/proxy/protect/api/cameras

# Returns JSON with camera details including IDs
```

**Method 3: RTSP Discovery**

```bash
# Test RTSP stream (will show if ID is correct)
ffplay rtsp://192.168.10.49:7447/[CAMERA_ID]

# If wrong ID, you'll see connection refused
# If correct ID, video will play
```

## Frigate Configuration

### Basic Camera Configuration

```yaml
cameras:
  front_door:  # Camera name (can be anything)
    enabled: true
    ffmpeg:
      inputs:
        # High quality for detection
        - path: rtsp://192.168.10.49:7447/12345ABCDEF?enableSrtp
          roles:
            - detect
            - record
        # Medium quality for recording (saves space)
        - path: rtsp://192.168.10.49:7447/12345ABCDEF_sub?enableSrtp
          roles:
            - record
    
    # Detection settings
    detect:
      width: 1920   # Match camera resolution
      height: 1080
      fps: 5        # Lower FPS saves CPU
      enabled: true
    
    # Motion detection
    motion:
      mask:
        # Ignore motion in specific areas (trees, flags, etc.)
        # Format: x1,y1,x2,y2,x3,y3,...
        - 0,0,200,0,200,100,0,100  # Top-left corner (example)
    
    # Detection zones
    zones:
      entrance:
        coordinates: 0,1080,400,1080,400,700,0,700
        objects:
          - person
          - package
      driveway:
        coordinates: 400,1080,1920,1080,1920,700,400,700
        objects:
          - person
          - car
    
    # Object tracking
    objects:
      track:
        - person
        - car
        - dog
        - cat
        - package
      filters:
        person:
          min_area: 5000
          max_area: 100000
          threshold: 0.7
    
    # Snapshots
    snapshots:
      enabled: true
      timestamp: true
      bounding_box: true
      crop: true
      required_zones:
        - entrance
        - driveway
    
    # Recording
    record:
      enabled: true
      retain:
        days: 7
        mode: motion  # Only record when motion detected
      events:
        retain:
          default: 30  # Keep events for 30 days
```

### All 22 Boulder House Cameras

You need to:

1. Get camera IDs from UniFi Protect
2. Add each camera to `frigate/config.yml`
3. Configure zones per camera
4. Set motion masks for each

**Camera Naming Convention:**

```yaml
cameras:
  # Exterior
  front_door:
  back_door:
  side_gate_left:
  side_gate_right:
  driveway:
  garage_exterior:
  front_yard:
  back_yard:
  
  # Perimeter
  north_perimeter:
  south_perimeter:
  east_perimeter:
  west_perimeter:
  
  # Interior
  garage_interior:
  basement_entrance:
  main_entrance:
  
  # Specific locations
  pool_area:
  shed:
  workshop:
  
  # etc... (total 22)
```

## Testing RTSP Streams

### Test Single Stream

```bash
# Install ffmpeg (if not installed)
brew install ffmpeg  # macOS
apt-get install ffmpeg  # Ubuntu

# Test RTSP stream
ffplay rtsp://192.168.10.49:7447/[CAMERA_ID]?enableSrtp

# Should open video player with live stream
# Press Q to quit
```

### Test All Streams

```bash
# Create test script
cat > test-streams.sh << 'EOF'
#!/bin/bash

CAMERAS=(
  "front_door:12345ABCDEF"
  "back_door:67890GHIJKL"
  # Add all camera_name:camera_id pairs
)

for cam in "${CAMERAS[@]}"; do
  name="${cam%:*}"
  id="${cam#*:}"
  echo "Testing $name ($id)..."
  
  timeout 5 ffmpeg -rtsp_transport tcp \
    -i "rtsp://192.168.10.49:7447/${id}?enableSrtp" \
    -frames:v 1 -f null - 2>&1 | grep -q "Stream #0:0"
  
  if [ $? -eq 0 ]; then
    echo "✓ $name works"
  else
    echo "✗ $name failed"
  fi
done
EOF

chmod +x test-streams.sh
./test-streams.sh
```

## UniFi Protect API (Optional)

For advanced features (PTZ control, settings changes), you can use the UniFi Protect API.

### Get API Token

```bash
# Login to UniFi Protect
curl -k -X POST https://192.168.10.49/api/auth/login \
  -H "Content-Type: application/json" \
  -d '{
    "username": "your-username",
    "password": "your-password"
  }'

# Returns:
# {
#   "accessToken": "eyJ...",
#   "refreshToken": "eyJ..."
# }

# Save the accessToken - valid for 24 hours
```

### API Endpoints

```bash
# Get all cameras
GET /proxy/protect/api/cameras

# Get specific camera
GET /proxy/protect/api/cameras/[CAMERA_ID]

# Update camera settings
PATCH /proxy/protect/api/cameras/[CAMERA_ID]

# Get bootstrap (all config)
GET /proxy/protect/api/bootstrap

# Get NVR info
GET /proxy/protect/api/nvr
```

### Important: Don't Poll API

✅ **DO:** Use API for one-time config changes  
✅ **DO:** Use API for manual camera controls  
❌ **DON'T:** Poll API for camera status (use RTSP)  
❌ **DON'T:** Poll API for motion events (use MQTT webhooks)

## Webhook Integration (Future)

UniFi Protect supports webhooks for events:

```yaml
# UniFi Protect Webhook Configuration
webhooks:
  - url: http://node-red:1880/webhook/unifi
    events:
      - motion
      - smart_detection
      - doorbell_ring
```

**Not required for basic operation** - RTSP streams provide all motion detection via Frigate.

## Network Requirements

### Bandwidth

**Per Camera:**
- High quality: 3-5 Mbps
- Medium quality: 1-2 Mbps  
- Low quality: 0.5-1 Mbps

**22 Cameras Total:**
- Using medium quality: ~30-50 Mbps
- Using high quality: ~70-110 Mbps

**Boulder Network:**
- Local network: 1 Gbps (plenty of headroom)
- UniFi NVR: Gigabit connection

### Latency

- RTSP stream latency: 1-3 seconds
- Detection latency: <1 second (after stream)
- Total latency: 2-4 seconds (acceptable for automation)

## Troubleshooting

### Stream Won't Connect

```bash
# Check if UniFi Protect is reachable
ping 192.168.10.49

# Check if RTSP port is open
nc -zv 192.168.10.49 7447

# Verify camera ID
curl -k https://192.168.10.49/proxy/protect/api/cameras
```

### Stream Drops Frequently

**Possible causes:**
1. Network congestion
2. UniFi Protect CPU overload
3. Frigate CPU overload
4. Insufficient bandwidth

**Solutions:**
```yaml
# In frigate/config.yml, reduce FPS
cameras:
  front_door:
    detect:
      fps: 3  # Lower from 5 to 3

# Or use lower quality stream
ffmpeg:
  inputs:
    - path: rtsp://192.168.10.49:7447/[ID]_sub?enableSrtp  # Use _sub instead
```

### Detection Not Working

```bash
# Check Frigate logs
docker-compose logs -f frigate

# Check if objects are detected in Frigate UI
open http://localhost:5000

# Verify zones are correctly configured
# Use Frigate UI to draw zones visually
```

### Rate Limit Errors

**If you see rate limit errors:**
- You're likely still using authentication polling somewhere
- Check that you're NOT using UniFi Protect integration plugins
- Verify all cameras use RTSP streams only
- RTSP streams don't cause rate limits

## Performance Optimization

### CPU Usage

**Without Hardware Acceleration:**
- 22 cameras × 5 FPS = ~4 cores @ 100%

**With Coral TPU:**
- 22 cameras × 5 FPS = ~1 core @ 20%

**Recommendation:** Add Coral TPU for 10x performance improvement

### Storage Optimization

```yaml
# Record only on motion
record:
  retain:
    days: 7
    mode: motion  # Not continuous

# Use lower quality for recording
ffmpeg:
  inputs:
    - path: rtsp://192.168.10.49:7447/[ID]_sub?enableSrtp
      roles:
        - record  # Use medium quality for recording
```

## Security Considerations

### RTSP Stream Security

- RTSP streams are unencrypted (local network only)
- Don't expose RTSP ports to internet
- Use Cloudflare Tunnel for remote access to UI (not RTSP)

### Credentials

```bash
# Store in .env file
UNIFI_HOST=192.168.10.49
UNIFI_USERNAME=homeassistant
UNIFI_PASSWORD=your-secure-password

# Never commit .env to git
echo ".env" >> .gitignore
```

## Next Steps

1. ✅ Get all 22 camera IDs from UniFi Protect
2. ✅ Configure Frigate with all cameras
3. ✅ Set up zones for each camera
4. ✅ Configure motion masks
5. ✅ Test detection accuracy
6. ✅ Integrate with Node-RED
7. ✅ Set up MQTT event handling