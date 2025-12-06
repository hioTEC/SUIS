#!/bin/bash
# 诊断和修复页面无法打开的问题

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

LOG_FILE="/var/log/sui-proxy/diagnose.log"
REPORT_FILE="/tmp/sui-diagnose-report.txt"

print_status() {
    echo -e "${GREEN}[✓]${NC} $1" | tee -a $LOG_FILE
}

print_warning() {
    echo -e "${YELLOW}[!]${NC} $1" | tee -a $LOG_FILE
}

print_error() {
    echo -e "${RED}[✗]${NC} $1" | tee -a $LOG_FILE
}

check_port() {
    local port=$1
    local service=$2
    
    echo -n "检查端口 $port ($service)... "
    
    # 检查端口监听
    if ss -tln | grep -q ":$port "; then
        echo -e "${GREEN}监听中${NC}"
        return 0
    else
        echo -e "${RED}未监听${NC}"
        return 1
    fi
}

check_service() {
    local service=$1
    
    echo -n "检查服务 $service... "
    
    if systemctl is-active --quiet $service; then
        echo -e "${GREEN}运行中${NC}"
        return 0
    else
        echo -e "${RED}未运行${NC}"
        return 1
    fi
}

check_certificate() {
    local domain=$1
    
    echo -n "检查证书 $domain... "
    
    if [ -f "/etc/letsencrypt/live/$domain/fullchain.pem" ]; then
        local expiry=$(openssl x509 -enddate -noout -in "/etc/letsencrypt/live/$domain/fullchain.pem" 2>/dev/null | cut -d= -f2)
        local days_left=$(( ($(date -d "$expiry" +%s) - $(date +%s)) / 86400 ))
        
        if [ $days_left -gt 0 ]; then
            echo -e "${GREEN}有效 (剩余 $days_left 天)${NC}"
            return 0
        else
            echo -e "${RED}已过期${NC}"
            return 1
        fi
    else
        echo -e "${RED}证书不存在${NC}"
        return 1
    fi
}

check_dns() {
    local domain=$1
    
    echo -n "检查DNS解析 $domain... "
    
    if dig +short $domain | grep -q '^[0-9]\+\.[0-9]\+\.[0-9]\+\.[0-9]\+$'; then
        local ip=$(dig +short $domain | head -1)
        echo -e "${GREEN}已解析到 $ip${NC}"
        return 0
    else
        echo -e "${RED}解析失败${NC}"
        return 1
    fi
}

check_firewall() {
    echo -n "检查防火墙... "
    
    if command -v ufw >/dev/null 2>&1; then
        if ufw status | grep -q "Status: active"; then
            echo -e "${YELLOW}UFW启用中${NC}"
            return 2
        else
            echo -e "${GREEN}UFW未启用${NC}"
            return 0
        fi
    elif command -v firewall-cmd >/dev/null 2>&1; then
        if firewall-cmd --state 2>/dev/null | grep -q "running"; then
            echo -e "${YELLOW}FirewallD启用中${NC}"
            return 2
        fi
    else
        echo -e "${GREEN}防火墙未检测到${NC}"
        return 0
    fi
}

check_connectivity() {
    local domain=$1
    local port=$2
    
    echo -n "检查连接 $domain:$port... "
    
    if timeout 5 curl -s -o /dev/null -w "%{http_code}" https://$domain:$port/health 2>/dev/null | grep -q "200\|401\|403"; then
        echo -e "${GREEN}可访问${NC}"
        return 0
    else
        echo -e "${RED}不可访问${NC}"
        return 1
    fi
}

fix_port_conflict() {
    local port=$1
    
    print_warning "修复端口 $port 冲突..."
    
    # 查找占用端口的进程
    local pids=$(lsof -ti :$port)
    
    if [ -n "$pids" ]; then
        for pid in $pids; do
            local process=$(ps -p $pid -o comm=)
            print_warning "  进程 $pid ($process) 占用端口 $port"
            
            # 如果不是我们的服务，询问是否终止
            if [[ ! "$process" =~ (caddy|singbox|sui-) ]]; then
                read -p "是否终止进程 $pid ($process)? [y/N]: " confirm
                if [[ "$confirm" =~ ^[Yy]$ ]]; then
                    kill -9 $pid
                    print_status "已终止进程 $pid"
                fi
            fi
        done
    fi
}

fix_certificate() {
    local domain=$1
    
    print_warning "修复证书 $domain..."
    
    if [ -n "$EMAIL" ]; then
        # 尝试续期证书
        if certbot renew --cert-name $domain --quiet; then
            print_status "证书续期成功"
            
            # 同步证书到Singbox
            /opt/sui-proxy/scripts/sync-certs.sh
            
            # 重启服务
            systemctl restart caddy singbox
        else
            print_error "证书续期失败，尝试重新申请..."
            
            # 停止占用80端口的服务
            systemctl stop caddy apache2 nginx 2>/dev/null || true
            
            # 申请新证书
            certbot certonly --standalone --preferred-challenges http \
                -d "$domain" -d "*.$domain" \
                --email "$EMAIL" --agree-tos --no-eff-email --force-renewal
            
            if [ $? -eq 0 ]; then
                print_status "证书申请成功"
                /opt/sui-proxy/scripts/sync-certs.sh
                systemctl start caddy
            else
                print_error "证书申请失败，使用自签名证书"
                /opt/sui-proxy/scripts/generate-selfsigned.sh
            fi
        fi
    else
        print_error "无邮箱配置，无法修复Let's Encrypt证书"
    fi
}

generate_report() {
    echo "生成诊断报告..." | tee -a $LOG_FILE
    
    cat > $REPORT_FILE << EOF
SUI Proxy 诊断报告
生成时间: $(date)
系统: $(uname -a)

=== 服务状态 ===
Caddy: $(systemctl is-active caddy)
Singbox: $(systemctl is-active singbox)

=== 端口监听 ===
$(ss -tln | grep -E ':80|:443|:8443|:8080')

=== 证书状态 ===
$(for cert in /etc/letsencrypt/live/*; do 
    [ -d "$cert" ] && domain=$(basename $cert) && \
    expiry=$(openssl x509 -enddate -noout -in "$cert/fullchain.pem" 2>/dev/null | cut -d= -f2) && \
    echo "$domain: $expiry"; 
done)

=== 最近错误日志 ===
$(journalctl -u caddy -u singbox --since "1 hour ago" | grep -i error | tail -20)

=== 建议操作 ===
EOF
    
    print_status "诊断报告已保存到: $REPORT_FILE"
}

# 加载配置
if [ -f "/etc/sui-proxy/config.env" ]; then
    source /etc/sui-proxy/config.env
else
    print_error "配置文件不存在"
    exit 1
fi

# 执行诊断
echo "开始系统诊断..." | tee $LOG_FILE
echo "======================" | tee -a $LOG_FILE

# 检查服务
check_service caddy
check_service singbox

# 检查端口
check_port 80 "HTTP"
check_port 443 "HTTPS"
check_port $VLESS_PORT "VLESS"
check_port $ADMIN_PORT "管理面板"

# 检查证书
if [ -n "$DOMAIN" ]; then
    check_certificate $DOMAIN
    check_dns $DOMAIN
    check_dns "master.$DOMAIN"
    check_dns "node.$DOMAIN"
fi

# 检查防火墙
check_firewall

# 检查连接性
if [ -n "$DOMAIN" ]; then
    check_connectivity "master.$DOMAIN" 443
fi

echo "======================" | tee -a $LOG_FILE

# 交互式修复
read -p "是否自动修复发现的问题? [y/N]: " fix_confirm

if [[ "$fix_confirm" =~ ^[Yy]$ ]]; then
    # 修复端口冲突
    for port in 80 443 $VLESS_PORT $ADMIN_PORT; do
        if ! check_port $port "测试" 2>/dev/null; then
            fix_port_conflict $port
        fi
    done
    
    # 修复证书
    if [ -n "$DOMAIN" ] && ! check_certificate $DOMAIN 2>/dev/null; then
        fix_certificate $DOMAIN
    fi
    
    # 重启服务
    print_warning "重启服务..."
    systemctl restart caddy singbox
    
    # 再次检查
    sleep 3
    echo "修复后检查..." | tee -a $LOG_FILE
    check_service caddy
    check_service singbox
fi

# 生成报告
generate_report

echo "诊断完成。详细日志: $LOG_FILE"
echo "请查看报告: $REPORT_FILE"