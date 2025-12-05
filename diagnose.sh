#!/bin/bash
#
# SUI Solo - Diagnostic Tool
# Checks for common issues and provides fixes
#

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

CHECK="${GREEN}✔${NC}"
CROSS="${RED}✘${NC}"
WARN="${YELLOW}⚠${NC}"

log_info()    { echo -e "${BLUE}[INFO]${NC}    $1"; }
log_success() { echo -e "${GREEN}[OK]${NC}      $1"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC}    $1"; }
log_error()   { echo -e "${RED}[ERROR]${NC}   $1"; }

echo -e "${CYAN}${BOLD}"
echo "╔═══════════════════════════════════════════════════════════╗"
echo "║           SUI Solo - System Diagnostics                  ║"
echo "╚═══════════════════════════════════════════════════════════╝"
echo -e "${NC}"

# Check 1: Docker running
echo -e "${BOLD}[1/7] Checking Docker...${NC}"
if docker info &>/dev/null; then
    log_success "Docker is running"
else
    log_error "Docker is not running"
    echo "  Fix: systemctl start docker"
    exit 1
fi

# Check 2: iptables mode
echo -e "${BOLD}[2/7] Checking iptables mode...${NC}"
if command -v update-alternatives &>/dev/null; then
    current_iptables=$(update-alternatives --query iptables 2>/dev/null | grep "Value:" | awk '{print $2}')
    if [[ "$current_iptables" == *"nft"* ]]; then
        log_warn "Using nftables mode (may cause Docker issues)"
        echo "  Fix: update-alternatives --set iptables /usr/sbin/iptables-legacy"
        echo "       update-alternatives --set ip6tables /usr/sbin/ip6tables-legacy"
    else
        log_success "Using iptables-legacy (recommended)"
    fi
else
    log_info "iptables mode check not available on this system"
fi

# Check 3: Docker networks
echo -e "${BOLD}[3/7] Checking Docker networks...${NC}"
if docker network inspect sui-master-net &>/dev/null; then
    log_success "Network sui-master-net exists"
else
    log_warn "Network sui-master-net missing"
    echo "  Fix: docker network create sui-master-net"
fi

if docker network inspect sui-node-net &>/dev/null; then
    log_success "Network sui-node-net exists"
else
    log_warn "Network sui-node-net missing"
    echo "  Fix: docker network create sui-node-net"
fi

# Check 4: Master installation
echo -e "${BOLD}[4/7] Checking Master installation...${NC}"
if [[ -d "/opt/sui-solo/master" ]]; then
    log_success "Master directory exists"
    
    if docker ps | grep -q "sui-master.*Up"; then
        log_success "Master container is running"
    else
        log_error "Master container is not running"
        echo "  Check: docker logs sui-master"
        echo "  Fix: cd /opt/sui-solo/master && docker compose up -d"
    fi
else
    log_info "Master not installed"
fi

# Check 5: Node installation
echo -e "${BOLD}[5/7] Checking Node installation...${NC}"
if [[ -d "/opt/sui-solo/node" ]]; then
    log_success "Node directory exists"
    
    # Check agent
    if docker ps | grep -q "sui-agent.*Up"; then
        log_success "Agent container is running"
        
        # Check if docker CLI is available in agent
        if docker exec sui-agent docker --version &>/dev/null; then
            log_success "Docker CLI available in agent"
        else
            log_error "Docker CLI missing in agent container"
            echo "  Fix: Rebuild agent container with updated Dockerfile"
            echo "       cd /opt/sui-solo/node && docker compose build --no-cache agent && docker compose up -d"
        fi
    else
        log_error "Agent container is not running"
        echo "  Check: docker logs sui-agent"
    fi
    
    # Check singbox
    if docker ps | grep -q "sui-singbox.*Up"; then
        log_success "Singbox container is running"
    else
        log_warn "Singbox container is not running"
        echo "  Check: docker logs sui-singbox"
    fi
    
    # Check adguard
    if docker ps | grep -q "sui-adguard.*Up"; then
        log_success "AdGuard container is running"
    else
        log_warn "AdGuard container is not running"
        echo "  Check: docker logs sui-adguard"
    fi
else
    log_info "Node not installed"
fi

# Check 6: Gateway
echo -e "${BOLD}[6/7] Checking Gateway...${NC}"
if [[ -d "/opt/sui-solo/gateway" ]]; then
    log_success "Gateway directory exists"
    
    if docker ps | grep -q "sui-gateway.*Up"; then
        log_success "Gateway container is running"
    else
        log_error "Gateway container is not running"
        echo "  Check: docker logs sui-gateway"
        echo "  Fix: cd /opt/sui-solo/gateway && docker compose up -d"
    fi
else
    log_info "Gateway not installed"
fi

# Check 7: Port conflicts
echo -e "${BOLD}[7/7] Checking port usage...${NC}"
check_port() {
    local port=$1
    local service=$2
    if ss -tuln 2>/dev/null | grep -q ":${port} " || netstat -tuln 2>/dev/null | grep -q ":${port} "; then
        local process=$(lsof -i :${port} 2>/dev/null | tail -n 1 | awk '{print $1}' || echo "unknown")
        if [[ "$process" == "docker-prox" ]] || docker ps --format '{{.Ports}}' | grep -q ":${port}->"; then
            log_success "Port ${port} (${service}) - used by Docker"
        else
            log_warn "Port ${port} (${service}) - used by ${process}"
        fi
    else
        log_info "Port ${port} (${service}) - available"
    fi
}

check_port 80 "HTTP"
check_port 443 "HTTPS"
check_port 53 "DNS"
check_port 5000 "Master API"
check_port 5001 "Node API"

echo ""
echo -e "${CYAN}${BOLD}Diagnostics complete!${NC}"
echo ""

# Offer quick fixes
if ! docker network inspect sui-master-net &>/dev/null || ! docker network inspect sui-node-net &>/dev/null; then
    echo -e "${YELLOW}Quick fix available:${NC}"
    read -r -p "Create missing Docker networks? [y/N]: " response
    if [[ "$response" =~ ^[Yy]$ ]]; then
        docker network create sui-master-net 2>/dev/null || true
        docker network create sui-node-net 2>/dev/null || true
        log_success "Networks created"
    fi
fi
