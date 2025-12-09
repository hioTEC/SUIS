#!/bin/bash

# SUI Proxy 部署测试脚本
# 用于验证 Sing-box 443 fallback 架构是否正确部署

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 测试计数器
TESTS_PASSED=0
TESTS_FAILED=0
TESTS_WARNING=0

# 配置（从环境变量或配置文件读取）
CONFIG_FILE="/opt/sui-proxy/config/config.env"
if [ -f "$CONFIG_FILE" ]; then
    source "$CONFIG_FILE"
fi

# 日志函数
log_test() {
    echo -e "${BLUE}[TEST]${NC} $1"
}

log_pass() {
    echo -e "${GREEN}[PASS]${NC} $1"
    ((TESTS_PASSED++))
}

log_fail() {
    echo -e "${RED}[FAIL]${NC} $1"
    ((TESTS_FAILED++))
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
    ((TESTS_WARNING++))
}

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

# 测试函数

test_port_bindings() {
    log_test "测试 1: 端口绑定检查"
    
    # 检查端口 80 (Caddy)
    if ss -tlnp 2>/dev/null | grep -q ":80 " || netstat -tlnp 2>/dev/null | grep -q ":80 "; then
        if docker ps --format '{{.Names}}' | grep -q "sui-gateway"; then
            log_pass "端口 80 由 Caddy (sui-gateway) 监听"
        else
            log_warn "端口 80 被占用，但不是 sui-gateway"
        fi
    else
        log_fail "端口 80 未被监听"
    fi
    
    # 检查端口 443 (Sing-box)
    if ss -tlnp 2>/dev/null | grep -q ":443 " || netstat -tlnp 2>/dev/null | grep -q ":443 "; then
        if docker ps --format '{{.Names}}' | grep -q "sui-singbox"; then
            log_pass "端口 443 由 Sing-box (sui-singbox) 监听"
        else
            log_warn "端口 443 被占用，但不是 sui-singbox"
        fi
    else
        log_fail "端口 443 未被监听"
    fi
    
    echo ""
}

test_container_status() {
    log_test "测试 2: 容器状态检查"
    
    # 检查 Gateway 容器
    if docker ps --format '{{.Names}}' | grep -q "sui-gateway"; then
        status=$(docker inspect --format='{{.State.Status}}' sui-gateway)
        if [ "$status" = "running" ]; then
            log_pass "Gateway 容器运行中"
        else
            log_fail "Gateway 容器状态: $status"
        fi
    else
        log_fail "Gateway 容器不存在"
    fi
    
    # 检查 Sing-box 容器
    if docker ps --format '{{.Names}}' | grep -q "sui-singbox"; then
        status=$(docker inspect --format='{{.State.Status}}' sui-singbox)
        if [ "$status" = "running" ]; then
            log_pass "Sing-box 容器运行中"
        else
            log_fail "Sing-box 容器状态: $status"
        fi
    else
        log_fail "Sing-box 容器不存在"
    fi
    
    echo ""
}

test_docker_networks() {
    log_test "测试 3: Docker 网络配置"
    
    # 检查网络存在
    if docker network inspect sui-master-net &>/dev/null; then
        log_pass "sui-master-net 网络存在"
    else
        log_fail "sui-master-net 网络不存在"
    fi
    
    if docker network inspect sui-node-net &>/dev/null; then
        log_pass "sui-node-net 网络存在"
    else
        log_fail "sui-node-net 网络不存在"
    fi
    
    # 检查容器网络连接
    if docker ps --format '{{.Names}}' | grep -q "sui-gateway"; then
        gateway_networks=$(docker inspect sui-gateway --format='{{range $k, $v := .NetworkSettings.Networks}}{{$k}} {{end}}')
        if echo "$gateway_networks" | grep -q "sui-master-net" && echo "$gateway_networks" | grep -q "sui-node-net"; then
            log_pass "Gateway 连接到两个网络"
        else
            log_fail "Gateway 网络配置不正确: $gateway_networks"
        fi
    fi
    
    if docker ps --format '{{.Names}}' | grep -q "sui-singbox"; then
        singbox_networks=$(docker inspect sui-singbox --format='{{range $k, $v := .NetworkSettings.Networks}}{{$k}} {{end}}')
        if echo "$singbox_networks" | grep -q "sui-master-net" && echo "$singbox_networks" | grep -q "sui-node-net"; then
            log_pass "Sing-box 连接到两个网络"
        else
            log_fail "Sing-box 网络配置不正确: $singbox_networks"
        fi
    fi
    
    echo ""
}

test_configuration_files() {
    log_test "测试 4: 配置文件验证"
    
    # 检查 Sing-box 配置
    singbox_config="/opt/sui-proxy/node/config/singbox/config.json"
    if [ -f "$singbox_config" ]; then
        if jq empty "$singbox_config" 2>/dev/null; then
            log_pass "Sing-box 配置 JSON 有效"
            
            # 检查端口 443
            vless_port=$(jq -r '.inbounds[] | select(.type == "vless") | .listen_port' "$singbox_config")
            if [ "$vless_port" = "443" ]; then
                log_pass "VLESS 监听端口 443"
            else
                log_fail "VLESS 端口配置错误: $vless_port"
            fi
            
            # 检查 fallback 配置
            if jq -e '.inbounds[] | select(.type == "vless") | .fallback' "$singbox_config" &>/dev/null; then
                fallback_server=$(jq -r '.inbounds[] | select(.type == "vless") | .fallback.server' "$singbox_config")
                fallback_port=$(jq -r '.inbounds[] | select(.type == "vless") | .fallback.server_port' "$singbox_config")
                
                if [ "$fallback_port" = "80" ]; then
                    log_pass "Fallback 配置正确 (${fallback_server}:${fallback_port})"
                else
                    log_fail "Fallback 端口错误: $fallback_port"
                fi
            else
                log_fail "Fallback 配置缺失"
            fi
        else
            log_fail "Sing-box 配置 JSON 无效"
        fi
    else
        log_fail "Sing-box 配置文件不存在"
    fi
    
    # 检查 Caddyfile
    caddyfile="/opt/sui-proxy/node/config/caddy/Caddyfile"
    if [ -f "$caddyfile" ]; then
        log_pass "Caddyfile 存在"
        
        # 检查 HTTP-only 配置
        if grep -q "http://.*:80" "$caddyfile"; then
            log_pass "Caddyfile 配置为 HTTP-only"
        else
            log_warn "Caddyfile 可能未配置为 HTTP-only"
        fi
    else
        log_fail "Caddyfile 不存在"
    fi
    
    echo ""
}

test_http_access() {
    log_test "测试 5: HTTP 访问测试"
    
    # 测试 Caddy 健康检查
    if curl -s -o /dev/null -w "%{http_code}" http://localhost:80/health 2>/dev/null | grep -q "200"; then
        log_pass "Caddy HTTP 健康检查通过"
    else
        log_warn "Caddy HTTP 健康检查失败（可能路由未配置）"
    fi
    
    echo ""
}

test_https_access() {
    log_test "测试 6: HTTPS 访问测试 (Fallback)"
    
    if [ -n "$MASTER_DOMAIN" ]; then
        log_info "测试域名: $MASTER_DOMAIN"
        
        # 测试 HTTPS 连接
        response=$(curl -k -s -o /dev/null -w "%{http_code}" https://${MASTER_DOMAIN}/ 2>/dev/null || echo "000")
        
        if [ "$response" = "200" ] || [ "$response" = "301" ] || [ "$response" = "302" ]; then
            log_pass "HTTPS 访问成功 (状态码: $response)"
        elif [ "$response" = "000" ]; then
            log_warn "HTTPS 连接失败（可能证书未配置或域名未解析）"
        else
            log_warn "HTTPS 访问返回状态码: $response"
        fi
    else
        log_warn "未配置 MASTER_DOMAIN，跳过 HTTPS 测试"
    fi
    
    echo ""
}

test_tls_certificate() {
    log_test "测试 7: TLS 证书检查"
    
    if [ -n "$NODE_DOMAIN" ]; then
        log_info "检查域名: $NODE_DOMAIN"
        
        cert_info=$(echo | timeout 5 openssl s_client -connect ${NODE_DOMAIN}:443 -servername ${NODE_DOMAIN} 2>/dev/null | openssl x509 -noout -subject -dates 2>/dev/null || echo "")
        
        if [ -n "$cert_info" ]; then
            log_pass "TLS 证书已配置"
            log_info "$cert_info"
        else
            log_warn "TLS 证书未配置或无法访问（ACME 可能仍在进行中）"
        fi
    else
        log_warn "未配置 NODE_DOMAIN，跳过证书检查"
    fi
    
    echo ""
}

test_container_connectivity() {
    log_test "测试 8: 容器间连接测试"
    
    # 测试 Sing-box 到 Gateway 的连接
    if docker ps --format '{{.Names}}' | grep -q "sui-singbox"; then
        if docker exec sui-singbox ping -c 3 sui-gateway &>/dev/null; then
            log_pass "Sing-box 可以连接到 Gateway"
        else
            log_fail "Sing-box 无法连接到 Gateway"
        fi
    else
        log_warn "Sing-box 容器未运行，跳过连接测试"
    fi
    
    echo ""
}

test_logs_for_errors() {
    log_test "测试 9: 日志错误检查"
    
    # 检查 Gateway 日志
    if docker ps --format '{{.Names}}' | grep -q "sui-gateway"; then
        error_count=$(docker logs sui-gateway 2>&1 | grep -i "error" | wc -l)
        if [ "$error_count" -eq 0 ]; then
            log_pass "Gateway 日志无错误"
        else
            log_warn "Gateway 日志中有 $error_count 个错误"
        fi
    fi
    
    # 检查 Sing-box 日志
    if docker ps --format '{{.Names}}' | grep -q "sui-singbox"; then
        error_count=$(docker logs sui-singbox 2>&1 | grep -i "error" | wc -l)
        if [ "$error_count" -eq 0 ]; then
            log_pass "Sing-box 日志无错误"
        else
            log_warn "Sing-box 日志中有 $error_count 个错误"
        fi
    fi
    
    echo ""
}

# 生成测试报告
generate_report() {
    echo ""
    echo "========================================="
    echo "           测试报告"
    echo "========================================="
    echo ""
    echo -e "${GREEN}通过: $TESTS_PASSED${NC}"
    echo -e "${RED}失败: $TESTS_FAILED${NC}"
    echo -e "${YELLOW}警告: $TESTS_WARNING${NC}"
    echo ""
    
    if [ $TESTS_FAILED -eq 0 ]; then
        echo -e "${GREEN}✓ 所有关键测试通过！${NC}"
        echo ""
        echo "部署成功！你可以："
        echo "1. 配置 VLESS 客户端连接"
        echo "2. 访问 Master 管理面板"
        echo "3. 查看详细日志："
        echo "   docker logs sui-gateway"
        echo "   docker logs sui-singbox"
        return 0
    else
        echo -e "${RED}✗ 有 $TESTS_FAILED 个测试失败${NC}"
        echo ""
        echo "请检查："
        echo "1. 容器日志: docker logs sui-gateway && docker logs sui-singbox"
        echo "2. 配置文件: /opt/sui-proxy/node/config/"
        echo "3. 网络配置: docker network inspect sui-master-net"
        return 1
    fi
}

# 主函数
main() {
    echo "========================================="
    echo "    SUI Proxy 部署测试"
    echo "    Sing-box 443 Fallback 架构"
    echo "========================================="
    echo ""
    
    # 检查是否为 root
    if [ "$EUID" -ne 0 ]; then
        echo "请使用 sudo 运行此脚本"
        exit 1
    fi
    
    # 运行所有测试
    test_port_bindings
    test_container_status
    test_docker_networks
    test_configuration_files
    test_http_access
    test_https_access
    test_tls_certificate
    test_container_connectivity
    test_logs_for_errors
    
    # 生成报告
    generate_report
}

# 运行主函数
main "$@"
