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
readonly VERSION="1.8.3"
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
LANG_CODE="en"
domain=""
master_domain=""
node_domain=""
email=""
secret=""

#=============================================================================
# I18N - Internationalization
#=============================================================================
declare -A MSG_EN MSG_ZH

# English messages
MSG_EN=(
    [select_lang]="Select language / 选择语言:"
    [lang_en]="English"
    [lang_zh]="中文"
    [downloading]="Downloading source files from GitHub..."
    [download_from]="Downloading from"
    [downloaded]="Downloaded source archive"
    [extracted]="Extracted source files"
    [source_dir]="Source directory"
    [download_failed]="Failed to download from GitHub!"
    [empty_file]="Downloaded file is empty!"
    [extract_failed]="Failed to extract archive!"
    [invalid_archive]="Invalid archive structure!"
    [checking_deps]="Checking Dependencies..."
    [installing_deps]="Installing"
    [install_docker]="Installing Docker..."
    [docker_mac_error]="Please install Docker Desktop for Mac manually."
    [no_pkg_mgr]="No package manager. Please install"
    [root_required]="This script must be run as root on Linux!"
    [macos_warn]="Running as non-root on macOS. Ensure Docker permissions."
    [config_setup]="Configuration Setup"
    [select_mode]="Select installation mode:"
    [mode_master]="Master (Control Panel)"
    [mode_node]="Node (Proxy Agent)"
    [enter_choice]="Enter choice"
    [invalid_choice]="Invalid choice"
    [reading_env]="Reading defaults from existing .env..."
    [config_hint]="Configuration (Press Enter for default)"
    [enter_domain]="Enter Domain"
    [enter_email]="Enter Email"
    [enter_secret]="Enter Cluster Secret"
    [found_existing]="found existing"
    [secret_required]="Secret is required!"
    [adguard_config]="AdGuard Home will be configured with"
    [summary]="Summary:"
    [mode]="Mode"
    [proceed]="Proceed?"
    [cancelled]="Cancelled"
    [port_in_use]="Port %s is in use."
    [port_options]="Options:"
    [port_kill]="Kill processes and continue"
    [port_continue]="Continue anyway (may fail)"
    [port_cancel]="Cancel"
    [select]="Select"
    [killing_port]="Killing process on port"
    [port_free_failed]="Failed to free port"
    [ports_freed]="Ports freed successfully"
    [continue_busy]="Continuing with busy ports..."
    [creating_networks]="Creating Docker networks..."
    [existing_master]="Existing Master installation detected!"
    [existing_node]="Existing Node installation detected!"
    [overwrite]="Overwrite (update domain/settings)"
    [cancel]="Cancel"
    [stopping_containers]="Stopping existing containers..."
    [installing_master]="Installing Master..."
    [installing_node]="Installing Node..."
    [master_detected]="Master detected - using shared gateway mode"
    [setup_gateway]="Setting up Shared Gateway (Caddy)..."
    [gateway_created]="Gateway docker-compose created"
    [gen_caddyfile]="Generating shared Caddyfile..."
    [added_master]="Added Master"
    [added_node]="Added Node"
    [starting_gateway]="Starting shared gateway..."
    [reloading_gateway]="Reloading gateway configuration..."
    [gen_adguard]="Generating AdGuard Config..."
    [adguard_created]="AdGuard config created. Setup Wizard available at /adguard/"
    [master_installed]="Master Installed!"
    [node_installed]="Node Installed!"
    [save_secret]="CLUSTER SECRET (Save this! Required for node installation)"
    [control_panel]="Control Panel"
    [node_url]="Node URL"
    [adguard_home]="AdGuard Home"
    [api_path]="API Path"
    [uninstall_title]="Uninstall"
    [select_uninstall]="Select component to uninstall:"
    [master_only]="Master only"
    [node_only]="Node only"
    [everything]="Everything"
    [confirm_remove_master]="Remove Master and all its data?"
    [confirm_remove_node]="Remove Node and all its data?"
    [confirm_remove_all]="Remove ALL SUI Solo components and data?"
    [master_uninstalled]="Master uninstalled!"
    [node_uninstalled]="Node uninstalled!"
    [all_uninstalled]="All SUI Solo components uninstalled!"
    [master_not_installed]="Master not installed"
    [node_not_installed]="Node not installed"
    [install_both]="Installing Master + Node on same server"
    [master_config]="Master Configuration"
    [node_config]="Node Configuration"
    [enter_master_domain]="Enter Master Domain"
    [enter_node_domain]="Enter Node Domain"
    [both_installed]="Both Master and Node installed successfully!"
    [master_panel]="Master Panel"
    [source_not_found]="Source files not found locally"
    [help_usage]="Usage: sudo %s [OPTION]"
    [help_options]="Options:"
    [help_master]="Install Master (Control Panel)"
    [help_node]="Install Node (Proxy Agent)"
    [help_both]="Install Master + Node on same server"
    [help_uninstall]="Uninstall SUI Solo"
    [help_help]="Show this help"
)

# Chinese messages
MSG_ZH=(
    [select_lang]="Select language / 选择语言:"
    [lang_en]="English"
    [lang_zh]="中文"
    [downloading]="正在从 GitHub 下载源文件..."
    [download_from]="下载地址"
    [downloaded]="已下载源文件压缩包"
    [extracted]="已解压源文件"
    [source_dir]="源文件目录"
    [download_failed]="从 GitHub 下载失败！"
    [empty_file]="下载的文件为空！"
    [extract_failed]="解压失败！"
    [invalid_archive]="压缩包结构无效！"
    [checking_deps]="正在检查依赖..."
    [installing_deps]="正在安装"
    [install_docker]="正在安装 Docker..."
    [docker_mac_error]="请手动安装 Docker Desktop for Mac。"
    [no_pkg_mgr]="未找到包管理器，请手动安装"
    [root_required]="此脚本需要 root 权限运行！"
    [macos_warn]="在 macOS 上以非 root 运行，请确保有 Docker 权限。"
    [config_setup]="配置设置"
    [select_mode]="选择安装模式："
    [mode_master]="主控 (控制面板)"
    [mode_node]="节点 (代理服务)"
    [enter_choice]="输入选项"
    [invalid_choice]="无效选项"
    [reading_env]="正在读取现有 .env 配置..."
    [config_hint]="配置信息 (按回车使用默认值)"
    [enter_domain]="输入域名"
    [enter_email]="输入邮箱"
    [enter_secret]="输入集群密钥"
    [found_existing]="已找到现有配置"
    [secret_required]="密钥不能为空！"
    [adguard_config]="AdGuard Home 将使用以下配置"
    [summary]="配置摘要："
    [mode]="模式"
    [proceed]="确认继续？"
    [cancelled]="已取消"
    [port_in_use]="端口 %s 已被占用。"
    [port_options]="选项："
    [port_kill]="终止进程并继续"
    [port_continue]="继续安装 (可能失败)"
    [port_cancel]="取消"
    [select]="选择"
    [killing_port]="正在终止端口上的进程"
    [port_free_failed]="无法释放端口"
    [ports_freed]="端口已成功释放"
    [continue_busy]="继续安装 (端口仍被占用)..."
    [creating_networks]="正在创建 Docker 网络..."
    [existing_master]="检测到已有主控安装！"
    [existing_node]="检测到已有节点安装！"
    [overwrite]="覆盖安装 (更新域名/设置)"
    [cancel]="取消"
    [stopping_containers]="正在停止现有容器..."
    [installing_master]="正在安装主控..."
    [installing_node]="正在安装节点..."
    [master_detected]="检测到主控 - 使用共享网关模式"
    [setup_gateway]="正在设置共享网关 (Caddy)..."
    [gateway_created]="网关 docker-compose 已创建"
    [gen_caddyfile]="正在生成共享 Caddyfile..."
    [added_master]="已添加主控"
    [added_node]="已添加节点"
    [starting_gateway]="正在启动共享网关..."
    [reloading_gateway]="正在重载网关配置..."
    [gen_adguard]="正在生成 AdGuard 配置..."
    [adguard_created]="AdGuard 配置已创建，设置向导地址: /adguard/"
    [master_installed]="主控安装完成！"
    [node_installed]="节点安装完成！"
    [save_secret]="集群密钥 (请保存！安装节点时需要)"
    [control_panel]="控制面板"
    [node_url]="节点地址"
    [adguard_home]="AdGuard Home"
    [api_path]="API 路径"
    [uninstall_title]="卸载"
    [select_uninstall]="选择要卸载的组件："
    [master_only]="仅主控"
    [node_only]="仅节点"
    [everything]="全部"
    [confirm_remove_master]="确认删除主控及其所有数据？"
    [confirm_remove_node]="确认删除节点及其所有数据？"
    [confirm_remove_all]="确认删除所有 SUI Solo 组件和数据？"
    [master_uninstalled]="主控已卸载！"
    [node_uninstalled]="节点已卸载！"
    [all_uninstalled]="所有 SUI Solo 组件已卸载！"
    [master_not_installed]="主控未安装"
    [node_not_installed]="节点未安装"
    [install_both]="正在同时安装主控和节点"
    [master_config]="主控配置"
    [node_config]="节点配置"
    [enter_master_domain]="输入主控域名"
    [enter_node_domain]="输入节点域名"
    [both_installed]="主控和节点安装成功！"
    [master_panel]="主控面板"
    [source_not_found]="本地未找到源文件"
    [help_usage]="用法: sudo %s [选项]"
    [help_options]="选项："
    [help_master]="安装主控 (控制面板)"
    [help_node]="安装节点 (代理服务)"
    [help_both]="同时安装主控和节点"
    [help_uninstall]="卸载 SUI Solo"
    [help_help]="显示帮助信息"
)

msg() {
    local key="$1"
    if [[ "$LANG_CODE" == "zh" ]]; then
        echo "${MSG_ZH[$key]:-$key}"
    else
        echo "${MSG_EN[$key]:-$key}"
    fi
}

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

select_language() {
    # Skip if /dev/tty not available
    [[ ! -e /dev/tty ]] && return 0
    
    echo ""
    echo "  $(msg select_lang)"
    echo "    1) $(msg lang_en)"
    echo "    2) $(msg lang_zh)"
    echo ""
    
    local lang_choice=""
    read -r -p "  [1-2]: " lang_choice < /dev/tty 2>/dev/null || lang_choice="1"
    case $lang_choice in
        2) LANG_CODE="zh" ;;
        *) LANG_CODE="en" ;;
    esac
    return 0
}

confirm() {
    local prompt="${1:-$(msg proceed)}"
    local default="${2:-n}"
    [[ "$default" == "y" ]] && prompt="$prompt [Y/n]: " || prompt="$prompt [y/N]: "
    read -r -p "$prompt" response < /dev/tty
    response=${response:-$default}
    [[ "$response" =~ ^[Yy]$ ]]
}

detect_script_dir() {
    local dir="$(cd "$(dirname "${BASH_SOURCE[0]}" 2>/dev/null)" 2>/dev/null && pwd)"
    [[ -z "$dir" || "$dir" == "/" ]] && dir="$(pwd)"
    if [[ -d "$dir/master" && -d "$dir/node" ]]; then echo "$dir"; return 0; fi
    if [[ -d "$dir/../master" && -d "$dir/../node" ]]; then echo "$(cd "$dir/.." && pwd)"; return 0; fi
    if [[ -d "./master" && -d "./node" ]]; then echo "$(pwd)"; return 0; fi
    echo ""
}

download_source_files() {
    log_step "$(msg downloading)"
    local github_zip="https://github.com/pjonix/SUIS/archive/refs/heads/main.zip"
    local tmp_dir="/tmp/sui-solo-install-$$"
    local zip_file="${tmp_dir}/suis.zip"
    
    rm -rf "$tmp_dir" && mkdir -p "$tmp_dir"
    
    log_info "$(msg download_from): $github_zip"
    if curl -fsSL "$github_zip" -o "$zip_file"; then
        echo -e "  ${CHECK} $(msg downloaded)"
    else
        log_error "$(msg download_failed)"; rm -rf "$tmp_dir"; exit 1
    fi
    
    [[ ! -s "$zip_file" ]] && { log_error "$(msg empty_file)"; rm -rf "$tmp_dir"; exit 1; }
    
    if unzip -q "$zip_file" -d "$tmp_dir"; then
        echo -e "  ${CHECK} $(msg extracted)"
    else
        log_error "$(msg extract_failed)"; rm -rf "$tmp_dir"; exit 1
    fi
    
    local extracted_dir=""
    for dir in "$tmp_dir"/SUIS* "$tmp_dir"/suis*; do
        [[ -d "$dir/master" && -d "$dir/node" ]] && { extracted_dir="$dir"; break; }
    done
    
    if [[ -n "$extracted_dir" ]]; then
        SCRIPT_DIR="$extracted_dir"
        echo -e "  ${CHECK} $(msg source_dir): ${CYAN}${SCRIPT_DIR}${NC}"
    else
        log_error "$(msg invalid_archive)"; rm -rf "$tmp_dir"; exit 1
    fi
}

SCRIPT_DIR="$(detect_script_dir)"

#=============================================================================
# PRE-FLIGHT
#=============================================================================
check_os() {
    OS_TYPE="unknown"
    [[ "$OSTYPE" == "darwin"* ]] && OS_TYPE="macos"
    [[ -f /etc/os-release ]] && OS_TYPE="linux"
}

check_root() {
    if [[ "$OS_TYPE" == "macos" ]]; then
        [[ "$(id -u)" -ne 0 ]] && log_warn "$(msg macos_warn)"
    else
        [[ "$(id -u)" -ne 0 ]] && { log_error "$(msg root_required)"; exit 1; }
    fi
}

check_dependencies() {
    log_step "$(msg checking_deps)"
    local missing=() pkg_mgr=""
    
    command -v brew &>/dev/null && pkg_mgr="brew"
    command -v apt-get &>/dev/null && pkg_mgr="apt"
    command -v yum &>/dev/null && pkg_mgr="yum"
    command -v apk &>/dev/null && pkg_mgr="apk"

    for tool in curl openssl unzip; do
        command -v "$tool" &>/dev/null || missing+=("$tool")
    done
    
    [[ "$OS_TYPE" == "macos" ]] && ! command -v lsof &>/dev/null && missing+=("lsof")
    [[ "$OS_TYPE" == "linux" ]] && ! command -v ss &>/dev/null && missing+=("iproute2")

    if [[ ${#missing[@]} -gt 0 ]]; then
        log_info "$(msg installing_deps): ${missing[*]}"
        case "$pkg_mgr" in
            brew) brew install "${missing[@]}" ;;
            apt)  apt-get update -qq && apt-get install -y -qq "${missing[@]}" ;;
            yum)  yum install -y "${missing[@]}" ;;
            apk)  apk add "${missing[@]}" ;;
            *)    log_error "$(msg no_pkg_mgr): ${missing[*]}"; exit 1 ;;
        esac
    fi
    
    if ! command -v docker &>/dev/null; then
        if [[ "$OS_TYPE" == "macos" ]]; then
            log_error "$(msg docker_mac_error)"; exit 1
        else
            log_info "$(msg install_docker)"
            curl -fsSL https://get.docker.com | sh
            systemctl enable docker && systemctl start docker
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
    log_info "$(msg killing_port) $port..."
    if [[ "$OS_TYPE" == "macos" ]]; then
        local pid=$(lsof -ti :$port 2>/dev/null)
        [[ -n "$pid" ]] && kill -9 $pid 2>/dev/null
    else
        local pid=$(ss -tlnp 2>/dev/null | grep ":${port} " | grep -oP 'pid=\K\d+' | head -1)
        [[ -n "$pid" ]] && kill -9 $pid 2>/dev/null
        fuser -k ${port}/tcp 2>/dev/null || true
    fi
    sleep 1
}

check_ports_avail() {
    local ports=("$@") blocked=()
    for p in "${ports[@]}"; do
        check_port "$p" || { blocked+=("$p"); log_warn "$(printf "$(msg port_in_use)" "$p")"; }
    done
    if [[ ${#blocked[@]} -gt 0 ]]; then
        echo ""
        echo "  $(msg port_options)"
        echo "    1) $(msg port_kill)"
        echo "    2) $(msg port_continue)"
        echo "    3) $(msg port_cancel)"
        echo ""
        read -r -p "  $(msg select) [1-3]: " choice < /dev/tty
        case $choice in
            1)
                for p in "${blocked[@]}"; do kill_port_process "$p"; done
                for p in "${blocked[@]}"; do
                    check_port "$p" || { log_error "$(msg port_free_failed) $p"; exit 1; }
                done
                log_success "$(msg ports_freed)"
                ;;
            2) log_warn "$(msg continue_busy)" ;;
            3) log_info "$(msg cancelled)"; exit 0 ;;
            *) log_error "$(msg invalid_choice)"; exit 1 ;;
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
    log_info "$(msg creating_networks)"
    docker network create sui-master-net 2>/dev/null || true
    docker network create sui-node-net 2>/dev/null || true
}

setup_shared_gateway() {
    log_step "$(msg setup_gateway)"
    mkdir -p "$GATEWAY_DIR"
    cat > "$GATEWAY_DIR/docker-compose.yml" << 'EOF'
version: '3.8'
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
    echo -e "  ${CHECK} $(msg gateway_created)"
}

generate_shared_caddyfile() {
    log_info "$(msg gen_caddyfile)"
    local caddyfile="$GATEWAY_DIR/Caddyfile"
    local m_domain="" n_domain="" n_path_prefix="" acme_email="${email:-admin@example.com}"
    
    [[ -f "$MASTER_INSTALL_DIR/.env" ]] && {
        m_domain=$(grep '^MASTER_DOMAIN=' "$MASTER_INSTALL_DIR/.env" | cut -d= -f2)
        acme_email=$(grep '^ACME_EMAIL=' "$MASTER_INSTALL_DIR/.env" | cut -d= -f2)
    }
    [[ -f "$NODE_INSTALL_DIR/.env" ]] && {
        n_domain=$(grep '^NODE_DOMAIN=' "$NODE_INSTALL_DIR/.env" | cut -d= -f2)
        n_path_prefix=$(grep '^PATH_PREFIX=' "$NODE_INSTALL_DIR/.env" | cut -d= -f2)
    }
    
    cat > "$caddyfile" << EOF
{
    email ${acme_email}
}
EOF
    
    [[ -n "$m_domain" ]] && {
        cat >> "$caddyfile" << EOF

${m_domain} {
    reverse_proxy sui-master:5000
    header {
        Strict-Transport-Security "max-age=31536000; includeSubDomains; preload"
        X-Frame-Options "DENY"
        X-Content-Type-Options "nosniff"
    }
    log { output file /var/log/caddy/master.log }
}
EOF
        echo -e "  ${CHECK} $(msg added_master): ${m_domain}"
    }
    
    [[ -n "$n_domain" && -n "$n_path_prefix" ]] && {
        cat >> "$caddyfile" << EOF

${n_domain} {
    handle /${n_path_prefix}/api/v1/* { reverse_proxy sui-agent:5001 }
    handle /adguard/* { uri strip_prefix /adguard; reverse_proxy sui-adguard:3000 }
    handle /health { reverse_proxy sui-agent:5001 }
    handle { respond "Welcome" 200 }
    header { Strict-Transport-Security "max-age=31536000"; -Server }
    log { output file /var/log/caddy/node.log }
}
EOF
        echo -e "  ${CHECK} $(msg added_node): ${n_domain}"
    }
}

start_shared_gateway() {
    log_info "$(msg starting_gateway)"
    cd "$GATEWAY_DIR" && docker compose up -d
}

reload_shared_gateway() {
    log_info "$(msg reloading_gateway)"
    docker exec sui-gateway caddy reload --config /etc/caddy/Caddyfile 2>/dev/null || \
        (cd "$GATEWAY_DIR" && docker compose restart)
}

generate_adguard_config() {
    local conf_file="$NODE_INSTALL_DIR/config/adguard/conf/AdGuardHome.yaml"
    mkdir -p "$(dirname "$conf_file")"
    [[ -f "$conf_file" ]] && return
    log_info "$(msg gen_adguard)"
    cat > "$conf_file" << EOF
bind_host: 0.0.0.0
bind_port: 3000
auth_attempts: 5
block_auth_min: 15
dns:
  bind_hosts: [0.0.0.0]
  port: 53
EOF
    log_info "$(msg adguard_created)"
}


#=============================================================================
# CONFIGURATION
#=============================================================================
load_env_defaults() {
    local env_file="$1"
    [[ -f "$env_file" ]] && {
        log_info "$(msg reading_env)"
        local s=$(grep '^CLUSTER_SECRET=' "$env_file" | cut -d= -f2)
        local d=$(grep '^MASTER_DOMAIN=' "$env_file" | cut -d= -f2)
        local nd=$(grep '^NODE_DOMAIN=' "$env_file" | cut -d= -f2)
        local e=$(grep '^ACME_EMAIL=' "$env_file" | cut -d= -f2)
        [[ -n "$s" ]] && secret="$s"
        [[ -n "$d" ]] && domain="$d"
        [[ -n "$nd" ]] && domain="$nd"
        [[ -n "$e" ]] && email="$e"
    }
}

collect_inputs() {
    log_step "$(msg config_setup)"
    echo ""

    if [[ -n "$CLI_MODE" ]]; then
        INSTALL_MODE="$CLI_MODE"
    else
        echo "  $(msg select_mode)"
        echo "    1) $(msg mode_master)"
        echo "    2) $(msg mode_node)"
        read -r -p "  $(msg enter_choice) [1-2]: " mode_choice < /dev/tty
        case $mode_choice in
            1) INSTALL_MODE="master" ;;
            2) INSTALL_MODE="node" ;;
            *) log_error "$(msg invalid_choice)"; exit 1 ;;
        esac
    fi
    
    local target_dir="$MASTER_INSTALL_DIR"
    [[ "$INSTALL_MODE" == "node" ]] && target_dir="$NODE_INSTALL_DIR"
    load_env_defaults "$target_dir/.env"

    echo ""
    log_info "$(msg config_hint)"
    
    local d_domain="${domain:-localhost}"
    read -r -p "  $(msg enter_domain) [${d_domain}]: " in_domain < /dev/tty
    domain=${in_domain:-$d_domain}
    domain=$(echo "$domain" | sed 's|https://||g' | sed 's|http://||g' | tr -d '/')

    local d_email="${email:-admin@example.com}"
    read -r -p "  $(msg enter_email) [${d_email}]: " in_email < /dev/tty
    email=${in_email:-$d_email}

    if [[ "$INSTALL_MODE" == "node" ]]; then
        local p_secret="$(msg enter_secret)"
        [[ -n "$secret" ]] && p_secret="$p_secret [$(msg found_existing)]"
        while [[ -z "$secret" ]]; do
            read -r -p "  $p_secret: " in_secret < /dev/tty
            [[ -n "$in_secret" ]] && secret="$in_secret"
            [[ -z "$secret" ]] && log_error "$(msg secret_required)"
        done
        log_info "$(msg adguard_config): User: admin | Pass: sui-solo"
    else
        [[ -z "$secret" ]] && {
            command -v openssl &>/dev/null && secret=$(openssl rand -hex 32) || \
                secret=$(head -c 64 /dev/urandom | sha256sum | cut -d' ' -f1)
        }
    fi

    echo ""
    log_info "$(msg summary)"
    echo -e "  $(msg mode):   ${BOLD}${INSTALL_MODE^^}${NC}"
    echo -e "  Domain: ${BOLD}${domain}${NC}"
    echo -e "  Email:  ${BOLD}${email}${NC}"
    echo ""
    confirm "$(msg proceed)" "y" || exit 0
}

#=============================================================================
# INSTALL
#=============================================================================
install_master() {
    log_step "$(msg installing_master)"
    
    if [[ -d "$MASTER_INSTALL_DIR" ]]; then
        log_warn "$(msg existing_master)"
        echo ""
        echo "    1) $(msg overwrite)"
        echo "    2) $(msg cancel)"
        read -r -p "  $(msg select) [1-2]: " choice < /dev/tty
        case $choice in
            1) log_info "$(msg stopping_containers)"; cd "$MASTER_INSTALL_DIR" && docker compose down 2>/dev/null || true
               [[ -d "$GATEWAY_DIR" ]] && cd "$GATEWAY_DIR" && docker compose down 2>/dev/null || true ;;
            *) log_info "$(msg cancelled)"; exit 0 ;;
        esac
    fi
    
    create_docker_networks
    check_gateway_exists || check_node_exists || check_ports_avail 80 443

    mkdir -p "$MASTER_INSTALL_DIR"
    cp -r "${SCRIPT_DIR}/master/"* "$MASTER_INSTALL_DIR/"
    
    cat > "$MASTER_INSTALL_DIR/docker-compose.yml" << 'EOF'
version: '3.8'
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

    cd "$MASTER_INSTALL_DIR" && docker compose up -d --build
    
    setup_shared_gateway
    generate_shared_caddyfile
    start_shared_gateway
    
    echo ""
    log_success "$(msg master_installed)"
    echo ""
    echo -e "${MAGENTA}╔════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${MAGENTA}║${NC}  ${BOLD}$(msg save_secret)${NC}  ${MAGENTA}║${NC}"
    echo -e "${MAGENTA}╠════════════════════════════════════════════════════════════════╣${NC}"
    echo -e "${MAGENTA}║${NC}  ${YELLOW}${secret}${NC}  ${MAGENTA}║${NC}"
    echo -e "${MAGENTA}╚════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "  ${ARROW} $(msg control_panel): ${CYAN}https://${domain}${NC}"
    echo ""
}

install_node() {
    log_step "$(msg installing_node)"
    
    if [[ -d "$NODE_INSTALL_DIR" ]]; then
        log_warn "$(msg existing_node)"
        echo ""
        echo "    1) $(msg overwrite)"
        echo "    2) $(msg cancel)"
        read -r -p "  $(msg select) [1-2]: " choice < /dev/tty
        case $choice in
            1) log_info "$(msg stopping_containers)"; cd "$NODE_INSTALL_DIR" && docker compose down 2>/dev/null || true ;;
            *) log_info "$(msg cancelled)"; exit 0 ;;
        esac
    fi
    
    create_docker_networks
    
    if check_master_exists || check_gateway_exists; then
        SHARED_CADDY_MODE=true
        log_info "$(msg master_detected)"
    else
        check_ports_avail 80 443
    fi
    check_ports_avail 53

    local path_prefix=$(echo -n "${SALT}:${secret}" | sha256sum | cut -c1-16)
    
    mkdir -p "$NODE_INSTALL_DIR/config/singbox" "$NODE_INSTALL_DIR/config/adguard/conf"
    cp -r "${SCRIPT_DIR}/node/"* "$NODE_INSTALL_DIR/"
    
    cat > "$NODE_INSTALL_DIR/docker-compose.yml" << 'EOF'
version: '3.8'
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

    cd "$NODE_INSTALL_DIR" && docker compose up -d --build
    
    if [[ "$SHARED_CADDY_MODE" == "true" ]]; then
        generate_shared_caddyfile
        reload_shared_gateway
    else
        setup_shared_gateway
        generate_shared_caddyfile
        start_shared_gateway
    fi
    
    echo ""
    log_success "$(msg node_installed)"
    echo ""
    echo -e "  ${ARROW} $(msg node_url):     ${CYAN}https://${domain}${NC}"
    echo -e "  ${ARROW} $(msg adguard_home): ${CYAN}https://${domain}/adguard/${NC}"
    echo -e "  ${ARROW} $(msg api_path):     ${CYAN}/${path_prefix}/api/v1/${NC}"
    echo ""
}


#=============================================================================
# UNINSTALL
#=============================================================================
uninstall() {
    print_banner
    select_language
    log_step "$(msg uninstall_title) ${PROJECT_NAME}"
    echo ""
    echo "  $(msg select_uninstall)"
    echo "    1) $(msg master_only)"
    echo "    2) $(msg node_only)"
    echo "    3) $(msg everything)"
    echo "    4) $(msg cancel)"
    echo ""
    read -r -p "  [1-4]: " choice < /dev/tty
    
    case $choice in
        1)
            if [[ -d "$MASTER_INSTALL_DIR" ]]; then
                confirm "$(msg confirm_remove_master)" "n" || exit 0
                log_info "$(msg stopping_containers)"
                cd "$MASTER_INSTALL_DIR" && docker compose down -v 2>/dev/null || true
                rm -rf "$MASTER_INSTALL_DIR"
                check_node_exists && check_gateway_exists && { generate_shared_caddyfile; reload_shared_gateway; } || \
                    { [[ -d "$GATEWAY_DIR" ]] && cd "$GATEWAY_DIR" && docker compose down -v 2>/dev/null; rm -rf "$GATEWAY_DIR"; }
                log_success "$(msg master_uninstalled)"
            else
                log_warn "$(msg master_not_installed)"
            fi
            ;;
        2)
            if [[ -d "$NODE_INSTALL_DIR" ]]; then
                confirm "$(msg confirm_remove_node)" "n" || exit 0
                log_info "$(msg stopping_containers)"
                cd "$NODE_INSTALL_DIR" && docker compose down -v 2>/dev/null || true
                rm -rf "$NODE_INSTALL_DIR"
                check_master_exists && check_gateway_exists && { generate_shared_caddyfile; reload_shared_gateway; } || \
                    { [[ -d "$GATEWAY_DIR" ]] && cd "$GATEWAY_DIR" && docker compose down -v 2>/dev/null; rm -rf "$GATEWAY_DIR"; }
                log_success "$(msg node_uninstalled)"
            else
                log_warn "$(msg node_not_installed)"
            fi
            ;;
        3)
            confirm "$(msg confirm_remove_all)" "n" || exit 0
            log_info "$(msg stopping_containers)"
            [[ -d "$GATEWAY_DIR" ]] && cd "$GATEWAY_DIR" && docker compose down -v 2>/dev/null || true
            [[ -d "$MASTER_INSTALL_DIR" ]] && cd "$MASTER_INSTALL_DIR" && docker compose down -v 2>/dev/null || true
            [[ -d "$NODE_INSTALL_DIR" ]] && cd "$NODE_INSTALL_DIR" && docker compose down -v 2>/dev/null || true
            rm -rf /opt/sui-solo
            docker network rm sui-master-net sui-node-net 2>/dev/null || true
            log_success "$(msg all_uninstalled)"
            ;;
        4) log_info "$(msg cancelled)" ;;
        *) log_error "$(msg invalid_choice)" ;;
    esac
}

#=============================================================================
# INSTALL BOTH
#=============================================================================
install_both() {
    print_banner
    select_language
    check_os
    check_root
    
    log_step "$(msg install_both)"
    echo ""
    
    [[ -z "$SCRIPT_DIR" || ! -d "${SCRIPT_DIR}/master" ]] && {
        log_warn "$(msg source_not_found)"
        check_dependencies
        download_source_files
    }
    
    check_dependencies
    
    log_info "$(msg master_config)"
    read -r -p "  $(msg enter_master_domain): " master_domain < /dev/tty
    master_domain=$(echo "$master_domain" | sed 's|https://||g' | sed 's|http://||g' | tr -d '/')
    
    log_info "$(msg node_config)"
    read -r -p "  $(msg enter_node_domain): " node_domain < /dev/tty
    node_domain=$(echo "$node_domain" | sed 's|https://||g' | sed 's|http://||g' | tr -d '/')
    
    read -r -p "  $(msg enter_email) [admin@example.com]: " email < /dev/tty
    email=${email:-admin@example.com}
    
    command -v openssl &>/dev/null && secret=$(openssl rand -hex 32) || \
        secret=$(head -c 64 /dev/urandom | sha256sum | cut -d' ' -f1)
    
    echo ""
    log_info "$(msg summary)"
    echo -e "  Master: ${BOLD}${master_domain}${NC}"
    echo -e "  Node:   ${BOLD}${node_domain}${NC}"
    echo -e "  Email:  ${BOLD}${email}${NC}"
    echo ""
    confirm "$(msg proceed)" "y" || exit 0
    
    check_ports_avail 80 443 53
    create_docker_networks
    
    domain="$master_domain"
    INSTALL_MODE="master"
    install_master
    
    domain="$node_domain"
    INSTALL_MODE="node"
    install_node
    
    echo ""
    log_success "$(msg both_installed)"
    echo ""
    echo -e "  ${ARROW} $(msg master_panel): ${CYAN}https://${master_domain}${NC}"
    echo -e "  ${ARROW} $(msg node_url):     ${CYAN}https://${node_domain}${NC}"
    echo -e "  ${ARROW} $(msg adguard_home): ${CYAN}https://${node_domain}/adguard/${NC}"
    echo ""
}

#=============================================================================
# MAIN
#=============================================================================
main() {
    print_banner
    
    # Only select language in interactive mode (no CLI args)
    [[ -z "$CLI_MODE" ]] && select_language
    
    check_os
    check_root
    
    [[ -z "$SCRIPT_DIR" || ! -d "${SCRIPT_DIR}/master" ]] && {
        log_warn "$(msg source_not_found)"
        check_dependencies
        download_source_files
    }

    collect_inputs
    check_dependencies
    
    [[ "$INSTALL_MODE" == "master" ]] && install_master || install_node
}

show_help() {
    printf "$(msg help_usage)\n" "$0"
    echo ""
    echo "$(msg help_options)"
    echo "  --master     $(msg help_master)"
    echo "  --node       $(msg help_node)"
    echo "  --both       $(msg help_both)"
    echo "  --uninstall  $(msg help_uninstall)"
    echo "  --help       $(msg help_help)"
}

# Detect language from environment or use default
[[ -n "${LANG}" && "${LANG}" =~ ^zh ]] && LANG_CODE="zh" || LANG_CODE="en"

case "${1:-}" in
    --master)    CLI_MODE="master"; main ;;
    --node)      CLI_MODE="node"; main ;;
    --both)      install_both ;;
    --uninstall) check_os; check_root; uninstall ;;
    --help|-h)   show_help; exit 0 ;;
    *)           main ;;
esac
