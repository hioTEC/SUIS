#!/bin/bash
# SUI Solo Update Script
# Usage: ./update.sh [master|node|all]

set -e

GITHUB_URL="https://github.com/pjonix/SUIS/archive/main.zip"
TMP_DIR="/tmp/sui-update-$$"
INSTALL_DIR="/opt/sui-solo"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log() { echo -e "${GREEN}[UPDATE]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

cleanup() {
    rm -rf "$TMP_DIR" 2>/dev/null || true
}
trap cleanup EXIT

download_latest() {
    log "Downloading latest version..."
    mkdir -p "$TMP_DIR"
    curl -fsSL "$GITHUB_URL" -o "$TMP_DIR/update.zip" || error "Download failed"
    unzip -q "$TMP_DIR/update.zip" -d "$TMP_DIR" || error "Unzip failed"
    log "Download complete"
}

update_master() {
    log "Updating Master..."
    
    if [ ! -d "$INSTALL_DIR/master" ]; then
        warn "Master not installed at $INSTALL_DIR/master"
        return 1
    fi
    
    # Backup current files
    cp "$INSTALL_DIR/master/app.py" "$INSTALL_DIR/master/app.py.bak" 2>/dev/null || true
    cp "$INSTALL_DIR/master/templates/index.html" "$INSTALL_DIR/master/templates/index.html.bak" 2>/dev/null || true
    
    # Copy new files
    cp "$TMP_DIR/SUIS-main/master/app.py" "$INSTALL_DIR/master/app.py"
    cp "$TMP_DIR/SUIS-main/master/templates/index.html" "$INSTALL_DIR/master/templates/index.html"
    cp "$TMP_DIR/SUIS-main/master/requirements.txt" "$INSTALL_DIR/master/requirements.txt"
    
    log "Master files updated"
    
    # Restart container
    log "Restarting Master container..."
    cd "$INSTALL_DIR/master"
    if docker compose restart 2>/dev/null; then
        log "Master restarted successfully"
    else
        warn "Failed to restart Master container"
    fi
}

update_node() {
    log "Updating Node..."
    
    if [ ! -d "$INSTALL_DIR/node" ]; then
        warn "Node not installed at $INSTALL_DIR/node"
        return 1
    fi
    
    # Backup current files
    cp "$INSTALL_DIR/node/agent.py" "$INSTALL_DIR/node/agent.py.bak" 2>/dev/null || true
    
    # Copy new files
    cp "$TMP_DIR/SUIS-main/node/agent.py" "$INSTALL_DIR/node/agent.py"
    cp "$TMP_DIR/SUIS-main/node/requirements.txt" "$INSTALL_DIR/node/requirements.txt"
    
    log "Node files updated"
    
    # Restart container
    log "Restarting Node container..."
    cd "$INSTALL_DIR/node"
    if docker compose restart 2>/dev/null; then
        log "Node restarted successfully"
    else
        warn "Failed to restart Node container"
    fi
}

update_gateway() {
    if [ -d "$INSTALL_DIR/gateway" ]; then
        log "Restarting Gateway..."
        cd "$INSTALL_DIR/gateway"
        docker compose restart 2>/dev/null || warn "Failed to restart Gateway"
    fi
}

show_version() {
    if [ -f "$INSTALL_DIR/master/app.py" ]; then
        version=$(grep -oP 'VERSION\s*=\s*"\K[^"]+' "$INSTALL_DIR/master/app.py" 2>/dev/null || echo "unknown")
        log "Current Master version: $version"
    fi
    if [ -f "$INSTALL_DIR/node/agent.py" ]; then
        version=$(grep -oP "version.*':\s*'\K[^']+" "$INSTALL_DIR/node/agent.py" 2>/dev/null || echo "unknown")
        log "Current Node version: $version"
    fi
}

main() {
    local target="${1:-all}"
    
    log "SUI Solo Update Script"
    show_version
    echo ""
    
    download_latest
    
    case "$target" in
        master)
            update_master
            ;;
        node)
            update_node
            ;;
        all)
            update_master
            update_node
            update_gateway
            ;;
        *)
            error "Usage: $0 [master|node|all]"
            ;;
    esac
    
    echo ""
    log "Update complete!"
    show_version
}

main "$@"
