#!/bin/bash

# AI-CLI 测试辅助脚本
# 用于收集信息并使用 AI 进行智能分析

# 颜色定义
BLUE='\033[0;34m'
GREEN='\033[0;32m'
NC='\033[0m'

# AI CLI 命令（根据你使用的 AI CLI 工具调整）
# 支持: openai, anthropic, ollama 等
AI_CMD="${AI_CMD:-ai}"  # 默认使用 'ai' 命令

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

# 检查 AI CLI 是否可用
check_ai_cli() {
    if ! command -v $AI_CMD &> /dev/null; then
        echo "错误: AI CLI 工具 '$AI_CMD' 未安装"
        echo ""
        echo "请安装 AI CLI 工具，例如："
        echo "  npm install -g @openai/cli"
        echo "  或设置环境变量: export AI_CMD='your-ai-command'"
        exit 1
    fi
}

# 1. 分析部署状态
analyze_deployment() {
    log_info "收集部署信息..."
    
    cat > /tmp/deployment-info.txt << EOF
=== SUI Proxy 部署状态 ===

容器状态:
$(docker ps -a --filter "name=sui-" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}")

端口绑定:
$(ss -tlnp | grep -E ':(80|443)' || echo "无端口绑定")

Docker 网络:
$(docker network ls | grep sui-)

网络详情 (sui-master-net):
$(docker network inspect sui-master-net --format '{{range .Containers}}{{.Name}} {{end}}' 2>/dev/null || echo "网络不存在")

网络详情 (sui-node-net):
$(docker network inspect sui-node-net --format '{{range .Containers}}{{.Name}} {{end}}' 2>/dev/null || echo "网络不存在")

配置文件检查:
Sing-box 配置: $([ -f /opt/sui-proxy/node/config/singbox/config.json ] && echo "存在" || echo "缺失")
Caddyfile: $([ -f /opt/sui-proxy/node/config/caddy/Caddyfile ] && echo "存在" || echo "缺失")

最近的 Gateway 日志:
$(docker logs sui-gateway --tail 20 2>&1 || echo "无法获取日志")

最近的 Sing-box 日志:
$(docker logs sui-singbox --tail 20 2>&1 || echo "无法获取日志")
EOF
    
    log_info "使用 AI 分析部署状态..."
    $AI_CMD "分析以下 SUI Proxy 部署信息，指出任何问题或异常，并提供建议：" < /tmp/deployment-info.txt
    
    rm /tmp/deployment-info.txt
}

# 2. 分析配置文件
analyze_config() {
    log_info "分析 Sing-box 配置..."
    
    if [ -f /opt/sui-proxy/node/config/singbox/config.json ]; then
        $AI_CMD "检查这个 Sing-box 配置文件，验证：
1. VLESS inbound 是否在端口 443
2. fallback 配置是否正确（应该指向 gateway:80）
3. 是否有任何配置错误或安全问题

配置内容：" < /opt/sui-proxy/node/config/singbox/config.json
    else
        echo "错误: Sing-box 配置文件不存在"
    fi
    
    echo ""
    log_info "分析 Caddyfile 配置..."
    
    if [ -f /opt/sui-proxy/node/config/caddy/Caddyfile ]; then
        $AI_CMD "检查这个 Caddyfile 配置，验证：
1. 是否配置为 HTTP-only (端口 80)
2. 反向代理配置是否正确
3. 是否有任何配置问题

配置内容：" < /opt/sui-proxy/node/config/caddy/Caddyfile
    else
        echo "错误: Caddyfile 不存在"
    fi
}

# 3. 诊断错误
diagnose_errors() {
    log_info "收集错误信息..."
    
    cat > /tmp/error-logs.txt << EOF
=== Gateway 错误日志 ===
$(docker logs sui-gateway 2>&1 | grep -i "error\|fail\|fatal" | tail -30 || echo "无错误")

=== Sing-box 错误日志 ===
$(docker logs sui-singbox 2>&1 | grep -i "error\|fail\|fatal" | tail -30 || echo "无错误")

=== 系统信息 ===
磁盘空间: $(df -h / | tail -1)
内存使用: $(free -h | grep Mem)
Docker 版本: $(docker --version)
EOF
    
    log_info "使用 AI 诊断错误..."
    $AI_CMD "分析以下错误日志，找出根本原因并提供解决方案：" < /tmp/error-logs.txt
    
    rm /tmp/error-logs.txt
}

# 4. 生成测试命令
generate_test_commands() {
    log_info "生成测试命令..."
    
    # 读取配置
    if [ -f /opt/sui-proxy/config/config.env ]; then
        source /opt/sui-proxy/config/config.env
    fi
    
    cat > /tmp/test-request.txt << EOF
请为以下 SUI Proxy 部署生成测试命令：

配置信息:
- Master 域名: ${MASTER_DOMAIN:-未配置}
- Node 域名: ${NODE_DOMAIN:-未配置}
- VLESS UUID: ${VLESS_UUID:-未配置}

请生成:
1. curl 命令测试 HTTP 访问 (端口 80)
2. curl 命令测试 HTTPS fallback (端口 443 → Caddy)
3. openssl 命令检查 TLS 证书
4. VLESS 客户端配置示例 (JSON 格式)
5. 性能测试命令 (使用 ab 或 wrk)
EOF
    
    $AI_CMD < /tmp/test-request.txt
    
    rm /tmp/test-request.txt
}

# 5. 生成客户端配置
generate_client_config() {
    log_info "生成 VLESS 客户端配置..."
    
    if [ -f /opt/sui-proxy/config/config.env ]; then
        source /opt/sui-proxy/config/config.env
        
        cat > /tmp/client-request.txt << EOF
请生成 VLESS 客户端配置，包括以下格式：
1. V2Ray/V2RayN JSON 配置
2. Clash 配置
3. Sing-box 客户端配置

服务器信息:
- 地址: ${NODE_DOMAIN}
- 端口: 443
- UUID: ${VLESS_UUID}
- 传输协议: TCP
- 安全: TLS
- Flow: xtls-rprx-vision
EOF
        
        $AI_CMD < /tmp/client-request.txt
        
        rm /tmp/client-request.txt
    else
        echo "错误: 配置文件不存在"
    fi
}

# 6. 性能分析
analyze_performance() {
    log_info "收集性能数据..."
    
    cat > /tmp/performance-data.txt << EOF
=== 容器资源使用 ===
$(docker stats --no-stream --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.NetIO}}" sui-gateway sui-singbox 2>/dev/null || echo "无法获取数据")

=== 连接统计 ===
端口 80 连接数: $(ss -tn | grep :80 | wc -l)
端口 443 连接数: $(ss -tn | grep :443 | wc -l)

=== 系统负载 ===
$(uptime)

=== 网络延迟 ===
Gateway ping: $(docker exec sui-singbox ping -c 3 sui-gateway 2>/dev/null | tail -1 || echo "无法测试")
EOF
    
    log_info "使用 AI 分析性能..."
    $AI_CMD "分析以下性能数据，评估系统性能并提供优化建议：" < /tmp/performance-data.txt
    
    rm /tmp/performance-data.txt
}

# 7. 安全检查
security_check() {
    log_info "执行安全检查..."
    
    cat > /tmp/security-check.txt << EOF
=== 安全配置检查 ===

配置文件权限:
$(ls -la /opt/sui-proxy/config/ 2>/dev/null || echo "无法访问")

Sing-box 配置安全检查:
$(jq '{
  tls_enabled: .inbounds[0].tls.enabled,
  acme_configured: (.inbounds[0].tls.acme != null),
  fallback_configured: (.inbounds[0].fallback != null)
}' /opt/sui-proxy/node/config/singbox/config.json 2>/dev/null || echo "无法解析")

开放端口:
$(ss -tlnp | grep -E ':(80|443|22)')

Docker 安全:
容器以 root 运行: $(docker inspect sui-singbox --format '{{.Config.User}}' 2>/dev/null || echo "未知")
EOF
    
    log_info "使用 AI 进行安全分析..."
    $AI_CMD "分析以下安全配置，指出潜在的安全风险并提供加固建议：" < /tmp/security-check.txt
    
    rm /tmp/security-check.txt
}

# 8. 故障排查指南
troubleshooting_guide() {
    log_info "生成故障排查指南..."
    
    # 收集当前问题
    cat > /tmp/troubleshoot-request.txt << EOF
基于以下信息，生成详细的故障排查步骤：

当前状态:
- Gateway 状态: $(docker inspect sui-gateway --format '{{.State.Status}}' 2>/dev/null || echo "未运行")
- Sing-box 状态: $(docker inspect sui-singbox --format '{{.State.Status}}' 2>/dev/null || echo "未运行")
- 端口 80: $(ss -tlnp | grep :80 > /dev/null && echo "监听中" || echo "未监听")
- 端口 443: $(ss -tlnp | grep :443 > /dev/null && echo "监听中" || echo "未监听")

最近错误:
$(docker logs sui-gateway 2>&1 | grep -i error | tail -5 || echo "无")
$(docker logs sui-singbox 2>&1 | grep -i error | tail -5 || echo "无")

请提供:
1. 常见问题及解决方案
2. 逐步排查流程
3. 日志分析技巧
4. 恢复步骤
EOF
    
    $AI_CMD < /tmp/troubleshoot-request.txt
    
    rm /tmp/troubleshoot-request.txt
}

# 显示菜单
show_menu() {
    echo "========================================="
    echo "    AI-CLI 测试辅助工具"
    echo "========================================="
    echo ""
    echo "1. 分析部署状态"
    echo "2. 分析配置文件"
    echo "3. 诊断错误"
    echo "4. 生成测试命令"
    echo "5. 生成客户端配置"
    echo "6. 性能分析"
    echo "7. 安全检查"
    echo "8. 故障排查指南"
    echo "9. 全面检查（运行所有测试）"
    echo "0. 退出"
    echo ""
    read -p "请选择 (0-9): " choice
    
    case $choice in
        1) analyze_deployment ;;
        2) analyze_config ;;
        3) diagnose_errors ;;
        4) generate_test_commands ;;
        5) generate_client_config ;;
        6) analyze_performance ;;
        7) security_check ;;
        8) troubleshooting_guide ;;
        9)
            analyze_deployment
            echo ""
            analyze_config
            echo ""
            diagnose_errors
            echo ""
            analyze_performance
            echo ""
            security_check
            ;;
        0) exit 0 ;;
        *) echo "无效选择" ;;
    esac
}

# 主函数
main() {
    # 检查是否为 root
    if [ "$EUID" -ne 0 ]; then
        echo "请使用 sudo 运行此脚本"
        exit 1
    fi
    
    # 检查 AI CLI
    check_ai_cli
    
    # 如果有参数，直接执行
    if [ $# -gt 0 ]; then
        case $1 in
            deploy) analyze_deployment ;;
            config) analyze_config ;;
            error) diagnose_errors ;;
            test) generate_test_commands ;;
            client) generate_client_config ;;
            perf) analyze_performance ;;
            security) security_check ;;
            troubleshoot) troubleshooting_guide ;;
            all)
                analyze_deployment
                analyze_config
                diagnose_errors
                analyze_performance
                security_check
                ;;
            *)
                echo "用法: $0 [deploy|config|error|test|client|perf|security|troubleshoot|all]"
                exit 1
                ;;
        esac
    else
        # 交互式菜单
        while true; do
            show_menu
            echo ""
            read -p "按 Enter 继续..."
            clear
        done
    fi
}

# 运行主函数
main "$@"
