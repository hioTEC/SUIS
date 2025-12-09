#!/bin/bash

# SUI Proxy Installation Script
# This script sets up the SUI Proxy system with Sing-box on port 443 and Caddy gateway on port 80

set -e

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Installation directories
INSTALL_DIR="/opt/sui-proxy"
CONFIG_DIR="${INSTALL_DIR}/config"
GATEWAY_DIR="${INSTALL_DIR}/gateway"
NODE_DIR="${INSTALL_DIR}/node"

# Logging functions
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# Check if running as root
check_root() {
    if [ "$EUID" -ne 0 ]; then
        log_error "Please run as root or with sudo"
        exit 1
    fi
}

# Check system requirements
check_requirements() {
    log_info "Checking system requirements..."
    
    # Check for Docker
    if ! command -v docker &> /dev/null; then
        log_error "Docker is not installed. Please install Docker first."
        exit 1
    fi
    
    # Check for Docker Compose
    if ! command -v docker compose &> /dev/null; then
        log_error "Docker Compose is not installed. Please install Docker Compose first."
        exit 1
    fi
    
    # Check for jq (for JSON validation)
    if ! command -v jq &> /dev/null; then
        log_warning "jq is not installed. Installing jq for JSON validation..."
        apt-get update && apt-get install -y jq || yum install -y jq
    fi
    
    log_info "All requirements satisfied"
}

# Setup directories
setup_directories() {
    log_info "Setting up directories..."
    
    mkdir -p "${INSTALL_DIR}"
    mkdir -p "${CONFIG_DIR}/singbox"
    mkdir -p "${CONFIG_DIR}/caddy"
    mkdir -p "${GATEWAY_DIR}"
    mkdir -p "${NODE_DIR}/config/singbox"
    mkdir -p "${NODE_DIR}/config/caddy"
    
    log_info "Directories created"
}

# Generate UUID for VLESS
generate_uuid() {
    if command -v uuidgen &> /dev/null; then
        uuidgen | tr '[:upper:]' '[:lower:]'
    else
        cat /proc/sys/kernel/random/uuid
    fi
}

# Generate random password
generate_password() {
    openssl rand -base64 32 | tr -d "=+/" | cut -c1-25
}

# Collect user input
collect_user_input() {
    log_info "Collecting configuration information..."
    
    # Master domain
    read -p "Enter Master domain (e.g., master.example.com): " MASTER_DOMAIN
    while [ -z "$MASTER_DOMAIN" ]; do
        log_error "Master domain cannot be empty"
        read -p "Enter Master domain: " MASTER_DOMAIN
    done
    
    # Node domain
    read -p "Enter Node domain (e.g., node.example.com): " NODE_DOMAIN
    while [ -z "$NODE_DOMAIN" ]; do
        log_error "Node domain cannot be empty"
        read -p "Enter Node domain: " NODE_DOMAIN
    done
    
    # ACME email
    read -p "Enter email for ACME/Let's Encrypt: " ACME_EMAIL
    while [ -z "$ACME_EMAIL" ]; then
        log_error "Email cannot be empty"
        read -p "Enter email: " ACME_EMAIL
    done
    
    # Generate credentials
    VLESS_UUID=$(generate_uuid)
    HY2_PASSWORD=$(generate_password)
    ADGUARD_ADMIN_PASS=$(generate_password)
    PATH_PREFIX="sui"
    GATEWAY_CONTAINER="sui-gateway"
    
    log_info "Configuration collected"
}

# Generate Sing-box configuration
generate_singbox_config() {
    log_info "Generating Sing-box configuration..."
    
    local output_file="${NODE_DIR}/config/singbox/config.json"
    local template_file="node/templates/singbox-config.json.template"
    
    if [ ! -f "$template_file" ]; then
        log_error "Template file not found: $template_file"
        exit 1
    fi
    
    # Substitute variables in template
    sed -e "s/\${VLESS_UUID}/${VLESS_UUID}/g" \
        -e "s/\${NODE_DOMAIN}/${NODE_DOMAIN}/g" \
        -e "s/\${ACME_EMAIL}/${ACME_EMAIL}/g" \
        -e "s/\${GATEWAY_CONTAINER}/${GATEWAY_CONTAINER}/g" \
        -e "s/\${HY2_PASSWORD}/${HY2_PASSWORD}/g" \
        "$template_file" > "$output_file"
    
    # Validate JSON
    if ! jq empty "$output_file" 2>/dev/null; then
        log_error "Generated Sing-box config is invalid JSON"
        exit 1
    fi
    
    log_info "Sing-box configuration generated: $output_file"
}

# Generate Caddyfile
generate_caddyfile() {
    log_info "Generating Caddyfile..."
    
    local output_file="${NODE_DIR}/config/caddy/Caddyfile"
    local template_file="node/templates/Caddyfile.template"
    
    if [ ! -f "$template_file" ]; then
        log_error "Template file not found: $template_file"
        exit 1
    fi
    
    # Substitute variables in template (Go template style)
    sed -e "s/{{\.MasterDomain}}/${MASTER_DOMAIN}/g" \
        -e "s/{{\.NodeDomain}}/${NODE_DOMAIN}/g" \
        -e "s/{{\.PathPrefix}}/${PATH_PREFIX}/g" \
        -e "s/{{\.AdGuardAdminPass}}/${ADGUARD_ADMIN_PASS}/g" \
        "$template_file" > "$output_file"
    
    log_info "Caddyfile generated: $output_file"
}

# Generate gateway docker-compose.yml
generate_gateway_compose() {
    log_info "Generating gateway docker-compose.yml..."
    
    local output_file="${GATEWAY_DIR}/docker-compose.yml"
    
    cat > "$output_file" << 'EOF'
version: '3.8'

services:
  gateway:
    image: caddy:2-alpine
    container_name: sui-gateway
    restart: unless-stopped
    ports:
      - "80:80"
    volumes:
      - ../node/config/caddy/Caddyfile:/etc/caddy/Caddyfile:ro
      - caddy_data:/data
      - caddy_config:/config
    networks:
      - sui-master-net
      - sui-node-net
    healthcheck:
      test: ["CMD", "wget", "--quiet", "--tries=1", "--spider", "http://localhost:80/health"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 40s

volumes:
  caddy_data:
    name: sui-caddy-data
  caddy_config:
    name: sui-caddy-config

networks:
  sui-master-net:
    external: true
  sui-node-net:
    external: true
EOF
    
    # Validate YAML
    if ! docker compose -f "$output_file" config > /dev/null 2>&1; then
        log_error "Generated gateway docker-compose.yml is invalid"
        exit 1
    fi
    
    log_info "Gateway docker-compose.yml generated: $output_file"
}

# Generate node docker-compose.yml
generate_node_compose() {
    log_info "Generating node docker-compose.yml..."
    
    local output_file="${NODE_DIR}/docker-compose.yml"
    
    # Copy the template
    cp "node/docker-compose.yml" "$output_file"
    
    # Validate YAML
    if ! docker compose -f "$output_file" config > /dev/null 2>&1; then
        log_error "Node docker-compose.yml is invalid"
        exit 1
    fi
    
    log_info "Node docker-compose.yml generated: $output_file"
}

# Create Docker networks
setup_docker_networks() {
    log_info "Setting up Docker networks..."
    
    # Create sui-master-net if it doesn't exist
    if ! docker network inspect sui-master-net &> /dev/null; then
        docker network create sui-master-net
        log_info "Created network: sui-master-net"
    else
        log_info "Network sui-master-net already exists"
    fi
    
    # Create sui-node-net if it doesn't exist
    if ! docker network inspect sui-node-net &> /dev/null; then
        docker network create sui-node-net
        log_info "Created network: sui-node-net"
    else
        log_info "Network sui-node-net already exists"
    fi
}

# Check port availability
check_port_availability() {
    log_info "Checking port availability..."
    
    local ports=(80 443)
    local port_in_use=false
    
    for port in "${ports[@]}"; do
        if ss -tlnp 2>/dev/null | grep -q ":${port} " || netstat -tlnp 2>/dev/null | grep -q ":${port} "; then
            log_error "Port ${port} is already in use:"
            ss -tlnp 2>/dev/null | grep ":${port} " || netstat -tlnp 2>/dev/null | grep ":${port} "
            port_in_use=true
        fi
    done
    
    if [ "$port_in_use" = true ]; then
        log_error "Please free up the required ports before continuing"
        exit 1
    fi
    
    log_info "All required ports are available"
}

# Save configuration
save_configuration() {
    log_info "Saving configuration..."
    
    local config_file="${CONFIG_DIR}/config.env"
    
    cat > "$config_file" << EOF
# SUI Proxy Configuration
MASTER_DOMAIN=${MASTER_DOMAIN}
NODE_DOMAIN=${NODE_DOMAIN}
ACME_EMAIL=${ACME_EMAIL}
VLESS_UUID=${VLESS_UUID}
HY2_PASSWORD=${HY2_PASSWORD}
ADGUARD_ADMIN_PASS=${ADGUARD_ADMIN_PASS}
PATH_PREFIX=${PATH_PREFIX}
GATEWAY_CONTAINER=${GATEWAY_CONTAINER}
EOF
    
    chmod 600 "$config_file"
    log_info "Configuration saved to: $config_file"
}

# Display credentials
display_credentials() {
    echo ""
    echo "========================================="
    echo "  SUI Proxy Installation Complete!"
    echo "========================================="
    echo ""
    echo "Master Domain: ${MASTER_DOMAIN}"
    echo "Node Domain: ${NODE_DOMAIN}"
    echo ""
    echo "VLESS UUID: ${VLESS_UUID}"
    echo "Hysteria2 Password: ${HY2_PASSWORD}"
    echo "AdGuard Admin Password: ${ADGUARD_ADMIN_PASS}"
    echo ""
    echo "Configuration saved to: ${CONFIG_DIR}/config.env"
    echo ""
    echo "To start services:"
    echo "  cd ${GATEWAY_DIR} && docker compose up -d"
    echo "  cd ${NODE_DIR} && docker compose up -d"
    echo ""
    echo "========================================="
}

# Main installation function
main() {
    log_info "Starting SUI Proxy installation..."
    
    check_root
    check_requirements
    check_port_availability
    setup_directories
    collect_user_input
    setup_docker_networks
    
    generate_singbox_config
    generate_caddyfile
    generate_gateway_compose
    generate_node_compose
    
    save_configuration
    display_credentials
    
    log_info "Installation completed successfully!"
}

# Run main function
main "$@"
