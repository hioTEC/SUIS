#!/bin/bash
#
# ███╗   ██╗███████╗██╗  ██╗██╗   ██╗███████╗
# ████╗  ██║██╔════╝╚██╗██╔╝██║   ██║██╔════╝
# ██╔██╗ ██║█████╗   ╚███╔╝ ██║   ██║███████╗
# ██║╚██╗██║██╔══╝   ██╔██╗ ██║   ██║╚════██║
# ██║ ╚████║███████╗██╔╝ ██╗╚██████╔╝███████║
# ╚═╝  ╚═══╝╚══════╝╚═╝  ╚═╝ ╚═════╝ ╚══════╝
#              P R O X Y
#
# NexusProxy - Interactive Installation Script
# https://github.com/yourusername/nexus-proxy
#
# Usage: sudo ./install.sh
#

set -e

#=============================================================================
# CONSTANTS & COLORS
#=============================================================================
readonly VERSION="1.0.0"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly MASTER_INSTALL_DIR="/opt/nexus-proxy/master"
readonly NODE_INSTALL_DIR="/opt/nexus-proxy/node"

# Colors
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly CYAN='\033[0;36m'
readonly MAGENTA='\033[0;35m'
readonly BOLD='\033[1m'
readonly NC='\033[0m' # No Color

# Symbols
readonly CHECK="${GREEN}✔${NC}"
readonly CROSS="${RED}✘${NC}"
readonly ARROW="${CYAN}➜${NC}"
readonly WARN="${YELLOW}⚠${NC}"

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
║     ███╗   ██╗███████╗██╗  ██╗██╗   ██╗███████╗                   ║
║     ████╗  ██║██╔════╝╚██╗██╔╝██║   ██║██╔════╝                   ║
║     ██╔██╗ ██║█████╗   ╚███╔╝ ██║   ██║███████╗                   ║
║     ██║╚██╗██║██╔══╝   ██╔██╗ ██║   ██║╚════██║                   ║
║     ██║ ╚████║███████╗██╔╝ ██╗╚██████╔╝███████║                   ║
║     ╚═╝  ╚═══╝╚══════╝╚═╝  ╚═╝ ╚═════╝ ╚══════╝                   ║
║                       P R O X Y                                   ║
║                                                                   ║
║           Distributed Proxy Cluster Management System             ║
║                        Version ${VERSION}                              ║
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
    
    if [[ "$default" == "y" ]]; then
        prompt="$prompt [Y/n]: "
    else
        prompt="$prompt [y/N]: "
    fi
    
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
    # Must match Python: SALT + ":" + token -> SHA256 -> first 16 chars
    local token="$1"
    local salt="NexusProxy_Secured_2024"
    echo -n "${salt}:${token}" | sha256sum | cut -c1-16
}

backup_if_exists() {
    local file="$1"
    if [[ -f "$file" ]]; then
        local backup="${file}.backup.$(date +%Y%m%d_%H%M%S)"
        cp "$file" "$backup"
        log_info "Backed up existing file to: $backup"
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

check_os() {
    log_step "Checking operating system..."
    
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        OS=$ID
        OS_VERSION=$VERSION_ID
        echo -e "  ${CHECK} Detected: ${GREEN}$PRETTY_NAME${NC}"
    elif [[ "$(uname)" == "Darwin" ]]; then
        OS="macos"
        echo -e "  ${CHECK} Detected: ${GREEN}macOS${NC}"
    else
        log_warn "Could not detect OS, proceeding anyway..."
        OS="unknown"
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
    
    # Check curl
    if ! check_command "curl" "curl"; then
        missing+=("curl")
    fi
    
    # Check openssl
    if ! check_command "openssl" "openssl"; then
        missing+=("openssl")
    fi
    
    # Check Docker
    if ! check_command "docker" "Docker"; then
        missing+=("docker")
        
        echo ""
        if confirm "Docker is not installed. Would you like to install it automatically?" "y"; then
            install_docker
        else
            log_error "Docker is required. Please install it manually."
            echo -e "  ${ARROW} Visit: ${CYAN}https://docs.docker.com/get-docker/${NC}"
            exit 1
        fi
    fi
    
    # Check Docker Compose
    if docker compose version &> /dev/null; then
        echo -e "  ${CHECK} Docker Compose (plugin) is installed"
    elif command -v docker-compose &> /dev/null; then
        echo -e "  ${CHECK} Docker Compose (standalone) is installed"
    else
        echo -e "  ${CROSS} Docker Compose is ${RED}not installed${NC}"
        log_error "Docker Compose is required."
        exit 1
    fi
    
    # Install missing basic dependencies
    if [[ ${#missing[@]} -gt 0 && ! " ${missing[*]} " =~ " docker " ]]; then
        log_info "Installing missing dependencies: ${missing[*]}"
        
        if command -v apt-get &> /dev/null; then
            apt-get update -qq
            apt-get install -y -qq "${missing[@]}"
        elif command -v yum &> /dev/null; then
            yum install -y -q "${missing[@]}"
        elif command -v dnf &> /dev/null; then
            dnf install -y -q "${missing[@]}"
        else
            log_error "Could not install dependencies. Please install manually: ${missing[*]}"
            exit 1
        fi
    fi
    
    echo ""
    log_success "All dependencies satisfied!"
}

install_docker() {
    log_step "Installing Docker..."
    
    echo -e "  ${ARROW} Downloading Docker installation script..."
    
    if curl -fsSL https://get.docker.com -o /tmp/get-docker.sh; then
        echo -e "  ${ARROW} Running Docker installer..."
        sh /tmp/get-docker.sh
        rm -f /tmp/get-docker.sh
        
        # Start Docker service
        if command -v systemctl &> /dev/null; then
            systemctl start docker
            systemctl enable docker
        fi
        
        log_success "Docker installed successfully!"
        
        # Verify installation
        if ! check_command "docker" "Docker"; then
            log_error "Docker installation failed!"
            exit 1
        fi
    else
        log_error "Failed to download Docker installer!"
        exit 1
    fi
}

check_ports() {
    local ports=("$@")
    local blocked=()
    
    log_step "Checking port availability..."
    
    for port in "${ports[@]}"; do
        if ss -tuln 2>/dev/null | grep -q ":${port} " || \
           netstat -tuln 2>/dev/null | grep -q ":${port} "; then
            echo -e "  ${CROSS} Port ${RED}$port${NC} is already in use"
            blocked+=("$port")
        else
            echo -e "  ${CHECK} Port $port is available"
        fi
    done
    
    if [[ ${#blocked[@]} -gt 0 ]]; then
        log_warn "Some ports are blocked: ${blocked[*]}"
        if ! confirm "Continue anyway?" "n"; then
            exit 1
        fi
    fi
}

#=============================================================================
# INSTALLATION FUNCTIONS
#=============================================================================
install_master() {
    log_step "Installing NexusProxy Master..."
    echo ""
    
    # Check if already installed
    if [[ -d "$MASTER_INSTALL_DIR" ]]; then
        log_warn "Master installation detected at: $MASTER_INSTALL_DIR"
        
        if [[ -f "$MASTER_INSTALL_DIR/.env" ]]; then
            echo -e "  ${WARN} Existing configuration found!"
            echo ""
            echo "  Options:"
            echo "    1) Upgrade (keep existing config)"
            echo "    2) Reinstall (backup and create new config)"
            echo "    3) Cancel"
            echo ""
            read -r -p "  Select option [1-3]: " choice
            
            case $choice in
                1)
                    log_info "Upgrading existing installation..."
                    ;;
                2)
                    backup_if_exists "$MASTER_INSTALL_DIR/.env"
                    GENERATE_NEW_SECRET=true
                    ;;
                3)
                    log_info "Installation cancelled."
                    return
                    ;;
                *)
                    log_error "Invalid option"
                    return
                    ;;
            esac
        fi
    fi
    
    # Check ports
    check_ports 5000
    
    # Create installation directory
    mkdir -p "$MASTER_INSTALL_DIR"
    
    # Copy files
    log_info "Copying files..."
    cp -r "${SCRIPT_DIR}/master/"* "$MASTER_INSTALL_DIR/"
    
    # Generate or preserve secret
    if [[ "$GENERATE_NEW_SECRET" == "true" ]] || [[ ! -f "$MASTER_INSTALL_DIR/.env" ]]; then
        CLUSTER_SECRET=$(generate_secret)
        
        cat > "$MASTER_INSTALL_DIR/.env" << EOF
# NexusProxy Master Configuration
# Generated: $(date -Iseconds)
CLUSTER_SECRET=${CLUSTER_SECRET}
EOF
        
        echo ""
        echo -e "${MAGENTA}╔════════════════════════════════════════════════════════════════╗${NC}"
        echo -e "${MAGENTA}║${NC}  ${BOLD}CLUSTER SECRET${NC} (Save this! Required for node installation)  ${MAGENTA}║${NC}"
        echo -e "${MAGENTA}╠════════════════════════════════════════════════════════════════╣${NC}"
        echo -e "${MAGENTA}║${NC}  ${YELLOW}${CLUSTER_SECRET}${NC}  ${MAGENTA}║${NC}"
        echo -e "${MAGENTA}╚════════════════════════════════════════════════════════════════╝${NC}"
        echo ""
    else
        source "$MASTER_INSTALL_DIR/.env"
        log_info "Using existing cluster secret"
    fi
    
    # Start services
    log_info "Starting Docker containers..."
    cd "$MASTER_INSTALL_DIR"
    docker compose up -d --build
    
    echo ""
    log_success "Master installation complete!"
    echo ""
    echo -e "  ${ARROW} Control Panel: ${CYAN}http://$(hostname -I 2>/dev/null | awk '{print $1}' || echo 'localhost'):5000${NC}"
    echo -e "  ${ARROW} Config Dir:    ${CYAN}${MASTER_INSTALL_DIR}${NC}"
    echo ""
}


install_node() {
    log_step "Installing NexusProxy Node..."
    echo ""
    
    # Check if already installed
    if [[ -d "$NODE_INSTALL_DIR" ]]; then
        log_warn "Node installation detected at: $NODE_INSTALL_DIR"
        
        if [[ -f "$NODE_INSTALL_DIR/.env" ]]; then
            echo -e "  ${WARN} Existing configuration found!"
            echo ""
            echo "  Options:"
            echo "    1) Upgrade (keep existing config)"
            echo "    2) Reinstall (backup and create new config)"
            echo "    3) Cancel"
            echo ""
            read -r -p "  Select option [1-3]: " choice
            
            case $choice in
                1)
                    log_info "Upgrading existing installation..."
                    source "$NODE_INSTALL_DIR/.env"
                    UPGRADE_MODE=true
                    ;;
                2)
                    backup_if_exists "$NODE_INSTALL_DIR/.env"
                    ;;
                3)
                    log_info "Installation cancelled."
                    return
                    ;;
                *)
                    log_error "Invalid option"
                    return
                    ;;
            esac
        fi
    fi
    
    # Get configuration from user (if not upgrading)
    if [[ "$UPGRADE_MODE" != "true" ]]; then
        echo ""
        echo -e "${BOLD}Configuration${NC}"
        echo ""
        
        # Cluster Secret
        while [[ -z "$CLUSTER_SECRET" ]]; do
            read -r -p "  Enter Cluster Secret (from Master): " CLUSTER_SECRET
            if [[ -z "$CLUSTER_SECRET" ]]; then
                log_error "Cluster secret is required!"
            elif [[ ${#CLUSTER_SECRET} -lt 32 ]]; then
                log_warn "Secret seems too short. Are you sure it's correct?"
                if ! confirm "  Continue with this secret?" "n"; then
                    CLUSTER_SECRET=""
                fi
            fi
        done
        
        # Node Domain
        while [[ -z "$NODE_DOMAIN" ]]; do
            read -r -p "  Enter this node's domain (e.g., node1.example.com): " NODE_DOMAIN
            if [[ -z "$NODE_DOMAIN" ]]; then
                log_error "Node domain is required!"
            elif [[ ! "$NODE_DOMAIN" =~ ^[a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?)*$ ]]; then
                log_warn "Domain format looks unusual: $NODE_DOMAIN"
                if ! confirm "  Continue with this domain?" "n"; then
                    NODE_DOMAIN=""
                fi
            fi
        done
        
        # ACME Email
        read -r -p "  Enter email for SSL certificates [admin@example.com]: " ACME_EMAIL
        ACME_EMAIL=${ACME_EMAIL:-admin@example.com}
    fi
    
    # Compute hidden path prefix (salted hash)
    PATH_PREFIX=$(compute_hidden_path "$CLUSTER_SECRET")
    
    echo ""
    log_info "Computed hidden API path: /${PATH_PREFIX}/api/v1/"
    
    # Check ports
    check_ports 80 443 53
    
    # Create installation directory
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
    
    # Create default sing-box config if not exists
    if [[ ! -f "$NODE_INSTALL_DIR/config/singbox/config.json" ]]; then
        log_info "Creating default Sing-box configuration..."
        cat > "$NODE_INSTALL_DIR/config/singbox/config.json" << 'SINGBOX_EOF'
{
  "log": {
    "level": "info",
    "timestamp": true
  },
  "inbounds": [
    {
      "type": "mixed",
      "tag": "mixed-in",
      "listen": "::",
      "listen_port": 1080
    }
  ],
  "outbounds": [
    {
      "type": "direct",
      "tag": "direct"
    }
  ]
}
SINGBOX_EOF
    fi
    
    # Create .env file
    cat > "$NODE_INSTALL_DIR/.env" << EOF
# NexusProxy Node Configuration
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
    echo -e "  ${ARROW} Config Dir:    ${CYAN}${NODE_INSTALL_DIR}${NC}"
    echo ""
    echo -e "  ${WARN} ${YELLOW}Don't forget to add this node in the Master control panel!${NC}"
    echo ""
}

#=============================================================================
# MANAGEMENT FUNCTIONS
#=============================================================================
show_status() {
    log_step "NexusProxy Status"
    echo ""
    
    # Master status
    if [[ -d "$MASTER_INSTALL_DIR" ]]; then
        echo -e "  ${BOLD}Master:${NC}"
        if docker ps --format '{{.Names}}' 2>/dev/null | grep -q "nexus-master"; then
            echo -e "    ${CHECK} Running at ${CYAN}http://localhost:5000${NC}"
        else
            echo -e "    ${CROSS} Not running"
        fi
    else
        echo -e "  ${BOLD}Master:${NC} Not installed"
    fi
    
    echo ""
    
    # Node status
    if [[ -d "$NODE_INSTALL_DIR" ]]; then
        echo -e "  ${BOLD}Node:${NC}"
        
        for container in nexus-caddy nexus-agent nexus-singbox nexus-adguard; do
            if docker ps --format '{{.Names}}' 2>/dev/null | grep -q "$container"; then
                echo -e "    ${CHECK} $container is running"
            else
                echo -e "    ${CROSS} $container is not running"
            fi
        done
        
        if [[ -f "$NODE_INSTALL_DIR/.env" ]]; then
            source "$NODE_INSTALL_DIR/.env"
            echo -e "    ${ARROW} Domain: ${CYAN}${NODE_DOMAIN}${NC}"
        fi
    else
        echo -e "  ${BOLD}Node:${NC} Not installed"
    fi
    
    echo ""
}

uninstall() {
    log_step "Uninstall NexusProxy"
    echo ""
    
    echo "  Select component to uninstall:"
    echo "    1) Master only"
    echo "    2) Node only"
    echo "    3) Everything"
    echo "    4) Cancel"
    echo ""
    read -r -p "  Choice [1-4]: " choice
    
    case $choice in
        1)
            if [[ -d "$MASTER_INSTALL_DIR" ]]; then
                if confirm "  Remove Master and all its data?" "n"; then
                    cd "$MASTER_INSTALL_DIR"
                    docker compose down -v 2>/dev/null || true
                    rm -rf "$MASTER_INSTALL_DIR"
                    log_success "Master uninstalled!"
                fi
            else
                log_warn "Master is not installed"
            fi
            ;;
        2)
            if [[ -d "$NODE_INSTALL_DIR" ]]; then
                if confirm "  Remove Node and all its data?" "n"; then
                    cd "$NODE_INSTALL_DIR"
                    docker compose down -v 2>/dev/null || true
                    rm -rf "$NODE_INSTALL_DIR"
                    log_success "Node uninstalled!"
                fi
            else
                log_warn "Node is not installed"
            fi
            ;;
        3)
            if confirm "  Remove ALL NexusProxy components and data?" "n"; then
                if [[ -d "$MASTER_INSTALL_DIR" ]]; then
                    cd "$MASTER_INSTALL_DIR"
                    docker compose down -v 2>/dev/null || true
                fi
                if [[ -d "$NODE_INSTALL_DIR" ]]; then
                    cd "$NODE_INSTALL_DIR"
                    docker compose down -v 2>/dev/null || true
                fi
                rm -rf /opt/nexus-proxy
                log_success "All components uninstalled!"
            fi
            ;;
        4)
            log_info "Cancelled"
            ;;
        *)
            log_error "Invalid option"
            ;;
    esac
}

show_logs() {
    echo ""
    echo "  Select component:"
    echo "    1) Master"
    echo "    2) Node (all services)"
    echo "    3) Node - Caddy"
    echo "    4) Node - Sing-box"
    echo "    5) Node - AdGuard"
    echo ""
    read -r -p "  Choice [1-5]: " choice
    
    case $choice in
        1) cd "$MASTER_INSTALL_DIR" && docker compose logs -f --tail=100 ;;
        2) cd "$NODE_INSTALL_DIR" && docker compose logs -f --tail=100 ;;
        3) docker logs -f --tail=100 nexus-caddy ;;
        4) docker logs -f --tail=100 nexus-singbox ;;
        5) docker logs -f --tail=100 nexus-adguard ;;
        *) log_error "Invalid option" ;;
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
    read -r -p "Select option [1-6]: " choice
    
    case $choice in
        1) install_master ;;
        2) install_node ;;
        3) show_status ;;
        4) show_logs ;;
        5) uninstall ;;
        6) 
            echo ""
            log_info "Goodbye! 👋"
            exit 0 
            ;;
        *)
            log_error "Invalid option"
            show_menu
            ;;
    esac
    
    # Return to menu after action
    if confirm "Return to main menu?" "y"; then
        show_menu
    fi
}

#=============================================================================
# ENTRY POINT
#=============================================================================
main() {
    # Clear screen
    clear
    
    # Print banner
    print_banner
    
    # Run checks
    check_root
    check_os
    check_dependencies
    
    # Show menu
    show_menu
}

# Handle script arguments
case "${1:-}" in
    --help|-h)
        print_banner
        echo "Usage: sudo $0 [OPTION]"
        echo ""
        echo "Options:"
        echo "  --help, -h      Show this help message"
        echo "  --version, -v   Show version"
        echo "  --master        Install master directly"
        echo "  --node          Install node directly"
        echo "  --status        Show status"
        echo "  --uninstall     Uninstall"
        echo ""
        exit 0
        ;;
    --version|-v)
        echo "NexusProxy Installer v${VERSION}"
        exit 0
        ;;
    --master)
        print_banner
        check_root
        check_dependencies
        install_master
        exit 0
        ;;
    --node)
        print_banner
        check_root
        check_dependencies
        install_node
        exit 0
        ;;
    --status)
        check_root
        show_status
        exit 0
        ;;
    --uninstall)
        print_banner
        check_root
        uninstall
        exit 0
        ;;
    "")
        main
        ;;
    *)
        log_error "Unknown option: $1"
        echo "Use --help for usage information"
        exit 1
        ;;
esac
