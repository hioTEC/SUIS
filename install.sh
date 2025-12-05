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
# Usage: sudo ./install.sh
#

set -e

#=============================================================================
# CONSTANTS & COLORS
#=============================================================================
readonly VERSION="1.0.0"
readonly PROJECT_NAME="SUI Solo"
readonly MASTER_INSTALL_DIR="/opt/sui-solo/master"
readonly NODE_INSTALL_DIR="/opt/sui-solo/node"

# GitHub repository URL
readonly GITHUB_REPO="https://github.com/pjonix/SUIS"
readonly GITHUB_ZIP="${GITHUB_REPO}/archive/refs/heads/main.zip"

# Detect script directory - handle both direct run and extracted zip scenarios
detect_script_dir() {
    local dir="$(cd "$(dirname "${BASH_SOURCE[0]}" 2>/dev/null)" 2>/dev/null && pwd)"
    
    # If running from pipe, dir might be empty or invalid
    [[ -z "$dir" || "$dir" == "/" ]] && dir="$(pwd)"
    
    # Check if master/ and node/ directories exist in current location
    if [[ -d "$dir/master" && -d "$dir/node" ]]; then
        echo "$dir"
        return 0
    fi
    
    # Check if we're inside an extracted zip folder (e.g., SUIS-main/)
    if [[ -d "$dir/../master" && -d "$dir/../node" ]]; then
        echo "$(cd "$dir/.." && pwd)"
        return 0
    fi
    
    # Check current working directory
    if [[ -d "./master" && -d "./node" ]]; then
        echo "$(pwd)"
        return 0
    fi
    
    # Return empty to trigger download
    echo ""
}

SCRIPT_DIR="$(detect_script_dir)"

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
readonly WARN="${YELLOW}⚠${NC}"

# Security Salt (must match Python code)
readonly SALT="SUI_Solo_Secured_2024"

#=============================================================================
# LOGGING FUNCTIONS
#=============================================================================
log_info()    { echo -e "${BLUE}[INFO]${NC}    $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC}    $1"; }
log_error()   { echo -e "${RED}[ERROR]${NC}   $1"; }
log_step()    { echo -e "${ARROW} ${BOLD}$1${NC}"; }

print_banner() {
    echo -e "${CYAN}"
    cat << 'EOF'
╔═══════════════════════════════════════════════════════════════════╗
║                                                                   ║
║     ███████╗██╗   ██╗██╗    ███████╗ ██████╗ ██╗      ██████╗     ║
║     ██╔════╝██║   ██║██║    ██╔════╝██╔═══██╗██║     ██╔═══██╗    ║
║     ███████╗██║   ██║██║    ███████╗██║   ██║██║     ██║   ██║    ║
║     ╚════██║██║   ██║██║    ╚════██║██║   ██║██║     ██║   ██║    ║
║     ███████║╚██████╔╝██║    ███████║╚██████╔╝███████╗╚██████╔╝    ║
║     ╚══════╝ ╚═════╝ ╚═╝    ╚══════╝ ╚═════╝ ╚══════╝ ╚═════╝     ║
║                                                                   ║
║           Distributed Proxy Cluster Management System             ║
║                        Version 1.0.0                              ║
╚═══════════════════════════════════════════════════════════════════╝
EOF
    echo -e "${NC}"
}

#=============================================================================
# UTILITY FUNCTIONS
#=============================================================================
confirm() {
    local prompt="${1:-Are you sure?}"
    local default="${2:-n}"
    [[ "$default" == "y" ]] && prompt="$prompt [Y/n]: " || prompt="$prompt [y/N]: "
    read -r -p "$prompt" response
    response=${response:-$default}
    [[ "$response" =~ ^[Yy]$ ]]
}

generate_secret() {
    if command -v openssl &> /dev/null; then
        openssl rand -hex 32
    else
        head -c 64 /dev/urandom | sha256sum | cut -d' ' -f1
    fi
}

compute_hidden_path() {
    local token="$1"
    echo -n "${SALT}:${token}" | sha256sum | cut -c1-16
}

backup_if_exists() {
    local file="$1"
    if [[ -f "$file" ]]; then
        local backup="${file}.backup.$(date +%Y%m%d_%H%M%S)"
        cp "$file" "$backup"
        log_info "Backed up existing file to: $backup"
    fi
}

download_source_files() {
    log_step "Downloading source files from GitHub..."
    local tmp_dir="/tmp/sui-solo-install-$$"
    local zip_file="${tmp_dir}/suis.zip"
    
    mkdir -p "$tmp_dir"
    
    # Download zip
    if curl -fsSL "$GITHUB_ZIP" -o "$zip_file"; then
        echo -e "  ${CHECK} Downloaded source archive"
    else
        log_error "Failed to download from GitHub!"
        rm -rf "$tmp_dir"
        exit 1
    fi
    
    # Extract
    if unzip -q "$zip_file" -d "$tmp_dir"; then
        echo -e "  ${CHECK} Extracted source files"
    else
        log_error "Failed to extract archive!"
        rm -rf "$tmp_dir"
        exit 1
    fi
    
    # Find extracted directory (usually SUIS-main)
    local extracted_dir=$(find "$tmp_dir" -maxdepth 1 -type d -name "SUIS*" | head -1)
    if [[ -z "$extracted_dir" ]]; then
        extracted_dir=$(find "$tmp_dir" -maxdepth 1 -type d ! -name "$(basename $tmp_dir)" | head -1)
    fi
    
    if [[ -d "$extracted_dir/master" && -d "$extracted_dir/node" ]]; then
        SCRIPT_DIR="$extracted_dir"
        echo -e "  ${CHECK} Source directory: ${CYAN}${SCRIPT_DIR}${NC}"
    else
        log_error "Invalid archive structure!"
        rm -rf "$tmp_dir"
        exit 1
    fi
}

#=============================================================================
# PREREQUISITE CHECKS
#=============================================================================
check_root() {
    log_step "Checking root privileges..."
    if [[ "$(id -u)" -ne 0 ]]; then
        log_error "This script must be run as root!"
        echo -e "  ${ARROW} Please run: ${YELLOW}sudo $0${NC}"
        exit 1
    fi
    echo -e "  ${CHECK} Running as root"
}

check_source_files() {
    log_step "Checking source files..."
    
    # If SCRIPT_DIR is empty or doesn't contain required dirs, download from GitHub
    if [[ -z "$SCRIPT_DIR" || ! -d "${SCRIPT_DIR}/master" || ! -d "${SCRIPT_DIR}/node" ]]; then
        echo -e "  ${WARN} Source files not found locally"
        download_source_files
        return 0
    fi
    
    echo -e "  ${CHECK} Found master/ directory"
    echo -e "  ${CHECK} Found node/ directory"
    echo -e "  ${CHECK} Source directory: ${CYAN}${SCRIPT_DIR}${NC}"
}

check_os() {
    log_step "Checking operating system..."
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        echo -e "  ${CHECK} Detected: ${GREEN}$PRETTY_NAME${NC}"
    elif [[ "$(uname)" == "Darwin" ]]; then
        echo -e "  ${CHECK} Detected: ${GREEN}macOS${NC}"
    else
        log_warn "Could not detect OS, proceeding anyway..."
    fi
}

check_command() {
    local cmd="$1"
    local name="${2:-$cmd}"
    if command -v "$cmd" &> /dev/null; then
        echo -e "  ${CHECK} $name is installed"
        return 0
    else
        echo -e "  ${CROSS} $name is ${RED}not installed${NC}"
        return 1
    fi
}

check_dependencies() {
    log_step "Checking dependencies..."
    local missing=()
    
    check_command "curl" "curl" || missing+=("curl")
    check_command "openssl" "openssl" || missing+=("openssl")
    check_command "unzip" "unzip" || missing+=("unzip")
    
    # Install missing packages first (before Docker check)
    if [[ ${#missing[@]} -gt 0 ]]; then
        log_info "Installing missing packages: ${missing[*]}"
        if command -v apt-get &> /dev/null; then
            apt-get update -qq && apt-get install -y -qq "${missing[@]}"
        elif command -v yum &> /dev/null; then
            yum install -y -q "${missing[@]}"
        elif command -v dnf &> /dev/null; then
            dnf install -y -q "${missing[@]}"
        elif command -v pacman &> /dev/null; then
            pacman -S --noconfirm "${missing[@]}"
        elif command -v apk &> /dev/null; then
            apk add --quiet "${missing[@]}"
        else
            log_warn "Could not auto-install packages. Please install manually: ${missing[*]}"
        fi
    fi
    
    if ! check_command "docker" "Docker"; then
        echo ""
        if confirm "Docker is not installed. Install automatically?" "y"; then
            install_docker
        else
            log_error "Docker is required."
            exit 1
        fi
    fi
    
    if docker compose version &> /dev/null; then
        echo -e "  ${CHECK} Docker Compose (plugin) is installed"
    elif command -v docker-compose &> /dev/null; then
        echo -e "  ${CHECK} Docker Compose (standalone) is installed"
    else
        log_error "Docker Compose is required."
        exit 1
    fi
    
    echo ""
    log_success "All dependencies satisfied!"
}

install_docker() {
    log_step "Installing Docker..."
    if curl -fsSL https://get.docker.com -o /tmp/get-docker.sh; then
        sh /tmp/get-docker.sh
        rm -f /tmp/get-docker.sh
        command -v systemctl &> /dev/null && systemctl start docker && systemctl enable docker
        log_success "Docker installed!"
    else
        log_error "Failed to install Docker!"
        exit 1
    fi
}

check_ports() {
    local ports=("$@")
    local blocked=()
    log_step "Checking port availability..."
    for port in "${ports[@]}"; do
        if ss -tuln 2>/dev/null | grep -q ":${port} "; then
            echo -e "  ${CROSS} Port ${RED}$port${NC} is in use"
            blocked+=("$port")
        else
            echo -e "  ${CHECK} Port $port is available"
        fi
    done
    if [[ ${#blocked[@]} -gt 0 ]]; then
        log_warn "Blocked ports: ${blocked[*]}"
        confirm "Continue anyway?" "n" || exit 1
    fi
}

#=============================================================================
# MASTER INSTALLATION (with HTTPS via Caddy)
#=============================================================================
install_master() {
    log_step "Installing ${PROJECT_NAME} Master..."
    echo ""
    
    # Check existing installation
    if [[ -d "$MASTER_INSTALL_DIR" && -f "$MASTER_INSTALL_DIR/.env" ]]; then
        log_warn "Existing installation found at: $MASTER_INSTALL_DIR"
        echo ""
        echo "  Options:"
        echo "    1) Upgrade (keep existing config)"
        echo "    2) Reinstall (backup and create new)"
        echo "    3) Cancel"
        echo ""
        read -r -p "  Select [1-3]: " choice
        case $choice in
            1) source "$MASTER_INSTALL_DIR/.env"; UPGRADE_MODE=true ;;
            2) backup_if_exists "$MASTER_INSTALL_DIR/.env" ;;
            3) log_info "Cancelled."; return ;;
            *) log_error "Invalid option"; return ;;
        esac
    fi
    
    # Get configuration
    if [[ "$UPGRADE_MODE" != "true" ]]; then
        echo ""
        echo -e "${BOLD}Master Configuration${NC}"
        echo -e "${YELLOW}⚠ IMPORTANT: Master requires a domain for HTTPS security!${NC}"
        echo -e "${YELLOW}⚠ Ensure DNS is already pointing to this server!${NC}"
        echo ""
        
        # Master Domain (REQUIRED for HTTPS)
        while [[ -z "$MASTER_DOMAIN" ]]; do
            read -r -p "  Enter Master panel domain (e.g., panel.example.com): " MASTER_DOMAIN
            if [[ -z "$MASTER_DOMAIN" ]]; then
                log_error "Domain is required for HTTPS!"
            fi
        done
        
        # ACME Email
        read -r -p "  Enter email for SSL certificates [admin@example.com]: " ACME_EMAIL
        ACME_EMAIL=${ACME_EMAIL:-admin@example.com}
        
        # Generate Cluster Secret
        CLUSTER_SECRET=$(generate_secret)
    fi
    
    # Check ports (80, 443 for Caddy)
    check_ports 80 443
    
    # Create directories
    mkdir -p "$MASTER_INSTALL_DIR"
    mkdir -p "$MASTER_INSTALL_DIR/config/caddy"
    
    # Copy files
    log_info "Copying files..."
    cp -r "${SCRIPT_DIR}/master/"* "$MASTER_INSTALL_DIR/"
    
    # Generate Caddyfile for Master
    log_info "Generating Caddyfile..."
    cat > "$MASTER_INSTALL_DIR/config/caddy/Caddyfile" << EOF
{
    email ${ACME_EMAIL}
}

${MASTER_DOMAIN} {
    reverse_proxy app:5000

    header {
        Strict-Transport-Security "max-age=31536000; includeSubDomains; preload"
        X-Frame-Options "DENY"
        X-Content-Type-Options "nosniff"
        X-XSS-Protection "1; mode=block"
        Referrer-Policy "strict-origin-when-cross-origin"
        -Server
    }

    log {
        output file /var/log/caddy/access.log
        format json
    }
}
EOF
    
    # Create .env file
    cat > "$MASTER_INSTALL_DIR/.env" << EOF
# SUI Solo Master Configuration
# Generated: $(date -Iseconds)
CLUSTER_SECRET=${CLUSTER_SECRET}
MASTER_DOMAIN=${MASTER_DOMAIN}
ACME_EMAIL=${ACME_EMAIL}
EOF
    
    # Start services
    log_info "Starting Docker containers..."
    cd "$MASTER_INSTALL_DIR"
    docker compose up -d --build
    
    echo ""
    log_success "Master installation complete!"
    echo ""
    echo -e "${MAGENTA}╔════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${MAGENTA}║${NC}  ${BOLD}CLUSTER SECRET${NC} (Save this! Required for node installation)  ${MAGENTA}║${NC}"
    echo -e "${MAGENTA}╠════════════════════════════════════════════════════════════════╣${NC}"
    echo -e "${MAGENTA}║${NC}  ${YELLOW}${CLUSTER_SECRET}${NC}  ${MAGENTA}║${NC}"
    echo -e "${MAGENTA}╚════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "  ${ARROW} Control Panel: ${CYAN}https://${MASTER_DOMAIN}${NC}"
    echo -e "  ${ARROW} Config Dir:    ${CYAN}${MASTER_INSTALL_DIR}${NC}"
    echo ""
    echo -e "  ${WARN} ${YELLOW}Ensure DNS for ${MASTER_DOMAIN} points to this server!${NC}"
    echo ""
}

#=============================================================================
# NODE INSTALLATION
#=============================================================================
install_node() {
    log_step "Installing ${PROJECT_NAME} Node..."
    echo ""
    
    # Check existing installation
    if [[ -d "$NODE_INSTALL_DIR" && -f "$NODE_INSTALL_DIR/.env" ]]; then
        log_warn "Existing installation found at: $NODE_INSTALL_DIR"
        echo ""
        echo "  Options:"
        echo "    1) Upgrade (keep existing config)"
        echo "    2) Reinstall (backup and create new)"
        echo "    3) Cancel"
        echo ""
        read -r -p "  Select [1-3]: " choice
        case $choice in
            1) source "$NODE_INSTALL_DIR/.env"; UPGRADE_MODE=true ;;
            2) backup_if_exists "$NODE_INSTALL_DIR/.env" ;;
            3) log_info "Cancelled."; return ;;
            *) log_error "Invalid option"; return ;;
        esac
    fi
    
    # Get configuration
    if [[ "$UPGRADE_MODE" != "true" ]]; then
        echo ""
        echo -e "${BOLD}Node Configuration${NC}"
        echo -e "${YELLOW}⚠ Ensure DNS is already pointing to this server!${NC}"
        echo ""
        
        # Cluster Secret
        while [[ -z "$CLUSTER_SECRET" ]]; do
            read -r -p "  Enter Cluster Secret (from Master): " CLUSTER_SECRET
            if [[ -z "$CLUSTER_SECRET" ]]; then
                log_error "Cluster secret is required!"
            elif [[ ${#CLUSTER_SECRET} -lt 32 ]]; then
                log_warn "Secret seems too short."
                confirm "  Continue?" "n" || CLUSTER_SECRET=""
            fi
        done
        
        # Node Domain
        while [[ -z "$NODE_DOMAIN" ]]; do
            read -r -p "  Enter node domain (e.g., node1.example.com): " NODE_DOMAIN
            [[ -z "$NODE_DOMAIN" ]] && log_error "Domain is required!"
        done
        
        # ACME Email
        read -r -p "  Enter email for SSL certificates [admin@example.com]: " ACME_EMAIL
        ACME_EMAIL=${ACME_EMAIL:-admin@example.com}
    fi
    
    # Compute hidden path
    PATH_PREFIX=$(compute_hidden_path "$CLUSTER_SECRET")
    log_info "Computed hidden API path: /${PATH_PREFIX}/api/v1/"
    
    # Check ports
    check_ports 80 443 53
    
    # Create directories
    mkdir -p "$NODE_INSTALL_DIR"
    mkdir -p "$NODE_INSTALL_DIR/config/caddy"
    mkdir -p "$NODE_INSTALL_DIR/config/singbox"
    mkdir -p "$NODE_INSTALL_DIR/config/adguard"
    
    # Copy files
    log_info "Copying files..."
    cp -r "${SCRIPT_DIR}/node/"* "$NODE_INSTALL_DIR/"
    
    # Generate Caddyfile
    log_info "Generating Caddyfile..."
    sed -e "s/{\\\$NODE_DOMAIN}/${NODE_DOMAIN}/g" \
        -e "s/{\\\$PATH_PREFIX}/${PATH_PREFIX}/g" \
        -e "s/{\\\$ACME_EMAIL}/${ACME_EMAIL}/g" \
        "${NODE_INSTALL_DIR}/templates/Caddyfile.template" > "$NODE_INSTALL_DIR/config/caddy/Caddyfile"
    
    # Create default sing-box config
    if [[ ! -f "$NODE_INSTALL_DIR/config/singbox/config.json" ]]; then
        cat > "$NODE_INSTALL_DIR/config/singbox/config.json" << 'EOF'
{
  "log": {"level": "info", "timestamp": true},
  "inbounds": [{"type": "mixed", "tag": "mixed-in", "listen": "::", "listen_port": 1080}],
  "outbounds": [{"type": "direct", "tag": "direct"}]
}
EOF
    fi
    
    # Create .env file
    cat > "$NODE_INSTALL_DIR/.env" << EOF
# SUI Solo Node Configuration
# Generated: $(date -Iseconds)
CLUSTER_SECRET=${CLUSTER_SECRET}
NODE_DOMAIN=${NODE_DOMAIN}
PATH_PREFIX=${PATH_PREFIX}
ACME_EMAIL=${ACME_EMAIL}
EOF
    
    # Start services
    log_info "Starting Docker containers..."
    cd "$NODE_INSTALL_DIR"
    docker compose up -d --build
    
    echo ""
    log_success "Node installation complete!"
    echo ""
    echo -e "  ${ARROW} Node URL:      ${CYAN}https://${NODE_DOMAIN}${NC}"
    echo -e "  ${ARROW} API Path:      ${CYAN}/${PATH_PREFIX}/api/v1/${NC}"
    echo -e "  ${ARROW} AdGuard Home:  ${CYAN}https://${NODE_DOMAIN}/adguard/${NC}"
    echo ""
    echo -e "  ${WARN} ${YELLOW}Add this node in Master panel: https://YOUR_MASTER_DOMAIN${NC}"
    echo ""
}

#=============================================================================
# MANAGEMENT FUNCTIONS
#=============================================================================
show_status() {
    log_step "${PROJECT_NAME} Status"
    echo ""
    
    if [[ -d "$MASTER_INSTALL_DIR" ]]; then
        echo -e "  ${BOLD}Master:${NC}"
        if docker ps --format '{{.Names}}' 2>/dev/null | grep -q "sui-master"; then
            source "$MASTER_INSTALL_DIR/.env" 2>/dev/null
            echo -e "    ${CHECK} Running at ${CYAN}https://${MASTER_DOMAIN:-localhost}${NC}"
        else
            echo -e "    ${CROSS} Not running"
        fi
    else
        echo -e "  ${BOLD}Master:${NC} Not installed"
    fi
    
    echo ""
    
    if [[ -d "$NODE_INSTALL_DIR" ]]; then
        echo -e "  ${BOLD}Node:${NC}"
        for container in sui-caddy sui-agent sui-singbox sui-adguard; do
            if docker ps --format '{{.Names}}' 2>/dev/null | grep -q "$container"; then
                echo -e "    ${CHECK} $container is running"
            else
                echo -e "    ${CROSS} $container is not running"
            fi
        done
        source "$NODE_INSTALL_DIR/.env" 2>/dev/null
        echo -e "    ${ARROW} Domain: ${CYAN}${NODE_DOMAIN:-unknown}${NC}"
    else
        echo -e "  ${BOLD}Node:${NC} Not installed"
    fi
    echo ""
}

uninstall() {
    log_step "Uninstall ${PROJECT_NAME}"
    echo ""
    echo "  Select component:"
    echo "    1) Master only"
    echo "    2) Node only"
    echo "    3) Everything"
    echo "    4) Cancel"
    echo ""
    read -r -p "  Choice [1-4]: " choice
    
    case $choice in
        1)
            if [[ -d "$MASTER_INSTALL_DIR" ]] && confirm "  Remove Master?" "n"; then
                cd "$MASTER_INSTALL_DIR" && docker compose down -v 2>/dev/null
                rm -rf "$MASTER_INSTALL_DIR"
                log_success "Master uninstalled!"
            fi
            ;;
        2)
            if [[ -d "$NODE_INSTALL_DIR" ]] && confirm "  Remove Node?" "n"; then
                cd "$NODE_INSTALL_DIR" && docker compose down -v 2>/dev/null
                rm -rf "$NODE_INSTALL_DIR"
                log_success "Node uninstalled!"
            fi
            ;;
        3)
            if confirm "  Remove ALL components?" "n"; then
                [[ -d "$MASTER_INSTALL_DIR" ]] && cd "$MASTER_INSTALL_DIR" && docker compose down -v 2>/dev/null
                [[ -d "$NODE_INSTALL_DIR" ]] && cd "$NODE_INSTALL_DIR" && docker compose down -v 2>/dev/null
                rm -rf /opt/sui-solo
                log_success "All uninstalled!"
            fi
            ;;
        4) log_info "Cancelled" ;;
    esac
}

show_logs() {
    echo ""
    echo "  Select:"
    echo "    1) Master"
    echo "    2) Node (all)"
    echo "    3) Node - Caddy"
    echo "    4) Node - Sing-box"
    echo "    5) Node - AdGuard"
    echo ""
    read -r -p "  Choice [1-5]: " choice
    case $choice in
        1) cd "$MASTER_INSTALL_DIR" && docker compose logs -f --tail=100 ;;
        2) cd "$NODE_INSTALL_DIR" && docker compose logs -f --tail=100 ;;
        3) docker logs -f --tail=100 sui-caddy ;;
        4) docker logs -f --tail=100 sui-singbox ;;
        5) docker logs -f --tail=100 sui-adguard ;;
    esac
}

#=============================================================================
# MAIN MENU
#=============================================================================
show_menu() {
    echo ""
    echo -e "${BOLD}What would you like to do?${NC}"
    echo ""
    echo -e "  ${CYAN}1)${NC} Install Master (Control Panel)"
    echo -e "  ${CYAN}2)${NC} Install Node (Proxy Agent)"
    echo -e "  ${CYAN}3)${NC} Show Status"
    echo -e "  ${CYAN}4)${NC} View Logs"
    echo -e "  ${CYAN}5)${NC} Uninstall"
    echo -e "  ${CYAN}6)${NC} Exit"
    echo ""
    read -r -p "Select [1-6]: " choice
    
    case $choice in
        1) install_master ;;
        2) install_node ;;
        3) show_status ;;
        4) show_logs ;;
        5) uninstall ;;
        6) echo ""; log_info "Goodbye! 👋"; exit 0 ;;
        *) log_error "Invalid option"; show_menu ;;
    esac
    
    confirm "Return to menu?" "y" && show_menu
}

main() {
    clear
    print_banner
    check_root
    check_os
    check_source_files
    check_dependencies
    show_menu
}

# CLI Arguments
case "${1:-}" in
    --help|-h)
        print_banner
        echo "Usage: sudo $0 [OPTION]"
        echo ""
        echo "Options:"
        echo "  --master     Install master"
        echo "  --node       Install node"
        echo "  --status     Show status"
        echo "  --uninstall  Uninstall"
        echo "  --version    Show version"
        exit 0
        ;;
    --version|-v) echo "${PROJECT_NAME} v${VERSION}"; exit 0 ;;
    --master) print_banner; check_root; check_source_files; check_dependencies; install_master; exit 0 ;;
    --node) print_banner; check_root; check_source_files; check_dependencies; install_node; exit 0 ;;
    --status) check_root; show_status; exit 0 ;;
    --uninstall) print_banner; check_root; uninstall; exit 0 ;;
    "") main ;;
    *) log_error "Unknown option: $1"; exit 1 ;;
esac
