#!/bin/bash
#
# ███████╗██╗   ██╗██╗    ███████╗ ██████╗ ██╗      ██████╗
# ██╔════╝██║   ██║██║    ██╔════╝██╔═══██╗██║     ██╔═══██╗
# ███████╗██║   ██║██║    ███████╗██║   ██║██║     ██║   ██║
# ╚════██║██║   ██║██║    ╚════██║██║   ██║██║     ██║   ██║
# ███████║╚██████╔╝██║    ███████║╚██████╔╝███████╗╚██████╔╝
# ╚══════╝ ╚═════╝ ╚═╝    ╚══════╝ ╚═════╝ ╚══════╝ ╚═════╝
#
# SUI Solo - Distributed Proxy Cluster Management
# https://github.com/pjonix/SUIS
#

set -e

#=============================================================================
# CONSTANTS
#=============================================================================
readonly VERSION="2.0.1"
readonly PROJECT_NAME="SUI Solo"
readonly BASE_DIR="/opt/sui-solo"
readonly MASTER_INSTALL_DIR="/opt/sui-solo/master"
readonly NODE_INSTALL_DIR="/opt/sui-solo/node"
readonly GATEWAY_DIR="/opt/sui-solo/gateway"
readonly SALT="SUI_Solo_Secured_2025"

# Colors
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly CYAN='\033[0;36m'
readonly MAGENTA='\033[0;35m'
readonly BOLD='\033[1m'
readonly NC='\033[0m'

# Symbols
readonly CHECK="${GREEN}✔${NC}"
readonly CROSS="${RED}✘${NC}"
readonly ARROW="${CYAN}➜${NC}"

# Global
SHARED_CADDY_MODE=false
INSTALL_MODE=""
CLI_MODE=""
domain=""
master_domain=""
node_domain=""
email=""
secret=""

#=============================================================================
# UTILS
#=============================================================================
log_info()    { echo -e "${BLUE}[INFO]${NC}    $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC}    $1"; }
log_error()   { echo -e "${RED}[ERROR]${NC}   $1"; }
log_step()    { echo -e "${ARROW} ${BOLD}$1${NC}"; }

print_banner() {
    clear
    echo -e "${CYAN}"
    cat << EOF
╔═══════════════════════════════════════════════════════════════════╗
║     ███████╗██╗   ██╗██╗    ███████╗ ██████╗ ██╗      ██████╗     ║
║     ██╔════╝██║   ██║██║    ██╔════╝██╔═══██╗██║     ██╔═══██╗    ║
║     ███████╗██║   ██║██║    ███████╗██║   ██║██║     ██║   ██║    ║
║     ╚════██║██║   ██║██║    ╚════██║██║   ██║██║     ██║   ██║    ║
║     ███████║╚██████╔╝██║    ███████║╚██████╔╝███████╗╚██████╔╝    ║
║     ╚══════╝ ╚═════╝ ╚═╝    ╚══════╝ ╚═════╝ ╚══════╝ ╚═════╝     ║
║           Distributed Proxy Cluster Management v${VERSION}            ║
╚═══════════════════════════════════════════════════════════════════╝
EOF
    echo -e "${NC}"
}

confirm() {
    local prompt="${1:-Proceed?}"
    local default="${2:-n}"
    [[ "$default" == "y" ]] && prompt="$prompt [Y/n]: " || prompt="$prompt [y/N]: "
    read -r -p "$prompt" response < /dev/tty
    response=${response:-$default}
    [[ "$response" =~ ^[Yy]$ ]]
}

detect_script_dir() {
    local dir=""
    # Try to get script directory from BASH_SOURCE
    if [[ -n "${BASH_SOURCE[0]:-}" ]] && [[ "${BASH_SOURCE[0]}" != "bash" ]]; then
        dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)" || dir=""
    fi
    # Fallback to current directory
    [[ -z "$dir" || "$dir" == "/" ]] && dir="$(pwd)"
    # Check if source files exist
    if [[ -d "$dir/master" && -d "$dir/node" ]]; then echo "$dir"; return 0; fi
    if [[ -d "$dir/../master" && -d "$dir/../node" ]]; then echo "$(cd "$dir/.." 2>/dev/null && pwd)"; return 0; fi
    if [[ -d "./master" && -d "./node" ]]; then echo "$(pwd)"; return 0; fi
    # Return empty if not found (will trigger download)
    echo ""
    return 0
}

download_source_files() {
    log_step "Downloading source files from GitHub..."
    local github_zip="https://github.com/pjonix/SUIS/archive/refs/heads/main.zip"
    local tmp_dir="/tmp/sui-solo-install-$$"
    local zip_file="${tmp_dir}/suis.zip"
    
    rm -rf "$tmp_dir" && mkdir -p "$tmp_dir"
    
    log_info "Downloading from: $github_zip"
    if curl -fsSL "$github_zip" -o "$zip_file"; then
        echo -e "  ${CHECK} Downloaded source archive"
    else
        log_error "Failed to download from GitHub!"; rm -rf "$tmp_dir"; exit 1
    fi
    
    [[ ! -s "$zip_file" ]] && { log_error "Downloaded file is empty!"; rm -rf "$tmp_dir"; exit 1; }
    
    if unzip -q "$zip_file" -d "$tmp_dir"; then
        echo -e "  ${CHECK} Extracted source files"
    else
        log_error "Failed to extract archive!"; rm -rf "$tmp_dir"; exit 1
    fi
    
    local extracted_dir=""
    for dir in "$tmp_dir"/SUIS* "$tmp_dir"/suis*; do
        [[ -d "$dir/master" && -d "$dir/node" ]] && { extracted_dir="$dir"; break; }
    done
    
    if [[ -n "$extracted_dir" ]]; then
        SCRIPT_DIR="$extracted_dir"
        echo -e "  ${CHECK} Source directory: ${CYAN}${SCRIPT_DIR}${NC}"
    else
        log_error "Invalid archive structure!"; rm -rf "$tmp_dir"; exit 1
    fi
}

SCRIPT_DIR="$(detect_script_dir)"

#=============================================================================
# PRE-FLIGHT
#=============================================================================
check_os() {
    OS_TYPE="unknown"
    [[ "$OSTYPE" == "darwin"* ]] && OS_TYPE="macos" || true
    [[ -f /etc/os-release ]] && OS_TYPE="linux" || true
}

check_root() {
    if [[ "$OS_TYPE" == "macos" ]]; then
        [[ "$(id -u)" -ne 0 ]] && log_warn "Running as non-root on macOS. Ensure Docker permissions." || true
    else
        if [[ "$(id -u)" -ne 0 ]]; then
            log_error "This script must be run as root on Linux!"
            exit 1
        fi
    fi
}

check_dependencies() {
    log_step "Checking Dependencies..."
    local missing=() pkg_mgr=""
    
    command -v brew &>/dev/null && pkg_mgr="brew"
    command -v apt-get &>/dev/null && pkg_mgr="apt"
    command -v yum &>/dev/null && pkg_mgr="yum"
    command -v apk &>/dev/null && pkg_mgr="apk"

    for tool in curl openssl unzip; do
        command -v "$tool" &>/dev/null || missing+=("$tool")
    done
    
    [[ "$OS_TYPE" == "macos" ]] && ! command -v lsof &>/dev/null && missing+=("lsof") || true
    [[ "$OS_TYPE" == "linux" ]] && ! command -v ss &>/dev/null && missing+=("iproute2") || true

    if [[ ${#missing[@]} -gt 0 ]]; then
        log_info "Installing: ${missing[*]}"
        case "$pkg_mgr" in
            brew) brew install "${missing[@]}" ;;
            apt)  apt-get update -qq && apt-get install -y -qq "${missing[@]}" ;;
            yum)  yum install -y "${missing[@]}" ;;
            apk)  apk add "${missing[@]}" ;;
            *)    log_error "No package manager. Please install: ${missing[*]}"; exit 1 ;;
        esac
    fi
    
    if ! command -v docker &>/dev/null; then
        if [[ "$OS_TYPE" == "macos" ]]; then
            log_error "Please install Docker Desktop for Mac manually."; exit 1
        else
            log_info "Installing Docker..."
            curl -fsSL https://get.docker.com | sh
            
            # Fix iptables conflict before starting Docker
            fix_iptables_conflict
            
            # Start Docker service (support both systemd and OpenRC)
            if command -v systemctl &>/dev/null; then
                systemctl enable docker && systemctl start docker
            elif command -v rc-service &>/dev/null; then
                rc-update add docker default && rc-service docker start
            elif command -v service &>/dev/null; then
                service docker start
            fi
            # Wait for Docker to be ready
            log_info "Waiting for Docker to start..."
            local retries=30
            while ! docker info &>/dev/null && [[ $retries -gt 0 ]]; do
                sleep 1
                ((retries--))
            done
            if ! docker info &>/dev/null; then
                log_error "Docker failed to start. Try manually: systemctl start docker OR service docker start"
                log_warn "If issue persists, try: update-alternatives --set iptables /usr/sbin/iptables-legacy"
                exit 1
            fi
            echo -e "  ${CHECK} Docker is ready"
        fi
    else
        # Docker already installed, but check for iptables issues
        if ! docker info &>/dev/null; then
            log_warn "Docker is installed but not responding, checking iptables..."
            fix_iptables_conflict
            
            # Try to restart Docker
            if command -v systemctl &>/dev/null; then
                systemctl restart docker
            elif command -v rc-service &>/dev/null; then
                rc-service docker restart
            elif command -v service &>/dev/null; then
                service docker restart
            fi
            
            sleep 3
            if ! docker info &>/dev/null; then
                log_error "Docker is not responding. Please check: systemctl status docker"
                exit 1
            fi
        fi
    fi
}

#=============================================================================
# HELPERS
#=============================================================================
check_port() {
    local port=$1
    if [[ "$OS_TYPE" == "macos" ]]; then
        lsof -i :"$port" >/dev/null 2>&1 && return 1
    else
        ss -tuln 2>/dev/null | grep -q ":${port} " && return 1
    fi
    return 0
}

kill_port_process() {
    local port=$1
    log_info "Freeing port $port..."
    
    # First try to stop SUI Solo containers that might be using the port
    local sui_containers=("sui-gateway" "sui-master" "sui-agent" "sui-singbox" "sui-adguard")
    for container in "${sui_containers[@]}"; do
        if docker ps -q -f name="$container" 2>/dev/null | grep -q .; then
            log_info "Stopping container: $container"
            docker stop "$container" 2>/dev/null || true
            docker rm -f "$container" 2>/dev/null || true
        fi
    done
    
    # Then try to kill any remaining process on the port
    if [[ "$OS_TYPE" == "macos" ]]; then
        local pid=$(lsof -ti :$port 2>/dev/null)
        [[ -n "$pid" ]] && kill -9 $pid 2>/dev/null || true
    else
        local pid=$(ss -tlnp 2>/dev/null | grep ":${port} " | grep -oP 'pid=\K\d+' | head -1)
        [[ -n "$pid" ]] && kill -9 $pid 2>/dev/null || true
        fuser -k ${port}/tcp 2>/dev/null || true
    fi
    sleep 1
}

check_ports_avail() {
    local ports=("$@") blocked=()
    for p in "${ports[@]}"; do
        check_port "$p" || { blocked+=("$p"); log_warn "Port $p is in use."; }
    done
    if [[ ${#blocked[@]} -gt 0 ]]; then
        echo ""
        echo "  Options:"
        echo "    1) Kill processes and continue"
        echo "    2) Continue anyway (may fail)"
        echo "    3) Cancel"
        echo ""
        read -r -p "  Select [1-3]: " choice < /dev/tty
        case $choice in
            1)
                for p in "${blocked[@]}"; do kill_port_process "$p"; done
                for p in "${blocked[@]}"; do
                    check_port "$p" || { log_error "Failed to free port $p"; exit 1; }
                done
                log_success "Ports freed successfully"
                ;;
            2) log_warn "Continuing with busy ports..." ;;
            3) log_info "Cancelled"; exit 0 ;;
            *) log_error "Invalid choice"; exit 1 ;;
        esac
    fi
}

#=============================================================================
# SHARED CADDY
#=============================================================================
check_master_exists() { [[ -d "$MASTER_INSTALL_DIR" && -f "$MASTER_INSTALL_DIR/.env" ]]; }
check_node_exists() { [[ -d "$NODE_INSTALL_DIR" && -f "$NODE_INSTALL_DIR/.env" ]]; }
check_gateway_exists() { [[ -d "$GATEWAY_DIR" && -f "$GATEWAY_DIR/docker-compose.yml" ]]; }

fix_iptables_conflict() {
    # Check for iptables/nftables conflict (common on Debian/Ubuntu)
    if command -v iptables &>/dev/null && command -v update-alternatives &>/dev/null; then
        local current_iptables
        current_iptables=$(update-alternatives --query iptables 2>/dev/null | grep "Value:" | awk '{print $2}')
        
        if [[ "$current_iptables" == *"nft"* ]]; then
            log_warn "Detected nftables mode, switching to iptables-legacy for Docker compatibility..."
            update-alternatives --set iptables /usr/sbin/iptables-legacy 2>/dev/null || true
            update-alternatives --set ip6tables /usr/sbin/ip6tables-legacy 2>/dev/null || true
            log_success "Switched to iptables-legacy"
        fi
    fi
}

create_docker_networks() {
    log_info "Creating Docker networks..."
    
    # Check if networks already exist
    if docker network inspect sui-master-net &>/dev/null; then
        log_info "Network sui-master-net already exists"
    else
        if docker network create sui-master-net 2>/dev/null; then
            log_success "Created network: sui-master-net"
        else
            log_error "Failed to create network: sui-master-net"
            exit 1
        fi
    fi
    
    if docker network inspect sui-node-net &>/dev/null; then
        log_info "Network sui-node-net already exists"
    else
        if docker network create sui-node-net 2>/dev/null; then
            log_success "Created network: sui-node-net"
        else
            log_error "Failed to create network: sui-node-net"
            exit 1
        fi
    fi
}

setup_shared_gateway() {
    log_step "Setting up Shared Gateway (Caddy)..."
    mkdir -p "$GATEWAY_DIR"
    cat > "$GATEWAY_DIR/docker-compose.yml" << 'EOF'
services:
  gateway:
    image: caddy:2-alpine
    container_name: sui-gateway
    restart: unless-stopped
    ports:
      - "80:80"
      - "443:443"
      - "443:443/udp"
    volumes:
      - ./Caddyfile:/etc/caddy/Caddyfile:ro
      - caddy-data:/data
      - caddy-config:/config
      - caddy-logs:/var/log/caddy
    networks:
      - sui-master-net
      - sui-node-net
volumes:
  caddy-data:
  caddy-config:
  caddy-logs:
networks:
  sui-master-net:
    external: true
  sui-node-net:
    external: true
EOF
    echo -e "  ${CHECK} Gateway docker-compose created"
}

generate_shared_caddyfile() {
    log_info "Generating shared Caddyfile..."
    local caddyfile="$GATEWAY_DIR/Caddyfile"
    local m_domain="" n_domain="" n_path_prefix="" acme_email="${email:-admin@example.com}"
    
    if [[ -f "$MASTER_INSTALL_DIR/.env" ]]; then
        m_domain=$(grep '^MASTER_DOMAIN=' "$MASTER_INSTALL_DIR/.env" | cut -d= -f2)
        acme_email=$(grep '^ACME_EMAIL=' "$MASTER_INSTALL_DIR/.env" | cut -d= -f2)
    fi
    if [[ -f "$NODE_INSTALL_DIR/.env" ]]; then
        n_domain=$(grep '^NODE_DOMAIN=' "$NODE_INSTALL_DIR/.env" | cut -d= -f2)
        n_path_prefix=$(grep '^PATH_PREFIX=' "$NODE_INSTALL_DIR/.env" | cut -d= -f2)
    fi
    
    cat > "$caddyfile" << EOF
{
    email ${acme_email}
}
EOF
    
    if [[ -n "$m_domain" ]]; then
        cat >> "$caddyfile" << EOF

${m_domain} {
    reverse_proxy sui-master:5000
    header Strict-Transport-Security "max-age=31536000; includeSubDomains; preload"
    header X-Frame-Options "DENY"
    header X-Content-Type-Options "nosniff"
    log {
        output file /var/log/caddy/master.log
    }
}
EOF
        echo -e "  ${CHECK} Added Master: ${m_domain}"
    fi
    
    if [[ -n "$n_domain" && -n "$n_path_prefix" ]]; then
        cat >> "$caddyfile" << EOF

${n_domain} {
    handle /${n_path_prefix}/api/v1/* {
        reverse_proxy sui-agent:5001
    }
    handle /adguard/* {
        uri strip_prefix /adguard
        reverse_proxy sui-adguard:3000
    }
    handle /health {
        reverse_proxy sui-agent:5001
    }
    handle {
        respond "Welcome" 200
    }
    header Strict-Transport-Security "max-age=31536000"
    header -Server
    log {
        output file /var/log/caddy/node.log
    }
}
EOF
        echo -e "  ${CHECK} Added Node: ${n_domain}"
    fi
}

start_shared_gateway() {
    log_info "Starting shared gateway..."
    cd "$GATEWAY_DIR"
    if ! docker compose up -d; then
        log_error "Failed to start gateway. Check docker compose logs:"
        docker compose logs --tail=20
        exit 1
    fi
}

reload_shared_gateway() {
    log_info "Reloading gateway configuration..."
    docker exec sui-gateway caddy reload --config /etc/caddy/Caddyfile 2>/dev/null || \
        (cd "$GATEWAY_DIR" && docker compose restart) || true
}

generate_adguard_config() {
    local conf_file="$NODE_INSTALL_DIR/config/adguard/conf/AdGuardHome.yaml"
    mkdir -p "$(dirname "$conf_file")"
    [[ -f "$conf_file" ]] && return
    log_info "Generating AdGuard Config..."
    cat > "$conf_file" << EOF
bind_host: 0.0.0.0
bind_port: 3000
auth_attempts: 5
block_auth_min: 15
dns:
  bind_hosts: [0.0.0.0]
  port: 53
EOF
    log_info "AdGuard config created. Setup Wizard available at /adguard/"
}


#=============================================================================
# CONFIGURATION
#=============================================================================
load_env_defaults() {
    local env_file="$1"
    if [[ -f "$env_file" ]]; then
        log_info "Reading defaults from existing .env..."
        local s=$(grep '^CLUSTER_SECRET=' "$env_file" | cut -d= -f2)
        local d=$(grep '^MASTER_DOMAIN=' "$env_file" | cut -d= -f2)
        local nd=$(grep '^NODE_DOMAIN=' "$env_file" | cut -d= -f2)
        local e=$(grep '^ACME_EMAIL=' "$env_file" | cut -d= -f2)
        [[ -n "$s" ]] && secret="$s" || true
        [[ -n "$d" ]] && domain="$d" || true
        [[ -n "$nd" ]] && domain="$nd" || true
        [[ -n "$e" ]] && email="$e" || true
    fi
}

collect_inputs() {
    log_step "Configuration Setup"
    echo ""

    if [[ -n "$CLI_MODE" ]]; then
        INSTALL_MODE="$CLI_MODE"
    else
        echo "  Select installation mode:"
        echo "    1) Master (Control Panel)"
        echo "    2) Node (Proxy Agent)"
        read -r -p "  Enter choice [1-2]: " mode_choice < /dev/tty
        case $mode_choice in
            1) INSTALL_MODE="master" ;;
            2) INSTALL_MODE="node" ;;
            *) log_error "Invalid choice"; exit 1 ;;
        esac
    fi
    
    local target_dir="$MASTER_INSTALL_DIR"
    [[ "$INSTALL_MODE" == "node" ]] && target_dir="$NODE_INSTALL_DIR" || true
    load_env_defaults "$target_dir/.env"

    # Check for existing installation
    if [[ -n "$domain" && "$domain" != "localhost" ]]; then
        echo ""
        log_info "Existing installation detected:"
        echo -e "  Domain: ${BOLD}${domain}${NC}"
        echo -e "  Email:  ${BOLD}${email}${NC}"
        echo ""
        if confirm "Keep existing settings?" "y"; then
            # Keep existing settings, just confirm
            echo ""
            log_info "Summary:"
            echo -e "  Mode:   ${BOLD}${INSTALL_MODE^^}${NC}"
            echo -e "  Domain: ${BOLD}${domain}${NC}"
            echo -e "  Email:  ${BOLD}${email}${NC}"
            echo ""
            confirm "Proceed with reinstall?" "y" || exit 0
            return
        fi
        echo ""
        log_info "Enter new configuration:"
    else
        echo ""
        log_info "Configuration (Press Enter for default)"
    fi
    
    local d_domain="${domain:-localhost}"
    read -r -p "  Enter Domain [${d_domain}]: " in_domain < /dev/tty
    domain=${in_domain:-$d_domain}
    domain=$(echo "$domain" | sed 's|https://||g' | sed 's|http://||g' | tr -d '/')

    local d_email="${email:-admin@example.com}"
    read -r -p "  Enter Email [${d_email}]: " in_email < /dev/tty
    email=${in_email:-$d_email}

    if [[ "$INSTALL_MODE" == "node" ]]; then
        local p_secret="Enter Cluster Secret"
        [[ -n "$secret" ]] && p_secret="$p_secret [found existing]" || true
        while [[ -z "$secret" ]]; do
            read -r -p "  $p_secret: " in_secret < /dev/tty
            [[ -n "$in_secret" ]] && secret="$in_secret" || true
            [[ -z "$secret" ]] && log_error "Secret is required!" || true
        done
        log_info "AdGuard Home will be configured with: User: admin | Pass: sui-solo"
    else
        if [[ -z "$secret" ]]; then
            if command -v openssl &>/dev/null; then
                secret=$(openssl rand -hex 32)
            else
                secret=$(head -c 64 /dev/urandom | sha256sum | cut -d' ' -f1)
            fi
        fi
    fi

    echo ""
    log_info "Summary:"
    echo -e "  Mode:   ${BOLD}${INSTALL_MODE^^}${NC}"
    echo -e "  Domain: ${BOLD}${domain}${NC}"
    echo -e "  Email:  ${BOLD}${email}${NC}"
    echo ""
    confirm "Proceed?" "y" || exit 0
}

#=============================================================================
# INSTALL
#=============================================================================
install_master() {
    log_step "Installing Master..."
    
    if [[ -d "$MASTER_INSTALL_DIR" ]]; then
        log_warn "Existing Master installation detected!"
        # Load existing settings
        local existing_domain=$(grep '^MASTER_DOMAIN=' "$MASTER_INSTALL_DIR/.env" 2>/dev/null | cut -d= -f2)
        local existing_email=$(grep '^ACME_EMAIL=' "$MASTER_INSTALL_DIR/.env" 2>/dev/null | cut -d= -f2)
        local existing_secret=$(grep '^CLUSTER_SECRET=' "$MASTER_INSTALL_DIR/.env" 2>/dev/null | cut -d= -f2)
        echo ""
        echo "    1) Quick reinstall (keep domain: ${existing_domain})"
        echo "    2) Overwrite (update domain/settings)"
        echo "    3) Cancel"
        read -r -p "  Select [1-3]: " choice < /dev/tty
        case $choice in
            1) 
                log_info "Quick reinstall with existing settings..."
                domain="${existing_domain}"
                email="${existing_email}"
                secret="${existing_secret}"
                log_info "Stopping existing containers..."
                (cd "$MASTER_INSTALL_DIR" && docker compose down 2>/dev/null) || true
                [[ -d "$GATEWAY_DIR" ]] && (cd "$GATEWAY_DIR" && docker compose down 2>/dev/null) || true
                ;;
            2) 
                log_info "Stopping existing containers..."
                (cd "$MASTER_INSTALL_DIR" && docker compose down 2>/dev/null) || true
                [[ -d "$GATEWAY_DIR" ]] && (cd "$GATEWAY_DIR" && docker compose down 2>/dev/null) || true
                ;;
            *) log_info "Cancelled"; exit 0 ;;
        esac
    fi
    
    create_docker_networks
    check_gateway_exists || check_node_exists || check_ports_avail 80 443

    mkdir -p "$MASTER_INSTALL_DIR"
    cp -r "${SCRIPT_DIR}/master/"* "$MASTER_INSTALL_DIR/"
    
    cat > "$MASTER_INSTALL_DIR/docker-compose.yml" << 'EOF'
services:
  app:
    build: .
    container_name: sui-master
    restart: unless-stopped
    expose: ["5000"]
    environment:
      - CLUSTER_SECRET=${CLUSTER_SECRET}
      - DATA_DIR=/data
    volumes: [app-data:/data]
    networks: [sui-master-net]
volumes:
  app-data:
networks:
  sui-master-net:
    external: true
EOF
    
    cat > "$MASTER_INSTALL_DIR/.env" << EOF
CLUSTER_SECRET=${secret}
MASTER_DOMAIN=${domain}
ACME_EMAIL=${email}
EOF

    cd "$MASTER_INSTALL_DIR"
    if ! docker compose up -d --build; then
        log_error "Failed to start Master containers"
        docker compose logs --tail=20
        exit 1
    fi
    
    # Wait for containers to be healthy
    log_info "Waiting for Master containers to be ready..."
    sleep 3
    local retries=10
    while [[ $retries -gt 0 ]]; do
        if docker ps | grep -q "sui-master.*Up"; then
            log_success "Master container is running"
            break
        fi
        sleep 2
        ((retries--))
    done
    
    if [[ $retries -eq 0 ]]; then
        log_warn "Master container may not be fully ready, check logs: docker logs sui-master"
    fi
    
    # Only start gateway in standalone master mode (not in --both mode)
    if [[ "$SHARED_CADDY_MODE" != "true" ]]; then
        setup_shared_gateway
        generate_shared_caddyfile
        start_shared_gateway
    fi
    
    echo ""
    log_success "Master Installed!"
    echo ""
    echo -e "${MAGENTA}╔════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${MAGENTA}║${NC}  ${BOLD}CLUSTER SECRET (Save this! Required for node installation)${NC}  ${MAGENTA}║${NC}"
    echo -e "${MAGENTA}╠════════════════════════════════════════════════════════════════╣${NC}"
    echo -e "${MAGENTA}║${NC}  ${YELLOW}${secret}${NC}  ${MAGENTA}║${NC}"
    echo -e "${MAGENTA}╚════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "  ${ARROW} Control Panel: ${CYAN}https://${domain}${NC}"
    echo ""
}

install_node() {
    log_step "Installing Node..."
    
    if [[ -d "$NODE_INSTALL_DIR" ]]; then
        log_warn "Existing Node installation detected!"
        # Load existing settings
        local existing_domain=$(grep '^NODE_DOMAIN=' "$NODE_INSTALL_DIR/.env" 2>/dev/null | cut -d= -f2)
        local existing_email=$(grep '^ACME_EMAIL=' "$NODE_INSTALL_DIR/.env" 2>/dev/null | cut -d= -f2)
        local existing_secret=$(grep '^CLUSTER_SECRET=' "$NODE_INSTALL_DIR/.env" 2>/dev/null | cut -d= -f2)
        echo ""
        echo "    1) Quick reinstall (keep domain: ${existing_domain})"
        echo "    2) Overwrite (update domain/settings)"
        echo "    3) Cancel"
        read -r -p "  Select [1-3]: " choice < /dev/tty
        case $choice in
            1) 
                log_info "Quick reinstall with existing settings..."
                domain="${existing_domain}"
                email="${existing_email}"
                secret="${existing_secret}"
                log_info "Stopping existing containers..."
                (cd "$NODE_INSTALL_DIR" && docker compose down 2>/dev/null) || true
                ;;
            2) 
                log_info "Stopping existing containers..."
                (cd "$NODE_INSTALL_DIR" && docker compose down 2>/dev/null) || true
                ;;
            *) log_info "Cancelled"; exit 0 ;;
        esac
    fi
    
    create_docker_networks
    
    # Check ports only if not in shared mode
    if [[ "$SHARED_CADDY_MODE" != "true" ]]; then
        check_ports_avail 80 443 53
    else
        check_ports_avail 53
    fi
    
    local path_prefix=$(echo -n "${SALT}:${secret}" | sha256sum | cut -c1-16)
    
    mkdir -p "$NODE_INSTALL_DIR/config/singbox" "$NODE_INSTALL_DIR/config/adguard/conf" "$NODE_INSTALL_DIR/config/caddy"
    cp -r "${SCRIPT_DIR}/node/"* "$NODE_INSTALL_DIR/"
    
    # Generate docker-compose.yml based on mode
    if [[ "$SHARED_CADDY_MODE" == "true" ]]; then
        # Shared mode: sing-box handles 443 with SNI routing, forwards master traffic to caddy
        log_info "Generating docker-compose for SNI routing mode..."
        cat > "$NODE_INSTALL_DIR/docker-compose.yml" << 'EOF'
services:
  singbox:
    image: ghcr.io/sagernet/sing-box:latest
    container_name: sui-singbox
    restart: unless-stopped
    ports:
      - "80:80/tcp"       # ACME HTTP-01 Challenge
      - "443:443/tcp"     # SNI routing (VLESS + Master)
      - "50200-50300:50200-50300/udp"  # Hysteria2 port hopping
    volumes:
      - ./config/singbox:/etc/sing-box
    command: ["run", "-c", "/etc/sing-box/config.json"]
    networks:
      - sui-node-net
      - sui-master-net
    cap_add: [NET_ADMIN]
    
  caddy:
    image: caddy:2-alpine
    container_name: sui-caddy
    restart: unless-stopped
    expose: ["443"]
    volumes:
      - ./config/caddy/Caddyfile:/etc/caddy/Caddyfile:ro
      - ./config/caddy/certs:/etc/caddy/certs:ro
      - ./config/caddy/logs:/var/log/caddy
    networks:
      - sui-node-net
      - sui-master-net
    security_opt:
      - seccomp:unconfined
    
  agent:
    build: .
    container_name: sui-agent
    restart: unless-stopped
    expose: ["5001"]
    environment:
      - CLUSTER_SECRET=${CLUSTER_SECRET}
      - NODE_DOMAIN=${NODE_DOMAIN}
      - CONFIG_DIR=/config
    volumes:
      - ./config:/config
      - /var/run/docker.sock:/var/run/docker.sock:ro
    networks: [sui-node-net]
    security_opt: [no-new-privileges:true]
    
  adguard:
    image: adguard/adguardhome:latest
    container_name: sui-adguard
    restart: unless-stopped
    volumes:
      - ./config/adguard/work:/opt/adguardhome/work
      - ./config/adguard/conf:/opt/adguardhome/conf
    networks: [sui-node-net]
    ports: ["53:53/tcp", "53:53/udp"]
    cap_add: [NET_BIND_SERVICE, CHOWN, SETUID, SETGID]

networks:
  sui-node-net:
    external: true
  sui-master-net:
    external: true
EOF
    else
        # Standalone mode: sing-box handles 80/443 directly
        log_info "Generating docker-compose for standalone mode..."
        cat > "$NODE_INSTALL_DIR/docker-compose.yml" << 'EOF'
services:
  singbox:
    image: ghcr.io/sagernet/sing-box:latest
    container_name: sui-singbox
    restart: unless-stopped
    ports:
      - "80:80/tcp"       # ACME HTTP-01 Challenge
      - "443:443/tcp"     # VLESS + TLS
      - "50200-50300:50200-50300/udp"  # Hysteria2 port hopping
    volumes:
      - ./config/singbox:/etc/sing-box
    command: ["run", "-c", "/etc/sing-box/config.json"]
    networks: [sui-node-net]
    cap_add: [NET_ADMIN]
    
  caddy:
    image: caddy:2-alpine
    container_name: sui-caddy
    restart: unless-stopped
    expose: ["80"]
    volumes:
      - ./config/caddy/Caddyfile:/etc/caddy/Caddyfile:ro
      - ./config/caddy/site:/usr/share/caddy:ro
      - ./config/caddy/logs:/var/log/caddy
    networks: [sui-node-net]
    security_opt:
      - seccomp:unconfined
    
  agent:
    build: .
    container_name: sui-agent
    restart: unless-stopped
    expose: ["5001"]
    environment:
      - CLUSTER_SECRET=${CLUSTER_SECRET}
      - NODE_DOMAIN=${NODE_DOMAIN}
      - CONFIG_DIR=/config
    volumes:
      - ./config:/config
      - /var/run/docker.sock:/var/run/docker.sock:ro
    networks: [sui-node-net]
    security_opt: [no-new-privileges:true]
    
  adguard:
    image: adguard/adguardhome:latest
    container_name: sui-adguard
    restart: unless-stopped
    volumes:
      - ./config/adguard/work:/opt/adguardhome/work
      - ./config/adguard/conf:/opt/adguardhome/conf
    networks: [sui-node-net]
    ports: ["53:53/tcp", "53:53/udp"]
    cap_add: [NET_BIND_SERVICE, CHOWN, SETUID, SETGID]

networks:
  sui-node-net:
    external: true
EOF
    fi

    # Generate UUID and password for proxies (or load existing)
    local vless_uuid hy2_password
    if [[ -f "$NODE_INSTALL_DIR/.env" ]]; then
        vless_uuid=$(grep '^VLESS_UUID=' "$NODE_INSTALL_DIR/.env" 2>/dev/null | cut -d= -f2)
        hy2_password=$(grep '^HY2_PASSWORD=' "$NODE_INSTALL_DIR/.env" 2>/dev/null | cut -d= -f2)
    fi
    [[ -z "$vless_uuid" ]] && vless_uuid=$(cat /proc/sys/kernel/random/uuid 2>/dev/null || openssl rand -hex 16 | sed 's/\(..\)\(..\)\(..\)\(..\)\(..\)\(..\)\(..\)\(..\)/\1\2\3\4-\5\6-\7\8-/')
    [[ -z "$hy2_password" ]] && hy2_password=$(openssl rand -hex 16 2>/dev/null || head -c 32 /dev/urandom | sha256sum | cut -c1-32)
    
    # VLESS always on 443
    local vless_port=443
    
    # Generate sing-box config based on mode
    log_info "Generating Sing-box configuration..."
    
    if [[ "$SHARED_CADDY_MODE" == "true" ]]; then
        # SNI routing mode: route master domain to caddy, handle node domain as VLESS
        log_info "Using SNI routing for master domain: ${master_domain}"
        cat > "$NODE_INSTALL_DIR/config/singbox/config.json" << SBEOF
{
  "log": {
    "level": "info",
    "timestamp": true
  },
  "inbounds": [
    {
      "type": "tls",
      "tag": "tls-in",
      "listen": "::",
      "listen_port": 443,
      "sni": {
        "${master_domain}": "master-tls",
        "": "vless-tls"
      }
    },
    {
      "type": "vless",
      "tag": "vless-in",
      "listen": "127.0.0.1",
      "listen_port": 10443,
      "users": [
        {
          "uuid": "${vless_uuid}",
          "flow": "xtls-rprx-vision"
        }
      ],
      "tls": {
        "enabled": true,
        "server_name": "${domain}",
        "acme": {
          "domain": ["${domain}"],
          "email": "${email}",
          "provider": "letsencrypt",
          "data_directory": "/etc/sing-box/acme"
        }
      }
    },
    {
      "type": "hysteria2",
      "tag": "hy2-in",
      "listen": "::",
      "listen_port": 50200,
      "users": [
        {
          "password": "${hy2_password}"
        }
      ],
      "tls": {
        "enabled": true,
        "server_name": "${domain}",
        "acme": {
          "domain": ["${domain}"],
          "email": "${email}",
          "provider": "letsencrypt",
          "data_directory": "/etc/sing-box/acme"
        }
      },
      "up_mbps": 100,
      "down_mbps": 100
    }
  ],
  "outbounds": [
    {
      "type": "direct",
      "tag": "direct"
    },
    {
      "type": "direct",
      "tag": "master-tls",
      "override_address": "sui-caddy",
      "override_port": 443
    },
    {
      "type": "direct",
      "tag": "vless-tls",
      "override_address": "127.0.0.1",
      "override_port": 10443
    }
  ],
  "route": {
    "rules": [],
    "final": "direct"
  }
}
SBEOF
    else
        # Standalone mode: simple VLESS + Hysteria2
        cat > "$NODE_INSTALL_DIR/config/singbox/config.json" << SBEOF
{
  "log": {
    "level": "info",
    "timestamp": true
  },
  "inbounds": [
    {
      "type": "vless",
      "tag": "vless-in",
      "listen": "::",
      "listen_port": 443,
      "users": [
        {
          "uuid": "${vless_uuid}",
          "flow": "xtls-rprx-vision"
        }
      ],
      "tls": {
        "enabled": true,
        "server_name": "${domain}",
        "acme": {
          "domain": ["${domain}"],
          "email": "${email}",
          "provider": "letsencrypt",
          "data_directory": "/etc/sing-box/acme"
        }
      }
    },
    {
      "type": "hysteria2",
      "tag": "hy2-in",
      "listen": "::",
      "listen_port": 50200,
      "users": [
        {
          "password": "${hy2_password}"
        }
      ],
      "tls": {
        "enabled": true,
        "server_name": "${domain}",
        "acme": {
          "domain": ["${domain}"],
          "email": "${email}",
          "provider": "letsencrypt",
          "data_directory": "/etc/sing-box/acme"
        }
      },
      "up_mbps": 100,
      "down_mbps": 100
    }
  ],
  "outbounds": [
    {
      "type": "direct",
      "tag": "direct"
    }
  ],
  "route": {
    "rules": [],
    "final": "direct"
  }
}
SBEOF
    fi
    
    # Generate Caddy configuration based on mode
    log_info "Generating Caddy configuration..."
    mkdir -p "$NODE_INSTALL_DIR/config/caddy/certs"
    
    if [[ "$SHARED_CADDY_MODE" == "true" ]]; then
        # SNI mode: Caddy receives TLS passthrough from sing-box for master domain
        # It needs to terminate TLS and reverse proxy to master
        cat > "$NODE_INSTALL_DIR/config/caddy/Caddyfile" << CADDYEOF
# Caddy handles master domain (TLS passthrough from sing-box)
{
    email ${email}
    acme_ca https://acme-v02.api.letsencrypt.org/directory
}

${master_domain} {
    reverse_proxy sui-master:5000
    
    header {
        Strict-Transport-Security "max-age=31536000; includeSubDomains"
        X-Frame-Options "DENY"
        X-Content-Type-Options "nosniff"
        -Server
    }
    
    log {
        output file /var/log/caddy/master.log
        level ERROR
    }
}
CADDYEOF
    else
        # Standalone mode: Caddy handles internal HTTP only
        cat > "$NODE_INSTALL_DIR/config/caddy/Caddyfile" << CADDYEOF
# Caddy runs on internal Docker network only (HTTP)
:80 {
    # Hidden API path
    handle /${path_prefix}/* {
        reverse_proxy agent:5001
    }
    
    # AdGuard Home Web UI
    handle /adguard/* {
        uri strip_prefix /adguard
        reverse_proxy adguard:3000
    }
    
    # Camouflage website
    handle {
        respond / \`<!DOCTYPE html>
<html>
<head>
    <title>Welcome</title>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <style>
        body { 
            font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
            max-width: 800px; 
            margin: 50px auto; 
            padding: 20px;
            background: #f5f5f5;
        }
        .container {
            background: white;
            padding: 40px;
            border-radius: 8px;
            box-shadow: 0 2px 4px rgba(0,0,0,0.1);
        }
        h1 { color: #333; margin-bottom: 20px; }
        p { color: #666; line-height: 1.6; }
    </style>
</head>
<body>
    <div class="container">
        <h1>Welcome to ${domain}</h1>
        <p>This is a personal website.</p>
    </div>
</body>
</html>\` 200
    }
    
    header {
        X-Frame-Options "DENY"
        X-Content-Type-Options "nosniff"
        -Server
    }
    
    log {
        output file /var/log/caddy/access.log
        level ERROR
    }
}
CADDYEOF
    fi
    
    generate_adguard_config
    
    cat > "$NODE_INSTALL_DIR/.env" << EOF
CLUSTER_SECRET=${secret}
NODE_DOMAIN=${domain}
ACME_EMAIL=${email}
PATH_PREFIX=${path_prefix}
VLESS_UUID=${vless_uuid}
VLESS_PORT=${vless_port}
HY2_PASSWORD=${hy2_password}
HY2_PORT_START=50200
HY2_PORT_END=50300
EOF

    cd "$NODE_INSTALL_DIR"
    if ! docker compose up -d --build; then
        log_error "Failed to start Node containers"
        docker compose logs --tail=20
        exit 1
    fi
    
    # Wait for containers to be healthy
    log_info "Waiting for Node containers to be ready..."
    sleep 3
    local retries=10
    while [[ $retries -gt 0 ]]; do
        local running_count=0
        docker ps | grep -q "sui-agent.*Up" && ((running_count++))
        docker ps | grep -q "sui-singbox.*Up" && ((running_count++))
        docker ps | grep -q "sui-adguard.*Up" && ((running_count++))
        
        if [[ $running_count -eq 3 ]]; then
            log_success "All Node containers are running"
            break
        fi
        sleep 2
        ((retries--))
    done
    
    if [[ $retries -eq 0 ]]; then
        log_warn "Some containers may not be fully ready. Check status:"
        docker ps -a | grep "sui-"
        log_info "Check logs: docker logs sui-agent / sui-singbox / sui-adguard"
    fi
    
    # Wait for ACME certificate (first time may take 1-2 minutes)
    log_info "Waiting for ACME certificate issuance..."
    log_warn "This may take 1-2 minutes on first installation..."
    sleep 10
    
    # Check if certificate was issued
    if [[ -d "$NODE_INSTALL_DIR/config/acme" ]]; then
        log_success "ACME directory created"
    fi
    
    # Generate proxy links for display (use correct port based on mode)
    local vless_link="vless://${vless_uuid}@${domain}:${vless_port}?encryption=none&flow=xtls-rprx-vision&security=tls&sni=${domain}&alpn=h2,http/1.1&type=tcp#${domain}-VLESS"
    local hy2_link="hysteria2://${hy2_password}@${domain}:50200?sni=${domain}&alpn=h3#${domain}-Hysteria2"
    
    echo ""
    log_success "Node Installed!"
    echo ""
    echo -e "  ${ARROW} Node Domain:  ${CYAN}${domain}${NC}"
    echo -e "  ${ARROW} Hidden Path:  ${CYAN}/${path_prefix}${NC}"
    echo ""
    echo -e "${MAGENTA}╔════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${MAGENTA}║${NC}  ${BOLD}PROXY CONFIGURATIONS${NC}                                         ${MAGENTA}║${NC}"
    echo -e "${MAGENTA}╠════════════════════════════════════════════════════════════════╣${NC}"
    echo -e "${MAGENTA}║${NC}  ${CYAN}VLESS + XTLS-Vision + TLS (Port ${vless_port})${NC}                         ${MAGENTA}║${NC}"
    echo -e "${MAGENTA}║${NC}  UUID: ${YELLOW}${vless_uuid}${NC}              ${MAGENTA}║${NC}"
    echo -e "${MAGENTA}╠════════════════════════════════════════════════════════════════╣${NC}"
    echo -e "${MAGENTA}║${NC}  ${CYAN}Hysteria2 (Port 50200-50300 UDP)${NC}                             ${MAGENTA}║${NC}"
    echo -e "${MAGENTA}║${NC}  Password: ${YELLOW}${hy2_password}${NC}                        ${MAGENTA}║${NC}"
    echo -e "${MAGENTA}╚════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${BOLD}Share Links (copy to client):${NC}"
    echo -e "${GREEN}VLESS:${NC}"
    echo -e "${vless_link}"
    echo ""
    echo -e "${GREEN}Hysteria2:${NC}"
    echo -e "${hy2_link}"
    echo ""
    echo -e "${YELLOW}Note:${NC} ACME certificate will be auto-issued on first connection."
    echo -e "      Check logs if needed: ${CYAN}docker logs sui-singbox${NC}"
    echo ""
    
    # Offer firewall configuration
    configure_firewall_prompt
}

#=============================================================================
# FIREWALL CONFIGURATION
#=============================================================================
configure_firewall_prompt() {
    echo ""
    if confirm "Configure firewall to block unnecessary ports? (Recommended)" "y"; then
        configure_firewall
    else
        log_warn "Skipping firewall configuration"
        echo -e "  ${YELLOW}Note: AdGuard Home port 3000 is exposed. Consider blocking it manually.${NC}"
    fi
}

configure_firewall() {
    log_step "Configuring firewall..."
    
    # Default ports to allow
    local default_ports="22 80 443 53"
    local default_ranges="50200-50300"
    
    echo ""
    echo -e "  ${CYAN}Default allowed ports:${NC}"
    echo -e "    22         - SSH"
    echo -e "    80         - HTTP (ACME Challenge)"
    echo -e "    443        - HTTPS (VLESS / Master Panel)"
    echo -e "    53         - DNS (AdGuard)"
    echo -e "    50200-50300- Hysteria2 UDP (port hopping)"
    echo ""
    echo -e "  ${YELLOW}Ports that will be BLOCKED:${NC}"
    echo -e "    3000       - AdGuard Home Web UI (access via hidden path)"
    echo ""
    
    read -r -p "  Additional ports to allow (space-separated, e.g., '8080 9000-9100'): " extra_ports < /dev/tty
    
    local all_ports="$default_ports $extra_ports"
    local all_ranges="$default_ranges"
    
    # Detect firewall tool
    if command -v ufw &>/dev/null; then
        configure_ufw "$all_ports" "$all_ranges"
    elif command -v firewall-cmd &>/dev/null; then
        configure_firewalld "$all_ports" "$all_ranges"
    elif command -v iptables &>/dev/null; then
        configure_iptables "$all_ports" "$all_ranges"
    else
        log_warn "No supported firewall tool found (ufw/firewalld/iptables)"
        log_info "Please configure firewall manually"
        return 1
    fi
    
    log_success "Firewall configured!"
}

configure_ufw() {
    local ports="$1"
    local ranges="$2"
    log_info "Configuring UFW..."
    
    # Reset UFW
    ufw --force reset >/dev/null 2>&1
    
    # Default deny incoming
    ufw default deny incoming >/dev/null 2>&1
    ufw default allow outgoing >/dev/null 2>&1
    
    # Allow specified ports
    for port in $ports; do
        if [[ "$port" == *-* ]]; then
            # Port range
            ufw allow "$port/tcp" >/dev/null 2>&1
            ufw allow "$port/udp" >/dev/null 2>&1
        else
            ufw allow "$port" >/dev/null 2>&1
        fi
        echo -e "    ${CHECK} Allowed port $port"
    done
    
    # Allow port ranges (for Hysteria2)
    for range in $ranges; do
        ufw allow "$range/udp" >/dev/null 2>&1
        echo -e "    ${CHECK} Allowed UDP range $range"
    done
    
    # Enable UFW
    ufw --force enable >/dev/null 2>&1
    
    echo ""
    log_info "UFW status:"
    ufw status numbered
}

configure_firewalld() {
    local ports="$1"
    log_info "Configuring firewalld..."
    
    # Start firewalld if not running
    systemctl start firewalld 2>/dev/null || true
    systemctl enable firewalld 2>/dev/null || true
    
    # Remove all existing ports from public zone
    for port in $(firewall-cmd --zone=public --list-ports 2>/dev/null); do
        firewall-cmd --zone=public --remove-port="$port" --permanent >/dev/null 2>&1
    done
    
    # Add specified ports
    for port in $ports; do
        if [[ "$port" == *-* ]]; then
            firewall-cmd --zone=public --add-port="${port}/tcp" --permanent >/dev/null 2>&1
            firewall-cmd --zone=public --add-port="${port}/udp" --permanent >/dev/null 2>&1
        else
            firewall-cmd --zone=public --add-port="${port}/tcp" --permanent >/dev/null 2>&1
            firewall-cmd --zone=public --add-port="${port}/udp" --permanent >/dev/null 2>&1
        fi
        echo -e "    ${CHECK} Allowed port $port"
    done
    
    # Reload firewalld
    firewall-cmd --reload >/dev/null 2>&1
    
    echo ""
    log_info "Firewalld status:"
    firewall-cmd --list-all
}

configure_iptables() {
    local ports="$1"
    log_info "Configuring iptables..."
    
    # Flush existing rules
    iptables -F INPUT 2>/dev/null || true
    
    # Default policies
    iptables -P INPUT DROP
    iptables -P FORWARD DROP
    iptables -P OUTPUT ACCEPT
    
    # Allow loopback
    iptables -A INPUT -i lo -j ACCEPT
    
    # Allow established connections
    iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
    
    # Allow specified ports
    for port in $ports; do
        if [[ "$port" == *-* ]]; then
            iptables -A INPUT -p tcp --dport "$port" -j ACCEPT
            iptables -A INPUT -p udp --dport "$port" -j ACCEPT
        else
            iptables -A INPUT -p tcp --dport "$port" -j ACCEPT
            iptables -A INPUT -p udp --dport "$port" -j ACCEPT
        fi
        echo -e "    ${CHECK} Allowed port $port"
    done
    
    # Save rules
    if command -v iptables-save &>/dev/null; then
        mkdir -p /etc/iptables
        iptables-save > /etc/iptables/rules.v4 2>/dev/null || true
    fi
    
    echo ""
    log_info "iptables rules applied"
}

#=============================================================================
# UNINSTALL
#=============================================================================
uninstall() {
    print_banner
    log_step "Uninstall ${PROJECT_NAME}"
    echo ""
    echo "  Select component to uninstall:"
    echo "    1) Master only"
    echo "    2) Node only"
    echo "    3) Everything"
    echo "    4) Cancel"
    echo ""
    read -r -p "  [1-4]: " choice < /dev/tty
    
    case $choice in
        1)
            if [[ -d "$MASTER_INSTALL_DIR" ]]; then
                confirm "Remove Master and all its data?" "n" || exit 0
                log_info "Stopping existing containers..."
                (cd "$MASTER_INSTALL_DIR" && docker compose down -v 2>/dev/null) || true
                rm -rf "$MASTER_INSTALL_DIR"
                check_node_exists && check_gateway_exists && { generate_shared_caddyfile; reload_shared_gateway; } || \
                    { [[ -d "$GATEWAY_DIR" ]] && (cd "$GATEWAY_DIR" && docker compose down -v 2>/dev/null); rm -rf "$GATEWAY_DIR"; }
                log_success "Master uninstalled!"
            else
                log_warn "Master not installed"
            fi
            ;;
        2)
            if [[ -d "$NODE_INSTALL_DIR" ]]; then
                confirm "Remove Node and all its data?" "n" || exit 0
                log_info "Stopping existing containers..."
                (cd "$NODE_INSTALL_DIR" && docker compose down -v 2>/dev/null) || true
                rm -rf "$NODE_INSTALL_DIR"
                check_master_exists && check_gateway_exists && { generate_shared_caddyfile; reload_shared_gateway; } || \
                    { [[ -d "$GATEWAY_DIR" ]] && (cd "$GATEWAY_DIR" && docker compose down -v 2>/dev/null); rm -rf "$GATEWAY_DIR"; }
                log_success "Node uninstalled!"
            else
                log_warn "Node not installed"
            fi
            ;;
        3)
            confirm "Remove ALL SUI Solo components and data?" "n" || exit 0
            log_info "Stopping existing containers..."
            [[ -d "$GATEWAY_DIR" ]] && (cd "$GATEWAY_DIR" && docker compose down -v 2>/dev/null) || true
            [[ -d "$MASTER_INSTALL_DIR" ]] && (cd "$MASTER_INSTALL_DIR" && docker compose down -v 2>/dev/null) || true
            [[ -d "$NODE_INSTALL_DIR" ]] && (cd "$NODE_INSTALL_DIR" && docker compose down -v 2>/dev/null) || true
            rm -rf /opt/sui-solo
            docker network rm sui-master-net sui-node-net 2>/dev/null || true
            log_success "All SUI Solo components uninstalled!"
            ;;
        4) log_info "Cancelled" ;;
        *) log_error "Invalid choice" ;;
    esac
}

#=============================================================================
# INSTALL BOTH (Simplified: Separate domains)
# Architecture:
#   - node.domain.com:443 -> sing-box (VLESS + Hysteria2)
#   - master.domain.com:443 -> Caddy (Master panel)
#   - Both use ACME for their own domains
#   - Port 80: Caddy handles HTTP->HTTPS redirect
#   - Hysteria2 on UDP 50200-50300
# Note: sing-box doesn't support fallback, so we use separate domains
#=============================================================================
install_both() {
    print_banner
    check_os
    check_root
    
    log_step "Installing Master + Node on same server (sing-box SNI mode)"
    echo ""
    
    if [[ -z "$SCRIPT_DIR" || ! -d "${SCRIPT_DIR}/master" ]]; then
        log_warn "Source files not found locally"
        check_dependencies
        download_source_files
    fi
    
    check_dependencies
    
    # Check for existing installation - Quick reinstall option
    if [[ -d "$MASTER_INSTALL_DIR" && -f "$MASTER_INSTALL_DIR/.env" ]] && \
       [[ -d "$NODE_INSTALL_DIR" && -f "$NODE_INSTALL_DIR/.env" ]]; then
        local existing_master=$(grep '^MASTER_DOMAIN=' "$MASTER_INSTALL_DIR/.env" 2>/dev/null | cut -d= -f2)
        local existing_node=$(grep '^NODE_DOMAIN=' "$NODE_INSTALL_DIR/.env" 2>/dev/null | cut -d= -f2)
        local existing_email=$(grep '^ACME_EMAIL=' "$MASTER_INSTALL_DIR/.env" 2>/dev/null | cut -d= -f2)
        local existing_secret=$(grep '^CLUSTER_SECRET=' "$MASTER_INSTALL_DIR/.env" 2>/dev/null | cut -d= -f2)
        
        log_warn "Existing installation detected!"
        echo -e "  Master: ${BOLD}${existing_master}${NC}"
        echo -e "  Node:   ${BOLD}${existing_node}${NC}"
        echo ""
        echo "    1) Quick reinstall (keep existing settings)"
        echo "    2) Overwrite (enter new settings)"
        echo "    3) Cancel"
        read -r -p "  Select [1-3]: " choice < /dev/tty
        case $choice in
            1)
                log_info "Quick reinstall with existing settings..."
                master_domain="$existing_master"
                node_domain="$existing_node"
                email="$existing_email"
                secret="$existing_secret"
                ;;
            2)
                log_info "Enter new configuration..."
                ;;
            *)
                log_info "Cancelled"
                exit 0
                ;;
        esac
    fi
    
    # Only ask for input if not quick reinstall
    if [[ -z "$master_domain" ]]; then
        log_info "Master Configuration"
        read -r -p "  Enter Master Domain: " master_domain < /dev/tty
        master_domain=$(echo "$master_domain" | sed 's|https://||g' | sed 's|http://||g' | tr -d '/')
        
        log_info "Node Configuration"
        read -r -p "  Enter Node Domain: " node_domain < /dev/tty
        node_domain=$(echo "$node_domain" | sed 's|https://||g' | sed 's|http://||g' | tr -d '/')
        
        read -r -p "  Enter Email [admin@example.com]: " email < /dev/tty
        email=${email:-admin@example.com}
        
        command -v openssl &>/dev/null && secret=$(openssl rand -hex 32) || \
            secret=$(head -c 64 /dev/urandom | sha256sum | cut -d' ' -f1)
    fi
    
    echo ""
    log_info "Summary:"
    echo -e "  Master: ${BOLD}${master_domain}${NC}"
    echo -e "  Node:   ${BOLD}${node_domain}${NC}"
    echo -e "  Email:  ${BOLD}${email}${NC}"
    echo ""
    confirm "Proceed?" "y" || exit 0
    
    # Stop existing containers first
    log_info "Stopping existing containers..."
    [[ -d "$GATEWAY_DIR" ]] && (cd "$GATEWAY_DIR" && docker compose down 2>/dev/null) || true
    [[ -d "$MASTER_INSTALL_DIR" ]] && (cd "$MASTER_INSTALL_DIR" && docker compose down 2>/dev/null) || true
    [[ -d "$NODE_INSTALL_DIR" ]] && (cd "$NODE_INSTALL_DIR" && docker compose down 2>/dev/null) || true
    
    check_ports_avail 80 443 53
    create_docker_networks
    
    # Generate path prefix for hidden API
    local path_prefix=$(echo -n "${SALT}:${secret}" | sha256sum | cut -c1-16)
    
    # Generate UUID and password for proxies
    local vless_uuid=$(cat /proc/sys/kernel/random/uuid 2>/dev/null || openssl rand -hex 16 | sed 's/\(..\)\(..\)\(..\)\(..\)\(..\)\(..\)\(..\)\(..\)/\1\2\3\4-\5\6-\7\8-/')
    local hy2_password=$(openssl rand -hex 16 2>/dev/null || head -c 32 /dev/urandom | sha256sum | cut -c1-32)
    
    #=========================================================================
    # STEP 1: Install Master (without gateway)
    #=========================================================================
    log_step "Installing Master..."
    mkdir -p "$MASTER_INSTALL_DIR"
    cp -r "${SCRIPT_DIR}/master/"* "$MASTER_INSTALL_DIR/"
    
    cat > "$MASTER_INSTALL_DIR/docker-compose.yml" << 'EOF'
services:
  app:
    build: .
    container_name: sui-master
    restart: unless-stopped
    expose: ["5000"]
    environment:
      - CLUSTER_SECRET=${CLUSTER_SECRET}
      - DATA_DIR=/data
    volumes: [app-data:/data]
    networks: [sui-master-net]
volumes:
  app-data:
networks:
  sui-master-net:
    external: true
EOF
    
    cat > "$MASTER_INSTALL_DIR/.env" << EOF
CLUSTER_SECRET=${secret}
MASTER_DOMAIN=${master_domain}
ACME_EMAIL=${email}
EOF

    cd "$MASTER_INSTALL_DIR"
    docker compose up -d --build
    echo -e "  ${CHECK} Master container started"
    
    #=========================================================================
    # STEP 2: Install Node (sing-box as SNI router on 443)
    #=========================================================================
    log_step "Installing Node with SNI routing..."
    mkdir -p "$NODE_INSTALL_DIR/config/singbox" "$NODE_INSTALL_DIR/config/adguard/conf"
    cp -r "${SCRIPT_DIR}/node/"* "$NODE_INSTALL_DIR/"
    
    # Node docker-compose:
    # - sing-box: node.domain.com on 443 (VLESS)
    # - Caddy: master.domain.com on 443 + port 80 redirect
    cat > "$NODE_INSTALL_DIR/docker-compose.yml" << 'EOF'
services:
  singbox:
    image: ghcr.io/sagernet/sing-box:latest
    container_name: sui-singbox
    restart: unless-stopped
    ports:
      - "8443:8443/tcp"
      - "50200-50300:50200-50300/udp"
    volumes:
      - ./config/singbox:/etc/sing-box
      - ./config/caddy/data:/etc/caddy-certs:ro
    command: ["run", "-c", "/etc/sing-box/config.json"]
    networks:
      - sui-node-net
    cap_add: [NET_ADMIN]
    
  caddy:
    image: caddy:2-alpine
    container_name: sui-caddy
    restart: unless-stopped
    ports:
      - "80:80/tcp"
      - "443:443/tcp"
    volumes:
      - ./config/caddy/Caddyfile:/etc/caddy/Caddyfile:ro
      - ./config/caddy/site:/usr/share/caddy:ro
      - ./config/caddy/logs:/var/log/caddy
      - ./config/caddy/data:/data
    networks:
      - sui-node-net
      - sui-master-net
    
  agent:
    build: .
    container_name: sui-agent
    restart: unless-stopped
    expose: ["5001"]
    environment:
      - CLUSTER_SECRET=${CLUSTER_SECRET}
      - NODE_DOMAIN=${NODE_DOMAIN}
      - CONFIG_DIR=/config
    volumes:
      - ./config:/config
      - /var/run/docker.sock:/var/run/docker.sock:ro
    networks: [sui-node-net]
    security_opt: [no-new-privileges:true]
    
  adguard:
    image: adguard/adguardhome:latest
    container_name: sui-adguard
    restart: unless-stopped
    volumes:
      - ./config/adguard/work:/opt/adguardhome/work
      - ./config/adguard/conf:/opt/adguardhome/conf
    networks: [sui-node-net]
    ports: ["53:53/tcp", "53:53/udp"]
    cap_add: [NET_BIND_SERVICE, CHOWN, SETUID, SETGID]

networks:
  sui-node-net:
    external: true
  sui-master-net:
    external: true
EOF
    
    # sing-box config: Port 443 Native with Caddy fallback
    # Architecture: sing-box owns 443, Caddy on internal port 80
    # - VLESS traffic: handled by sing-box directly
    # - Non-VLESS traffic: falls back to Caddy for web serving
    cat > "$NODE_INSTALL_DIR/config/singbox/config.json" << SBEOF
{
  "log": {
    "level": "info",
    "timestamp": true
  },
  "inbounds": [
    {
      "type": "vless",
      "tag": "vless-in",
      "listen": "::",
      "listen_port": 8443,
      "users": [
        {
          "uuid": "${vless_uuid}",
          "flow": "xtls-rprx-vision"
        }
      ],
      "tls": {
        "enabled": true,
        "server_name": "${node_domain}",
        "key_path": "/etc/caddy-certs/caddy/certificates/acme-v02.api.letsencrypt.org-directory/${node_domain}/${node_domain}.key",
        "certificate_path": "/etc/caddy-certs/caddy/certificates/acme-v02.api.letsencrypt.org-directory/${node_domain}/${node_domain}.crt"
      }
    },
    {
      "type": "hysteria2",
      "tag": "hy2-in",
      "listen": "::",
      "listen_port": 50200,
      "users": [
        {
          "password": "${hy2_password}"
        }
      ],
      "tls": {
        "enabled": true,
        "server_name": "${node_domain}",
        "key_path": "/etc/sing-box/acme/${node_domain}/key.pem",
        "certificate_path": "/etc/sing-box/acme/${node_domain}/cert.pem"
      },
      "up_mbps": 100,
      "down_mbps": 100
    }
  ],
  "outbounds": [
    {
      "type": "direct",
      "tag": "direct"
    }
  ],
  "route": {
    "rules": [],
    "final": "direct"
  }
}
SBEOF
    
    mkdir -p "$NODE_INSTALL_DIR/config/singbox/acme"
    mkdir -p "$NODE_INSTALL_DIR/config/caddy/site"
    mkdir -p "$NODE_INSTALL_DIR/config/caddy/logs"
    
    # Generate random password for Master panel basicauth
    local panel_user="admin"
    local panel_pass=$(openssl rand -base64 12 | tr -dc 'a-zA-Z0-9' | head -c 12)
    # Will generate bcrypt hash after Caddy container is running
    local panel_hash=""
    # Generate random password for AdGuard admin interface
    local adguard_pass=$(openssl rand -base64 12 | tr -dc 'a-zA-Z0-9' | head -c 12)
    generate_adguard_config
    
    cat > "$NODE_INSTALL_DIR/.env" << EOF
CLUSTER_SECRET=${secret}
NODE_DOMAIN=${node_domain}
MASTER_DOMAIN=${master_domain}
ACME_EMAIL=${email}
PATH_PREFIX=${path_prefix}
VLESS_UUID=${vless_uuid}
VLESS_PORT=${vless_port}
HY2_PASSWORD=${hy2_password}
HY2_PORT_START=50200
HY2_PORT_END=50300
PANEL_USER=${panel_user}
PANEL_PASS=${panel_pass}
ADGUARD_ADMIN_PASS=${adguard_pass}
EOF

    # Generate Caddyfile using template
    local template_file="${SCRIPT_DIR}/node/templates/Caddyfile.template"
    local output_file="$NODE_INSTALL_DIR/config/caddy/Caddyfile"
    
    # 使用环境变量替换模板内容
    export MasterDomain="${master_domain}"
    export NodeDomain="${node_domain}"
    export PathPrefix="${path_prefix}"
    export AdGuardAdminPass="${adguard_pass}"
    
    # 使用envsubst进行模板替换
    if command -v envsubst &>/dev/null; then
        envsubst < "$template_file" > "$output_file"
    else
        # 如果envsubst不可用，使用awk替换
        awk -v md="${master_domain}" -v nd="${node_domain}" \
            -v pp="${path_prefix}" -v ap="${adguard_pass}" \
            '{gsub(/\{\{.MasterDomain\}\}/, md); 
              gsub(/\{\{.NodeDomain\}\}/, nd); 
              gsub(/\{\{.PathPrefix\}\}/, pp); 
              gsub(/\{\{.AdGuardAdminPass\}\}/, ap); 
              print}' "$template_file" > "$output_file"
    fi

    # Create camouflage site
    cat > "$NODE_INSTALL_DIR/config/caddy/site/index.html" << 'SITEEOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Welcome</title>
    <style>
        body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif; max-width: 800px; margin: 50px auto; padding: 20px; background: #f5f5f5; }
        .container { background: white; padding: 40px; border-radius: 8px; box-shadow: 0 2px 4px rgba(0,0,0,0.1); }
        h1 { color: #333; margin-bottom: 20px; }
        p { color: #666; line-height: 1.6; }
    </style>
</head>
<body>
    <div class="container">
        <h1>Welcome</h1>
        <p>This is a personal website.</p>
    </div>
</body>
</html>
SITEEOF

    # Start Node containers (includes Caddy internally)
    cd "$NODE_INSTALL_DIR"
    docker compose up -d --build
    echo -e "  ${CHECK} Node containers started (sing-box + Caddy + Agent + AdGuard)"
    
    # Generate bcrypt hash using running Caddy container (no extra pull needed)
    sleep 2
    log_info "Generating basicauth credentials..."
    panel_hash=$(docker exec sui-caddy caddy hash-password --plaintext "${panel_pass}" 2>/dev/null || echo "")
    
    if [[ -n "$panel_hash" ]]; then
        # Update Caddyfile with basicauth and additional headers
        cat > "$NODE_INSTALL_DIR/config/caddy/Caddyfile" << CADDYEOF
{
    auto_https off
}

:80 {
    @master host ${master_domain}
    handle @master {
        basicauth {
            ${panel_user} ${panel_hash}
        }
        reverse_proxy sui-master:5000
    }
    
    @node host ${node_domain}
    handle @node {
        handle /${path_prefix}/api/v1/* {
            reverse_proxy sui-agent:5001
        }
        handle /adguard/* {
            uri strip_prefix /adguard
            reverse_proxy sui-adguard:3000
        }
        handle /health {
            reverse_proxy sui-agent:5001
        }
        handle {
            root * /usr/share/caddy
            file_server
            try_files {path} /index.html
        }
    }
    
    handle {
        respond "Not Found" 404
    }
    
    header -Server
    log {
        output file /var/log/caddy/access.log
        level ERROR
    }
}
CADDYEOF
        # Reload Caddy config
        docker exec sui-caddy caddy reload --config /etc/caddy/Caddyfile 2>/dev/null || true
        echo -e "  ${CHECK} Master panel basicauth enabled"
    else
        log_warn "Could not generate bcrypt hash, Master panel has no password protection"
    fi
    
    # Wait for ACME certificates
    log_info "Waiting for TLS certificates (this may take 1-2 minutes)..."
    log_warn "sing-box will automatically obtain certificates via ACME HTTP-01..."
    sleep 15
    
    #=========================================================================
    # STEP 3: Final setup
    #=========================================================================
    # Wait for containers to be healthy
    log_info "Waiting for all containers to be ready..."
    sleep 3
    
    # Generate proxy links
    local vless_link="vless://${vless_uuid}@${node_domain}:443?encryption=none&flow=xtls-rprx-vision&security=tls&sni=${node_domain}&alpn=h2,http/1.1&type=tcp#${node_domain}-VLESS"
    local hy2_link="hysteria2://${hy2_password}@${node_domain}:50200?sni=${node_domain}&alpn=h3#${node_domain}-Hysteria2"
    
    echo ""
    log_success "Both Master and Node installed successfully!"
    echo ""
    echo -e "${MAGENTA}╔════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${MAGENTA}║${NC}  ${BOLD}CLUSTER SECRET (Save this!)${NC}                                  ${MAGENTA}║${NC}"
    echo -e "${MAGENTA}╠════════════════════════════════════════════════════════════════╣${NC}"
    echo -e "${MAGENTA}║${NC}  ${YELLOW}${secret}${NC}  ${MAGENTA}║${NC}"
    echo -e "${MAGENTA}╚════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    if [[ -n "$panel_hash" ]]; then
        echo -e "${CYAN}╔════════════════════════════════════════════════════════════════╗${NC}"
        echo -e "${CYAN}║${NC}  ${BOLD}MASTER PANEL LOGIN (Save this!)${NC}                              ${CYAN}║${NC}"
        echo -e "${CYAN}╠════════════════════════════════════════════════════════════════╣${NC}"
        echo -e "${CYAN}║${NC}  URL:      ${YELLOW}https://${master_domain}${NC}"
        echo -e "${CYAN}║${NC}  Username: ${YELLOW}${panel_user}${NC}"
        echo -e "${CYAN}║${NC}  Password: ${YELLOW}${panel_pass}${NC}"
        echo -e "${CYAN}╚════════════════════════════════════════════════════════════════╝${NC}"
        echo ""
    fi
    echo -e "  ${ARROW} Master Panel: ${CYAN}https://${master_domain}${NC}"
    echo -e "  ${ARROW} Node URL:     ${CYAN}https://${node_domain}${NC}"
    echo -e "  ${ARROW} AdGuard Home: ${CYAN}https://${node_domain}/adguard/${NC}"
    echo ""
    echo -e "${MAGENTA}╔════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${MAGENTA}║${NC}  ${BOLD}PROXY CONFIGURATIONS${NC}                                         ${MAGENTA}║${NC}"
    echo -e "${MAGENTA}╠════════════════════════════════════════════════════════════════╣${NC}"
    echo -e "${MAGENTA}║${NC}  ${CYAN}VLESS + XTLS-Vision + TLS (Port 443)${NC}                         ${MAGENTA}║${NC}"
    echo -e "${MAGENTA}║${NC}  UUID: ${YELLOW}${vless_uuid}${NC}              ${MAGENTA}║${NC}"
    echo -e "${MAGENTA}╠════════════════════════════════════════════════════════════════╣${NC}"
    echo -e "${MAGENTA}║${NC}  ${CYAN}Hysteria2 (Port 50200-50300 UDP)${NC}                             ${MAGENTA}║${NC}"
    echo -e "${MAGENTA}║${NC}  Password: ${YELLOW}${hy2_password}${NC}                        ${MAGENTA}║${NC}"
    echo -e "${MAGENTA}╚════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${BOLD}Share Links (copy to client):${NC}"
    echo -e "${GREEN}VLESS:${NC}"
    echo -e "${vless_link}"
    echo ""
    echo -e "${GREEN}Hysteria2:${NC}"
    echo -e "${hy2_link}"
    echo ""
    
    # Auto-connect Node to Master
    log_info "Auto-connecting Node to Master..."
    sleep 2
    
    local node_name=$(echo "$node_domain" | cut -d. -f1 | tr '[:lower:]' '[:upper:]')
    local node_id=$(echo -n "$node_domain" | md5sum | cut -c1-8)
    
    docker exec sui-master sh -c "mkdir -p /data && cat > /data/nodes.json << NODEEOF
{
  \"${node_id}\": {
    \"name\": \"${node_name}\",
    \"domain\": \"${node_domain}\",
    \"https\": true,
    \"added_at\": \"$(date -Iseconds)\",
    \"status\": \"unknown\"
  }
}
NODEEOF"
    
    if [[ $? -eq 0 ]]; then
        echo -e "  ${CHECK} Node auto-connected to Master"
    else
        log_warn "Auto-connect failed. Please add node manually in Master panel."
    fi
    echo ""
    
    # Offer firewall configuration
    configure_firewall_prompt
}



#=============================================================================
# MAIN
#=============================================================================
main() {
    print_banner
    check_os
    check_root
    
    if [[ -z "$SCRIPT_DIR" || ! -d "${SCRIPT_DIR}/master" ]]; then
        log_warn "Source files not found locally"
        check_dependencies
        download_source_files
    fi

    collect_inputs
    check_dependencies
    
    if [[ "$INSTALL_MODE" == "master" ]]; then
        install_master
    else
        install_node
    fi
    
    # Post-installation tips
    echo ""
    echo -e "${CYAN}╔═══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${NC}  ${BOLD}Installation Complete!${NC}                                  ${CYAN}║${NC}"
    echo -e "${CYAN}╠═══════════════════════════════════════════════════════════╣${NC}"
    echo -e "${CYAN}║${NC}  If you encounter any issues, run diagnostics:          ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}  ${YELLOW}curl -fsSL https://raw.githubusercontent.com/hioTEC/SUIS/main/diagnose.sh | bash${NC}  ${CYAN}║${NC}"
    echo -e "${CYAN}╚═══════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

show_help() {
    printf "Usage: sudo %s [OPTION]\n" "$0"
    echo ""
    echo "Options:"
    echo "  --master     Install Master (Control Panel)"
    echo "  --node       Install Node (Proxy Agent)"
    echo "  --both       Install Master + Node on same server"
    echo "  --uninstall  Uninstall SUI Solo"
    echo "  --help       Show this help"
}

case "${1:-}" in
    --master)    CLI_MODE="master"; main ;;
    --node)      CLI_MODE="node"; main ;;
    --both)      install_both ;;
    --uninstall) check_os; check_root; uninstall ;;
    --help|-h)   show_help; exit 0 ;;
    *)           main ;;
esac
