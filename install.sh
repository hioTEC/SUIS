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
readonly VERSION="1.9.10"
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
                exit 1
            fi
            echo -e "  ${CHECK} Docker is ready"
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

create_docker_networks() {
    log_info "Creating Docker networks..."
    docker network create sui-master-net 2>/dev/null || true
    docker network create sui-node-net 2>/dev/null || true
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
        (cd "$GATEWAY_DIR" && docker compose restart)
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
        echo ""
        echo "    1) Overwrite (update domain/settings)"
        echo "    2) Cancel"
        read -r -p "  Select [1-2]: " choice < /dev/tty
        case $choice in
            1) log_info "Stopping existing containers..."; cd "$MASTER_INSTALL_DIR" && docker compose down 2>/dev/null || true
               [[ -d "$GATEWAY_DIR" ]] && cd "$GATEWAY_DIR" && docker compose down 2>/dev/null || true ;;
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
    
    setup_shared_gateway
    generate_shared_caddyfile
    start_shared_gateway
    
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
        echo ""
        echo "    1) Overwrite (update domain/settings)"
        echo "    2) Cancel"
        read -r -p "  Select [1-2]: " choice < /dev/tty
        case $choice in
            1) log_info "Stopping existing containers..."; cd "$NODE_INSTALL_DIR" && docker compose down 2>/dev/null || true ;;
            *) log_info "Cancelled"; exit 0 ;;
        esac
    fi
    
    create_docker_networks
    
    if check_master_exists || check_gateway_exists; then
        SHARED_CADDY_MODE=true
        log_info "Master detected - using shared gateway mode"
    else
        check_ports_avail 80 443
    fi
    check_ports_avail 53

    local path_prefix=$(echo -n "${SALT}:${secret}" | sha256sum | cut -c1-16)
    
    mkdir -p "$NODE_INSTALL_DIR/config/singbox" "$NODE_INSTALL_DIR/config/adguard/conf"
    cp -r "${SCRIPT_DIR}/node/"* "$NODE_INSTALL_DIR/"
    
    cat > "$NODE_INSTALL_DIR/docker-compose.yml" << 'EOF'
services:
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
    read_only: true
    tmpfs: [/tmp]
    cap_drop: [ALL]
    security_opt: [no-new-privileges:true]
  singbox:
    image: ghcr.io/sagernet/sing-box:latest
    container_name: sui-singbox
    restart: unless-stopped
    command: ["run", "-c", "/etc/sing-box/config.json"]
    volumes: [./config/singbox:/etc/sing-box:ro]
    networks: [sui-node-net]
    cap_add: [NET_ADMIN]
    cap_drop: [ALL]
  adguard:
    image: adguard/adguardhome:latest
    container_name: sui-adguard
    restart: unless-stopped
    volumes:
      - ./config/adguard/work:/opt/adguardhome/work
      - ./config/adguard/conf:/opt/adguardhome/conf
    networks: [sui-node-net]
    ports: ["53:53/tcp", "53:53/udp"]
    cap_drop: [ALL]
    cap_add: [NET_BIND_SERVICE, CHOWN, SETUID, SETGID]
networks:
  sui-node-net:
    external: true
EOF

    [[ ! -f "$NODE_INSTALL_DIR/config/singbox/config.json" ]] && cat > "$NODE_INSTALL_DIR/config/singbox/config.json" << 'EOF'
{"log":{"level":"info"},"inbounds":[{"type":"mixed","listen":"::","listen_port":1080}],"outbounds":[{"type":"direct"}]}
EOF
    
    generate_adguard_config
    
    cat > "$NODE_INSTALL_DIR/.env" << EOF
CLUSTER_SECRET=${secret}
NODE_DOMAIN=${domain}
PATH_PREFIX=${path_prefix}
ACME_EMAIL=${email}
EOF

    cd "$NODE_INSTALL_DIR"
    if ! docker compose up -d --build; then
        log_error "Failed to start Node containers"
        docker compose logs --tail=20
        exit 1
    fi
    
    if [[ "$SHARED_CADDY_MODE" == "true" ]]; then
        generate_shared_caddyfile
        reload_shared_gateway
    else
        setup_shared_gateway
        generate_shared_caddyfile
        start_shared_gateway
    fi
    
    echo ""
    log_success "Node Installed!"
    echo ""
    echo -e "  ${ARROW} Node URL:     ${CYAN}https://${domain}${NC}"
    echo -e "  ${ARROW} AdGuard Home: ${CYAN}https://${domain}/adguard/${NC}"
    echo -e "  ${ARROW} API Path:     ${CYAN}/${path_prefix}/api/v1/${NC}"
    echo ""
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
                cd "$MASTER_INSTALL_DIR" && docker compose down -v 2>/dev/null || true
                rm -rf "$MASTER_INSTALL_DIR"
                check_node_exists && check_gateway_exists && { generate_shared_caddyfile; reload_shared_gateway; } || \
                    { [[ -d "$GATEWAY_DIR" ]] && cd "$GATEWAY_DIR" && docker compose down -v 2>/dev/null; rm -rf "$GATEWAY_DIR"; }
                log_success "Master uninstalled!"
            else
                log_warn "Master not installed"
            fi
            ;;
        2)
            if [[ -d "$NODE_INSTALL_DIR" ]]; then
                confirm "Remove Node and all its data?" "n" || exit 0
                log_info "Stopping existing containers..."
                cd "$NODE_INSTALL_DIR" && docker compose down -v 2>/dev/null || true
                rm -rf "$NODE_INSTALL_DIR"
                check_master_exists && check_gateway_exists && { generate_shared_caddyfile; reload_shared_gateway; } || \
                    { [[ -d "$GATEWAY_DIR" ]] && cd "$GATEWAY_DIR" && docker compose down -v 2>/dev/null; rm -rf "$GATEWAY_DIR"; }
                log_success "Node uninstalled!"
            else
                log_warn "Node not installed"
            fi
            ;;
        3)
            confirm "Remove ALL SUI Solo components and data?" "n" || exit 0
            log_info "Stopping existing containers..."
            [[ -d "$GATEWAY_DIR" ]] && cd "$GATEWAY_DIR" && docker compose down -v 2>/dev/null || true
            [[ -d "$MASTER_INSTALL_DIR" ]] && cd "$MASTER_INSTALL_DIR" && docker compose down -v 2>/dev/null || true
            [[ -d "$NODE_INSTALL_DIR" ]] && cd "$NODE_INSTALL_DIR" && docker compose down -v 2>/dev/null || true
            rm -rf /opt/sui-solo
            docker network rm sui-master-net sui-node-net 2>/dev/null || true
            log_success "All SUI Solo components uninstalled!"
            ;;
        4) log_info "Cancelled" ;;
        *) log_error "Invalid choice" ;;
    esac
}

#=============================================================================
# INSTALL BOTH
#=============================================================================
install_both() {
    print_banner
    check_os
    check_root
    
    log_step "Installing Master + Node on same server"
    echo ""
    
    if [[ -z "$SCRIPT_DIR" || ! -d "${SCRIPT_DIR}/master" ]]; then
        log_warn "Source files not found locally"
        check_dependencies
        download_source_files
    fi
    
    check_dependencies
    
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
    
    echo ""
    log_info "Summary:"
    echo -e "  Master: ${BOLD}${master_domain}${NC}"
    echo -e "  Node:   ${BOLD}${node_domain}${NC}"
    echo -e "  Email:  ${BOLD}${email}${NC}"
    echo ""
    confirm "Proceed?" "y" || exit 0
    
    check_ports_avail 80 443 53
    create_docker_networks
    
    domain="$master_domain"
    INSTALL_MODE="master"
    install_master
    
    domain="$node_domain"
    INSTALL_MODE="node"
    install_node
    
    echo ""
    log_success "Both Master and Node installed successfully!"
    echo ""
    echo -e "${MAGENTA}╔════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${MAGENTA}║${NC}  ${BOLD}CLUSTER SECRET (Save this!)${NC}                                  ${MAGENTA}║${NC}"
    echo -e "${MAGENTA}╠════════════════════════════════════════════════════════════════╣${NC}"
    echo -e "${MAGENTA}║${NC}  ${YELLOW}${secret}${NC}  ${MAGENTA}║${NC}"
    echo -e "${MAGENTA}╚════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "  ${ARROW} Master Panel: ${CYAN}https://${master_domain}${NC}"
    echo -e "  ${ARROW} Node URL:     ${CYAN}https://${node_domain}${NC}"
    echo -e "  ${ARROW} AdGuard Home: ${CYAN}https://${node_domain}/adguard/${NC}"
    echo ""
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
