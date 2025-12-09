#!/bin/bash

# SUI Proxy 服务器端快速部署脚本
# 从 GitHub 下载并自动部署

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# 配置
GITHUB_REPO="${GITHUB_REPO:-your-username/sui-proxy}"  # 替换为你的仓库
BRANCH="${BRANCH:-main}"
INSTALL_DIR="/opt/sui-proxy"
TEMP_DIR="/tmp/sui-proxy-deploy"

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# 显示欢迎信息
show_welcome() {
    clear
    echo "========================================="
    echo "    SUI Proxy 服务器端部署脚本"
    echo "    Sing-box 443 Fallback 架构"
    echo "========================================="
    echo ""
    echo "此脚本将："
    echo "1. 从 GitHub 下载最新代码"
    echo "2. 安装必要的依赖"
    echo "3. 运行安装脚本"
    echo "4. 启动服务"
    echo "5. 运行测试验证"
    echo ""
    read -p "按 Enter 继续，或 Ctrl+C 取消..."
}

# 检查 root 权限
check_root() {
    if [ "$EUID" -ne 0 ]; then
        log_error "请使用 root 权限运行此脚本"
        echo "使用: sudo $0"
        exit 1
    fi
}

# 检查系统
check_system() {
    log_info "检查系统环境..."
    
    # 检查操作系统
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        log_info "操作系统: $NAME $VERSION"
    else
        log_warning "无法识别操作系统"
    fi
    
    # 检查架构
    ARCH=$(uname -m)
    log_info "系统架构: $ARCH"
    
    # 检查内存
    TOTAL_MEM=$(free -m | awk '/^Mem:/{print $2}')
    log_info "总内存: ${TOTAL_MEM}MB"
    
    if [ "$TOTAL_MEM" -lt 512 ]; then
        log_warning "内存不足 512MB，可能影响性能"
    fi
}

# 安装依赖
install_dependencies() {
    log_info "安装依赖..."
    
    # 更新包列表
    apt-get update -qq
    
    # 安装基础工具
    log_info "安装基础工具..."
    apt-get install -y -qq curl wget git jq net-tools > /dev/null 2>&1
    
    # 安装 Docker
    if ! command -v docker &> /dev/null; then
        log_info "安装 Docker..."
        curl -fsSL https://get.docker.com | sh > /dev/null 2>&1
        systemctl enable docker
        systemctl start docker
        log_success "Docker 安装完成"
    else
        log_info "Docker 已安装: $(docker --version)"
    fi
    
    # 检查 Docker Compose
    if ! docker compose version &> /dev/null; then
        log_error "Docker Compose 未安装"
        exit 1
    else
        log_info "Docker Compose 已安装: $(docker compose version)"
    fi
    
    log_success "依赖安装完成"
}

# 从 GitHub 下载代码
download_from_github() {
    log_info "从 GitHub 下载代码..."
    
    # 清理临时目录
    rm -rf "$TEMP_DIR"
    mkdir -p "$TEMP_DIR"
    
    # 克隆仓库
    log_info "克隆仓库: https://github.com/${GITHUB_REPO}.git"
    if git clone -b "$BRANCH" --depth=1 "https://github.com/${GITHUB_REPO}.git" "$TEMP_DIR" > /dev/null 2>&1; then
        log_success "代码下载完成"
    else
        log_error "下载失败，请检查仓库地址和网络连接"
        exit 1
    fi
    
    # 显示最新提交
    cd "$TEMP_DIR"
    LAST_COMMIT=$(git log -1 --pretty=format:"%h - %s (%ar)")
    log_info "最新提交: $LAST_COMMIT"
}

# 运行安装脚本
run_installation() {
    log_info "运行安装脚本..."
    
    cd "$TEMP_DIR"
    
    # 赋予执行权限
    chmod +x install.sh test-deployment.sh ai-test-helper.sh
    
    # 运行安装
    log_info "开始配置..."
    ./install.sh
    
    if [ $? -eq 0 ]; then
        log_success "安装完成"
    else
        log_error "安装失败"
        exit 1
    fi
}

# 启动服务
start_services() {
    log_info "启动服务..."
    
    # 启动 Gateway
    log_info "启动 Gateway..."
    cd "$INSTALL_DIR/gateway"
    docker compose up -d
    
    if [ $? -eq 0 ]; then
        log_success "Gateway 启动成功"
    else
        log_error "Gateway 启动失败"
        exit 1
    fi
    
    # 等待 Gateway 启动
    log_info "等待 Gateway 初始化..."
    sleep 10
    
    # 启动 Node
    log_info "启动 Node (Sing-box)..."
    cd "$INSTALL_DIR/node"
    docker compose up -d
    
    if [ $? -eq 0 ]; then
        log_success "Node 启动成功"
    else
        log_error "Node 启动失败"
        exit 1
    fi
    
    # 等待服务稳定
    log_info "等待服务稳定..."
    sleep 15
}

# 运行测试
run_tests() {
    log_info "运行部署测试..."
    
    cd "$TEMP_DIR"
    
    if [ -f "test-deployment.sh" ]; then
        ./test-deployment.sh
        
        if [ $? -eq 0 ]; then
            log_success "所有测试通过"
            return 0
        else
            log_warning "部分测试失败，请检查日志"
            return 1
        fi
    else
        log_warning "测试脚本不存在，跳过测试"
        return 0
    fi
}

# 显示部署信息
show_deployment_info() {
    echo ""
    echo "========================================="
    echo "         部署完成！"
    echo "========================================="
    echo ""
    
    # 读取配置
    if [ -f "$INSTALL_DIR/config/config.env" ]; then
        source "$INSTALL_DIR/config/config.env"
        
        echo "📋 配置信息:"
        echo "  Master 域名: ${MASTER_DOMAIN}"
        echo "  Node 域名: ${NODE_DOMAIN}"
        echo ""
        echo "🔑 凭证信息:"
        echo "  VLESS UUID: ${VLESS_UUID}"
        echo "  Hysteria2 密码: ${HY2_PASSWORD}"
        echo "  AdGuard 密码: ${ADGUARD_ADMIN_PASS}"
        echo ""
        echo "💾 配置文件位置:"
        echo "  ${INSTALL_DIR}/config/config.env"
        echo ""
    fi
    
    echo "🐳 容器状态:"
    docker ps --filter "name=sui-" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
    echo ""
    
    echo "🔍 端口监听:"
    ss -tlnp | grep -E ':(80|443)' || echo "  未检测到端口监听"
    echo ""
    
    echo "📚 下一步:"
    echo "  1. 配置 VLESS 客户端"
    echo "  2. 访问 Master 管理面板: https://${MASTER_DOMAIN:-your-domain}"
    echo "  3. 查看日志: docker logs sui-gateway && docker logs sui-singbox"
    echo ""
    
    echo "🔧 管理命令:"
    echo "  查看状态: docker ps"
    echo "  查看日志: docker logs sui-gateway"
    echo "  重启服务: cd $INSTALL_DIR/node && docker compose restart"
    echo "  停止服务: cd $INSTALL_DIR/node && docker compose down"
    echo ""
    
    echo "🤖 AI 辅助测试:"
    echo "  cd $TEMP_DIR"
    echo "  ./ai-test-helper.sh"
    echo ""
    
    echo "========================================="
}

# 提供 AI 测试选项
offer_ai_testing() {
    echo ""
    read -p "是否要运行 AI 辅助测试？(需要先安装 AI-CLI) [y/N]: " run_ai
    
    if [[ "$run_ai" =~ ^[Yy]$ ]]; then
        echo ""
        echo "请选择 AI-CLI 工具:"
        echo "1. OpenAI CLI (需要 API key)"
        echo "2. Anthropic Claude CLI (需要 API key)"
        echo "3. Ollama (本地运行，免费)"
        echo "4. 跳过"
        echo ""
        read -p "选择 [1-4]: " ai_choice
        
        case $ai_choice in
            1)
                log_info "安装 OpenAI CLI..."
                npm install -g @openai/cli
                read -p "请输入 OpenAI API Key: " api_key
                export OPENAI_API_KEY="$api_key"
                export AI_CMD="openai"
                ;;
            2)
                log_info "安装 Anthropic CLI..."
                pip install anthropic-cli
                read -p "请输入 Anthropic API Key: " api_key
                export ANTHROPIC_API_KEY="$api_key"
                export AI_CMD="claude"
                ;;
            3)
                log_info "安装 Ollama..."
                curl -fsSL https://ollama.ai/install.sh | sh
                ollama pull llama2
                export AI_CMD="ollama run llama2"
                ;;
            *)
                log_info "跳过 AI 测试"
                return
                ;;
        esac
        
        log_info "运行 AI 辅助测试..."
        cd "$TEMP_DIR"
        ./ai-test-helper.sh all
    fi
}

# 清理临时文件
cleanup() {
    log_info "清理临时文件..."
    # 保留临时目录以便后续使用 AI 测试
    # rm -rf "$TEMP_DIR"
    log_info "临时文件保留在: $TEMP_DIR"
}

# 错误处理
handle_error() {
    log_error "部署过程中出现错误"
    echo ""
    echo "故障排查步骤:"
    echo "1. 查看错误信息"
    echo "2. 检查日志: docker logs sui-gateway && docker logs sui-singbox"
    echo "3. 运行测试: cd $TEMP_DIR && ./test-deployment.sh"
    echo "4. 使用 AI 诊断: cd $TEMP_DIR && ./ai-test-helper.sh error"
    echo ""
    exit 1
}

# 主函数
main() {
    # 设置错误处理
    trap handle_error ERR
    
    # 显示欢迎信息
    show_welcome
    
    # 检查权限
    check_root
    
    # 检查系统
    check_system
    
    # 安装依赖
    install_dependencies
    
    # 下载代码
    download_from_github
    
    # 运行安装
    run_installation
    
    # 启动服务
    start_services
    
    # 运行测试
    run_tests
    
    # 显示部署信息
    show_deployment_info
    
    # 提供 AI 测试选项
    offer_ai_testing
    
    # 清理
    cleanup
    
    log_success "部署完成！"
}

# 运行主函数
main "$@"
