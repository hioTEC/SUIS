#!/bin/bash
# TLS证书自动更新和管理脚本

set -e

CONFIG_DIR="/etc/sui-proxy"
LOG_DIR="/var/log/sui-proxy"
INSTALL_DIR="/opt/sui-proxy"
DOMAIN=""
EMAIL=""

# 加载配置
load_config() {
    if [ -f "$CONFIG_DIR/config.env" ]; then
        source $CONFIG_DIR/config.env
    else
        echo "错误: 配置文件不存在"
        exit 1
    fi
}

# 申请新证书
request_new_cert() {
    echo "申请新的Let's Encrypt证书..."
    
    # 临时停止Caddy释放80端口
    systemctl stop caddy
    
    certbot certonly --standalone --preferred-challenges http \
        -d "*.$DOMAIN" -d "$DOMAIN" \
        --email "$EMAIL" --agree-tos --no-eff-email \
        --force-renewal
    
    # 重新启动Caddy
    systemctl start caddy
    
    if [ $? -eq 0 ]; then
        echo "证书申请成功"
        sync_certificates
        return 0
    else
        echo "证书申请失败"
        return 1
    fi
}

# 同步证书到Singbox
sync_certificates() {
    echo "同步证书到Singbox..."
    
    local cert_dir="$INSTALL_DIR/certificates"
    local live_cert_dir="/etc/letsencrypt/live/$DOMAIN"
    
    if [ -f "$live_cert_dir/fullchain.pem" ] && [ -f "$live_cert_dir/privkey.pem" ]; then
        # 备份旧证书
        cp "$cert_dir/fullchain.pem" "$cert_dir/fullchain.pem.backup.$(date +%Y%m%d)" 2>/dev/null || true
        cp "$cert_dir/privkey.pem" "$cert_dir/privkey.pem.backup.$(date +%Y%m%d)" 2>/dev/null || true
        
        # 复制新证书
        cp "$live_cert_dir/fullchain.pem" "$cert_dir/fullchain.pem"
        cp "$live_cert_dir/privkey.pem" "$cert_dir/privkey.pem"
        
        # 设置权限
        chmod 644 "$cert_dir/fullchain.pem"
        chmod 600 "$cert_dir/privkey.pem"
        chown sui-proxy:sui-proxy "$cert_dir"/*
        
        echo "证书同步完成"
        
        # 重启Singbox服务
        systemctl restart singbox
        echo "Singbox服务已重启"
        
        # 记录日志
        echo "$(date): 证书更新成功" >> "$LOG_DIR/cert-renewal.log"
        
        return 0
    else
        echo "错误: 证书文件不存在"
        return 1
    fi
}

# 检查证书有效期
check_cert_expiry() {
    echo "检查证书有效期..."
    
    local cert_file="/etc/letsencrypt/live/$DOMAIN/fullchain.pem"
    
    if [ -f "$cert_file" ]; then
        local expiry_date=$(openssl x509 -enddate -noout -in "$cert_file" | cut -d= -f2)
        local expiry_seconds=$(date -d "$expiry_date" +%s)
        local current_seconds=$(date +%s)
        local days_left=$(( (expiry_seconds - current_seconds) / 86400 ))
        
        echo "证书有效期: $expiry_date"
        echo "剩余天数: $days_left 天"
        
        if [ $days_left -lt 7 ]; then
            echo "证书即将过期，开始更新..."
            if request_new_cert; then
                return 0
            else
                return 1
            fi
        elif [ $days_left -lt 30 ]; then
            echo "证书将在30天内过期，建议提前更新"
            read -p "是否立即更新证书? [y/N]: " choice
            if [[ "$choice" =~ ^[Yy]$ ]]; then
                request_new_cert
            fi
            return 0
        else
            echo "证书有效期内，无需更新"
            return 0
        fi
    else
        echo "错误: 证书文件不存在"
        return 1
    fi
}

# 切换证书类型
switch_cert_type() {
    echo "选择证书类型:"
    echo "1) Let's Encrypt (自动)"
    echo "2) 自签名"
    echo "3) 自定义证书"
    
    read -p "请选择: " choice
    
    case $choice in
        1)
            echo "切换到Let's Encrypt证书..."
            if [ -z "$EMAIL" ]; then
                read -p "请输入邮箱地址: " EMAIL
                echo "EMAIL=$EMAIL" >> "$CONFIG_DIR/config.env"
            fi
            request_new_cert
            ;;
        2)
            echo "切换到自签名证书..."
            "$INSTALL_DIR/scripts/generate-selfsigned.sh"
            sync_certificates
            ;;
        3)
            echo "请将自定义证书文件放置在:"
            echo "  - $INSTALL_DIR/certificates/fullchain.pem"
            echo "  - $INSTALL_DIR/certificates/privkey.pem"
            read -p "放置完成后按Enter键继续..." dummy
            sync_certificates
            ;;
        *)
            echo "无效选择"
            ;;
    esac
}

# 查看证书信息
show_cert_info() {
    local cert_file="/etc/letsencrypt/live/$DOMAIN/fullchain.pem"
    
    if [ -f "$cert_file" ]; then
        echo "证书信息:"
        echo "-----------"
        openssl x509 -in "$cert_file" -text -noout | grep -E "Subject:|Issuer:|Not Before:|Not After :|DNS:"
        
        echo -e "\n证书路径:"
        echo "  - 公钥: $cert_file"
        echo "  - 私钥: /etc/letsencrypt/live/$DOMAIN/privkey.pem"
        echo "  - 副本: $INSTALL_DIR/certificates/"
    else
        echo "未找到Let's Encrypt证书"
        
        # 检查自签名证书
        local self_signed_cert="$INSTALL_DIR/certificates/fullchain.pem"
        if [ -f "$self_signed_cert" ]; then
            echo -e "\n发现自签名证书:"
            openssl x509 -in "$self_signed_cert" -text -noout | grep -E "Subject:|Issuer:|Not Before:|Not After :"
        fi
    fi
}

# 手动续期证书
manual_renew() {
    echo "手动续期证书..."
    
    if certbot renew --force-renewal; then
        echo "证书续期成功"
        sync_certificates
        return 0
    else
        echo "证书续期失败"
        return 1
    fi
}

# 测试HTTPS连接
test_https() {
    local test_url="https://$DOMAIN"
    
    echo "测试HTTPS连接: $test_url"
    
    if curl -s -o /dev/null -w "%{http_code}" --connect-timeout 10 "$test_url"; then
        echo -e "\nHTTPS连接正常"
        
        # 测试证书链
        echo -e "\n测试证书链..."
        openssl s_client -connect "$DOMAIN:443" -servername "$DOMAIN" -showcerts </dev/null 2>/dev/null | \
            grep -E "Verify|Certificate chain"
        
        return 0
    else
        echo "HTTPS连接失败"
        return 1
    fi
}

# 主菜单
show_menu() {
    echo ""
    echo "TLS证书管理菜单"
    echo "================="
    echo "1) 检查证书状态"
    echo "2) 手动续期证书"
    echo "3) 申请新证书"
    echo "4) 切换证书类型"
    echo "5) 测试HTTPS连接"
    echo "6) 查看证书信息"
    echo "7) 设置自动续期"
    echo "8) 退出"
    echo ""
}

# 设置自动续期
setup_auto_renewal() {
    echo "设置自动证书续期..."
    
    # 创建续期脚本
    cat > /etc/cron.weekly/sui-cert-renew << 'EOF'
#!/bin/bash
# 自动证书续期脚本

CONFIG_DIR="/etc/sui-proxy"
LOG_FILE="/var/log/sui-proxy/cert-auto-renew.log"

if [ -f "$CONFIG_DIR/config.env" ]; then
    source $CONFIG_DIR/config.env
    /opt/sui-proxy/scripts/cert-renewal.sh --check >> "$LOG_FILE" 2>&1
fi
EOF
    
    chmod +x /etc/cron.weekly/sui-cert-renew
    
    # 创建systemd定时器
    cat > /etc/systemd/system/sui-cert-renew.timer << EOF
[Unit]
Description=SUI Proxy证书自动续期定时器
Requires=sui-cert-renew.service

[Timer]
OnCalendar=weekly
Persistent=true

[Install]
WantedBy=timers.target
EOF
    
    cat > /etc/systemd/system/sui-cert-renew.service << EOF
[Unit]
Description=SUI Proxy证书自动续期
After=network.target

[Service]
Type=oneshot
ExecStart=/opt/sui-proxy/scripts/cert-renewal.sh --check
User=root
EOF
    
    systemctl daemon-reload
    systemctl enable sui-cert-renew.timer
    systemctl start sui-cert-renew.timer
    
    echo "自动续期已设置:"
    echo "  - 每周执行: /etc/cron.weekly/sui-cert-renew"
    echo "  - systemd定时器: sui-cert-renew.timer"
    echo "  - 日志: /var/log/sui-proxy/cert-auto-renew.log"
}

# 主函数
main() {
    # 加载配置
    load_config
    
    if [ $# -eq 0 ]; then
        # 交互模式
        while true; do
            show_menu
            read -p "请选择操作 (1-8): " choice
            
            case $choice in
                1)
                    check_cert_expiry
                    ;;
                2)
                    manual_renew
                    ;;
                3)
                    request_new_cert
                    ;;
                4)
                    switch_cert_type
                    ;;
                5)
                    test_https
                    ;;
                6)
                    show_cert_info
                    ;;
                7)
                    setup_auto_renewal
                    ;;
                8)
                    echo "退出"
                    exit 0
                    ;;
                *)
                    echo "无效选择"
                    ;;
            esac
            
            echo ""
            read -p "按Enter键继续..." dummy
        done
    else
        # 命令行模式
        case $1 in
            --check)
                check_cert_expiry
                ;;
            --renew)
                manual_renew
                ;;
            --test)
                test_https
                ;;
            --info)
                show_cert_info
                ;;
            --auto-setup)
                setup_auto_renewal
                ;;
            *)
                echo "用法: $0 [选项]"
                echo "选项:"
                echo "  --check       检查证书状态"
                echo "  --renew       手动续期证书"
                echo "  --test        测试HTTPS连接"
                echo "  --info        查看证书信息"
                echo "  --auto-setup  设置自动续期"
                echo ""
                echo "无选项时进入交互模式"
                exit 1
                ;;
        esac
    fi
}

# 运行主函数
main "$@"