#!/bin/bash

# Boulder Home Automation - Automated Setup Script
# This script sets up the entire stack on Boulder Mac Mini

set -e  # Exit on error

echo "=========================================="
echo "Boulder Home Automation Setup"
echo "=========================================="
echo ""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Helper functions
info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
    exit 1
}

# Check if running on Mac
if [[ "$OSTYPE" != "darwin"* ]]; then
    warn "This script is designed for macOS (Boulder Mac Mini)"
    read -p "Continue anyway? (y/n) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

# Check prerequisites
info "Checking prerequisites..."

# Check Docker
if ! command -v docker &> /dev/null; then
    error "Docker not found. Please install Docker Desktop first."
fi

# Check Docker Compose
if ! docker compose version &> /dev/null; then
    error "Docker Compose not found. Please install Docker Desktop with Compose."
fi

# Check Docker is running
if ! docker ps &> /dev/null; then
    error "Docker is not running. Please start Docker Desktop."
fi

info "✓ Docker is installed and running"

# Check disk space
AVAILABLE_GB=$(df -g . | awk 'NR==2 {print $4}')
if [ "$AVAILABLE_GB" -lt 100 ]; then
    warn "Low disk space: ${AVAILABLE_GB}GB available"
    warn "Recommended: 500GB+ for 7 day video retention"
    read -p "Continue anyway? (y/n) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

info "✓ Disk space check passed (${AVAILABLE_GB}GB available)"

# Create .env file if it doesn't exist
if [ ! -f .env ]; then
    info "Creating .env file from template..."
    cp .env.example .env
    
    warn "⚠️  IMPORTANT: Edit .env file with your credentials!"
    warn "Required:"
    warn "  - UNIFI_HOST (default: 192.168.10.49)"
    warn "  - UNIFI_USERNAME"
    warn "  - UNIFI_PASSWORD"
    warn "  - POSTGRES_PASSWORD"
    warn "  - MQTT_PASSWORD"
    warn "  - ABODE_USERNAME"
    warn "  - ABODE_PASSWORD"
    echo ""
    read -p "Press Enter to edit .env file..."
    
    # Open in default editor
    if command -v nano &> /dev/null; then
        nano .env
    elif command -v vi &> /dev/null; then
        vi .env
    else
        warn "No text editor found. Please edit .env manually."
    fi
else
    info "✓ .env file already exists"
fi

# Create required directories
info "Creating required directories..."
mkdir -p mosquitto/config mosquitto/data mosquitto/log
mkdir -p node-red/data
mkdir -p frigate/storage
mkdir -p postgres/data
mkdir -p nginx/html

info "✓ Directories created"

# Set permissions
info "Setting permissions..."
chmod -R 755 mosquitto/config
chmod -R 755 node-red/data
chmod -R 755 frigate/storage
chmod -R 755 postgres/data

info "✓ Permissions set"

# Create Mosquitto password file
if [ ! -f mosquitto/config/password.txt ]; then
    info "Creating Mosquitto password file..."
    
    # Get MQTT credentials from .env
    source .env
    
    # Create password file
    docker run --rm -v $(pwd)/mosquitto/config:/mosquitto/config eclipse-mosquitto:2.0 \
        mosquitto_passwd -b -c /mosquitto/config/password.txt \
        "${MQTT_USERNAME}" "${MQTT_PASSWORD}"
    
    info "✓ Mosquitto password file created"
else
    info "✓ Mosquitto password file already exists"
fi

# Pull Docker images
info "Pulling Docker images (this may take a while)..."
docker compose pull

info "✓ Docker images pulled"

# Start services
info "Starting services..."
docker compose up -d

info "✓ Services started"

# Wait for services to be healthy
info "Waiting for services to be ready..."
sleep 10

# Check service status
info "Checking service status..."
docker compose ps

# Get service URLs
echo ""
echo "=========================================="
echo "Setup Complete! 🎉"
echo "=========================================="
echo ""
echo "Services are running at:"
echo ""
echo "  Node-RED:     http://localhost:1880"
echo "  Frigate:      http://localhost:5000"
echo "  MQTT Broker:  localhost:1883"
echo "  PostgreSQL:   localhost:5432"
echo ""
echo "Next steps:"
echo ""
echo "1. Open Node-RED:    http://localhost:1880"
echo "2. Import flows:     node-red/flows/example-flows.json"
echo "3. Configure cameras in Frigate config"
echo "4. Get camera IDs from UniFi Protect"
echo "5. Update frigate/config.yml with all 22 cameras"
echo "6. Restart Frigate:  docker compose restart frigate"
echo ""
echo "Documentation:"
echo ""
echo "  Architecture:   docs/ARCHITECTURE.md"
echo "  UniFi Setup:    docs/UNIFI-INTEGRATION.md"
echo "  MCP Integration: docs/MCP-INTEGRATION.md"
echo ""
echo "To view logs:"
echo "  docker compose logs -f"
echo ""
echo "To stop services:"
echo "  docker compose down"
echo ""
echo "=========================================="