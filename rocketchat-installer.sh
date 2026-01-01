#!/bin/bash

#############################################################################
# RocketChat One-Click Installer
# 
# Created by: Ramtin - NetAdminPlus
# Website: https://netadminplus.com
# YouTube: https://youtube.com/@netadminplus
# Instagram: https://instagram.com/netadminplus
#############################################################################

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Banner
clear
echo -e "${CYAN}"
echo "╔════════════════════════════════════════════════════════════════╗"
echo "║                                                                ║"
echo "║           🚀 RocketChat One-Click Installer 🚀                ║"
echo "║                                                                ║"
echo "║              Created by: Ramtin - NetAdminPlus                ║"
echo "║           https://netadminplus.com                            ║"
echo "║           YouTube: @netadminplus                              ║"
echo "║           Instagram: @netadminplus                            ║"
echo "║                                                                ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo -e "${NC}\n"

#############################################################################
# Helper Functions
#############################################################################

print_success() {
    echo -e "${GREEN}✓${NC} $1"
}

print_error() {
    echo -e "${RED}✗${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

print_info() {
    echo -e "${CYAN}ℹ${NC} $1"
}

print_step() {
    echo -e "${BLUE}==>${NC} ${GREEN}$1${NC}"
}

#############################################################################
# Gather Information
#############################################################################

echo -e "${BLUE}Configuration Setup${NC}\n"

# Domain
read -p "1. Enter your domain (e.g., chat.example.com): " DOMAIN < /dev/tty
while [ -z "$DOMAIN" ]; do
    print_error "Domain cannot be empty"
    read -p "1. Enter your domain (e.g., chat.example.com): " DOMAIN < /dev/tty
done

# Port
read -p "2. Server port (default: 3000): " PORT < /dev/tty
PORT=${PORT:-3000}

# Version
read -p "3. RocketChat version (default: latest): " RELEASE < /dev/tty
RELEASE=${RELEASE:-latest}

# Email
read -p "4. Email for SSL/alerts (optional, press Enter to skip): " EMAIL < /dev/tty

# Docker Mirror
echo ""
print_info "If Docker Hub is blocked, you can provide a mirror URL"
read -p "5. Docker mirror URL (optional, press Enter to skip): " DOCKER_MIRROR < /dev/tty

echo ""

#############################################################################
# Check DNS
#############################################################################

print_step "Checking DNS configuration..."

# Try multiple IP detection services with better error handling
PUBLIC_IP=""

# Try ip.sb first (usually works in Iran)
PUBLIC_IP=$(curl -s --connect-timeout 5 --max-time 10 https://ip.sb 2>/dev/null || echo "")

# If failed, try icanhazip
if [ -z "$PUBLIC_IP" ] || [[ "$PUBLIC_IP" =~ "html" ]]; then
    PUBLIC_IP=$(curl -s --connect-timeout 5 --max-time 10 https://icanhazip.com 2>/dev/null || echo "")
fi

# If still failed, try ipinfo.io
if [ -z "$PUBLIC_IP" ] || [[ "$PUBLIC_IP" =~ "html" ]]; then
    PUBLIC_IP=$(curl -s --connect-timeout 5 --max-time 10 https://ipinfo.io/ip 2>/dev/null || echo "")
fi

# Validate IP format
if [[ "$PUBLIC_IP" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    print_info "Your public IP: $PUBLIC_IP"
    
    # Check DNS resolution
    if command -v dig &> /dev/null; then
        DOMAIN_IP=$(dig +short "$DOMAIN" @8.8.8.8 | tail -n1)
    elif command -v host &> /dev/null; then
        DOMAIN_IP=$(host "$DOMAIN" 8.8.8.8 | grep "has address" | head -n1 | awk '{print $4}')
    elif command -v nslookup &> /dev/null; then
        DOMAIN_IP=$(nslookup "$DOMAIN" 8.8.8.8 | grep -A1 "Name:" | tail -n1 | awk '{print $2}')
    fi
    
    if [ "$DOMAIN_IP" == "$PUBLIC_IP" ]; then
        print_success "DNS verified: $DOMAIN → $PUBLIC_IP"
    elif [ -z "$DOMAIN_IP" ]; then
        print_warning "Could not resolve domain. Please ensure DNS is configured"
    else
        print_warning "DNS mismatch!"
        print_info "Expected: $PUBLIC_IP"
        print_info "Got: $DOMAIN_IP"
        print_info "Please update your DNS A record"
    fi
else
    print_warning "Could not detect public IP (services may be blocked)"
    print_info "Skipping DNS check"
fi

echo ""

#############################################################################
# Install Docker
#############################################################################

print_step "Checking Docker installation..."

if ! command -v docker &> /dev/null; then
    print_info "Docker not found. Installing..."
    
    # Try get.docker.com first
    if curl -fsSL https://get.docker.com -o get-docker.sh 2>/dev/null; then
        if [ ! -z "$DOCKER_MIRROR" ]; then
            print_info "Using Docker mirror: $DOCKER_MIRROR"
            sh get-docker.sh --mirror "$DOCKER_MIRROR"
        else
            sh get-docker.sh
        fi
        rm get-docker.sh
        print_success "Docker installed from official script"
    else
        # Fallback to apt if get.docker.com is blocked
        print_warning "Official Docker installation blocked, using system packages..."
        
        if command -v apt &> /dev/null; then
            apt update -qq
            apt install -y docker.io docker-compose -qq
            print_success "Docker installed from system repository"
        elif command -v yum &> /dev/null; then
            yum install -y docker docker-compose -q
            print_success "Docker installed from system repository"
        else
            print_error "Cannot install Docker. Please install manually."
            exit 1
        fi
    fi
    
    # Start Docker
    systemctl start docker
    systemctl enable docker &> /dev/null
else
    DOCKER_VER=$(docker --version | awk '{print $3}' | tr -d ',')
    print_success "Docker already installed (version: $DOCKER_VER)"
fi

# Check for Docker Compose
if docker compose version &> /dev/null 2>&1; then
    print_success "Docker Compose plugin available"
    DOCKER_COMPOSE="docker compose"
elif command -v docker-compose &> /dev/null; then
    print_success "Docker Compose standalone available"
    DOCKER_COMPOSE="docker-compose"
else
    print_info "Installing Docker Compose plugin..."
    if command -v apt &> /dev/null; then
        apt install -y docker-compose-plugin -qq 2>/dev/null || apt install -y docker-compose -qq
    fi
    
    if docker compose version &> /dev/null 2>&1; then
        DOCKER_COMPOSE="docker compose"
    elif command -v docker-compose &> /dev/null; then
        DOCKER_COMPOSE="docker-compose"
    else
        print_error "Could not install Docker Compose"
        exit 1
    fi
fi

echo ""

#############################################################################
# Generate docker-compose.yml
#############################################################################

print_step "Generating configuration..."

# Determine ROOT_URL
if [ "$PORT" == "443" ] || [ "$PORT" == "80" ]; then
    ROOT_URL="https://$DOMAIN"
else
    ROOT_URL="http://$DOMAIN:$PORT"
fi

# Create docker-compose.yml directly (no template needed)
cat > docker-compose.yml <<EOF
version: '3.8'

services:
  rocketchat:
    image: registry.rocket.chat/rocketchat/rocket.chat:${RELEASE}
    command: >
      bash -c
        "for i in \`seq 1 30\`; do
          node main.js &&
          s=\$\$? && break || s=\$\$?;
          echo \"Tried \$\$i times. Waiting 5 secs...\";
          sleep 5;
        done; (exit \$\$s)"
    restart: unless-stopped
    volumes:
      - uploads:/app/uploads
    environment:
      PORT: 3000
      ROOT_URL: ${ROOT_URL}
      MONGO_URL: mongodb://mongodb:27017/rocketchat?replicaSet=rs0
      MONGO_OPLOG_URL: mongodb://mongodb:27017/local?replicaSet=rs0
    ports:
      - "${PORT}:3000"
    depends_on:
      - mongodb

  mongodb:
    image: mongo:5.0
    restart: unless-stopped
    volumes:
      - db-data:/data/db
      - db-dump:/dump
    command: mongod --oplogSize 128 --replSet rs0
    expose:
      - 27017

  mongo-init-replica:
    image: mongo:5.0
    command: >
      bash -c "for i in \`seq 1 30\`; do
        mongo mongodb/rocketchat --eval \"rs.initiate({ _id: 'rs0', members: [ { _id: 0, host: 'mongodb:27017' } ]})\" &&
        s=\$\$? && break || s=\$\$?;
        echo \"Tried \$\$i times. Waiting 5 secs...\";
        sleep 5;
      done; (exit \$\$s)"
    depends_on:
      - mongodb

volumes:
  uploads:
  db-data:
  db-dump:
EOF

print_success "Configuration created"

echo ""

#############################################################################
# Start Services
#############################################################################

print_step "Starting RocketChat services..."

$DOCKER_COMPOSE pull
$DOCKER_COMPOSE up -d

if [ $? -eq 0 ]; then
    echo ""
    echo -e "${GREEN}╔════════════════════════════════════════════════════════════════╗"
    echo -e "║                                                                ║"
    echo -e "║                  🎉 Installation Complete! 🎉                 ║"
    echo -e "║                                                                ║"
    echo -e "╚════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    print_success "RocketChat is running at: ${BLUE}${ROOT_URL}${NC}"
    echo ""
    print_info "Useful commands:"
    echo -e "  ${YELLOW}View logs:${NC}     $DOCKER_COMPOSE logs -f"
    echo -e "  ${YELLOW}Stop:${NC}          $DOCKER_COMPOSE down"
    echo -e "  ${YELLOW}Restart:${NC}       $DOCKER_COMPOSE restart"
    echo -e "  ${YELLOW}Status:${NC}        $DOCKER_COMPOSE ps"
    echo ""
    echo -e "${CYAN}Created by Ramtin - NetAdminPlus${NC}"
    echo -e "YouTube: @netadminplus | Instagram: @netadminplus"
    echo ""
else
    echo ""
    print_error "Failed to start containers"
    echo ""
    print_info "Check logs with: $DOCKER_COMPOSE logs"
    exit 1
fi
