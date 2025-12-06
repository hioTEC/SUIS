#!/bin/bash
# 修复bcrypt生成问题

set -e

LOG_FILE="/var/log/sui-proxy/bcrypt-fix.log"
MAX_RETRIES=30
RETRY_DELAY=5

print_log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a $LOG_FILE
}

wait_for_container() {
    local container_name=$1
    local retries=0
    
    print_log "等待容器 $container_name 就绪..."
    
    while [ $retries -lt $MAX_RETRIES ]; do
        if docker ps --format '{{.Names}}' | grep -q "^${container_name}$"; then
            if docker exec $container_name echo "Container ready" > /dev/null 2>&1; then
                print_log "容器 $container_name 已就绪"
                return 0
            fi
        fi
        
        print_log "等待容器启动... ($((retries+1))/$MAX_RETRIES)"
        sleep $RETRY_DELAY
        ((retries++))
    done
    
    print_log "错误: 容器 $container_name 启动超时"
    return 1
}

fix_bcrypt_generation() {
    print_log "开始修复bcrypt生成..."
    
    # 方法1: 使用Python生成
    local python_script=$(cat << 'EOF'
import bcrypt
import sys

password = sys.argv[1] if len(sys.argv) > 1 else "default_password"
hashed = bcrypt.hashpw(password.encode('utf-8'), bcrypt.gensalt(rounds=12))
print(hashed.decode('utf-8'))
EOF
    )
    
    # 尝试生成bcrypt哈希
    if command -v python3 >/dev/null 2>&1; then
        print_log "使用Python生成bcrypt哈希..."
        if python3 -c "import bcrypt" >/dev/null 2>&1; then
            local hashed_password=$(python3 -c "$python_script" "admin123")
            echo "BCRYPT_PASSWORD=$hashed_password" >> /etc/sui-proxy/config.env
            print_log "bcrypt哈希生成成功"
            return 0
        fi
    fi
    
    # 方法2: 使用Node.js生成（回退方案）
    print_log "尝试使用Node.js生成bcrypt..."
    if command -v node >/dev/null 2>&1; then
        cat > /tmp/generate-bcrypt.js << 'EOF'
const bcrypt = require('bcrypt');
const saltRounds = 12;
const password = 'admin123';

bcrypt.hash(password, saltRounds, function(err, hash) {
    if (err) {
        console.error(err);
        process.exit(1);
    }
    console.log(hash);
});
EOF
        
        if node /tmp/generate-bcrypt.js 2>/dev/null; then
            local hashed_password=$(node /tmp/generate-bcrypt.js)
            echo "BCRYPT_PASSWORD=$hashed_password" >> /etc/sui-proxy/config.env
            print_log "使用Node.js生成bcrypt成功"
            return 0
        fi
    fi
    
    # 方法3: 使用openssl生成临时密码（最终回退）
    print_log "使用openssl生成临时密码..."
    local temp_password=$(openssl rand -base64 32 | tr -dc 'a-zA-Z0-9' | head -c 16)
    echo "TEMP_PASSWORD=$temp_password" >> /etc/sui-proxy/config.env
    echo "BCRYPT_FALLBACK=true" >> /etc/sui-proxy/config.env
    
    print_log "警告: 使用临时密码，请尽快在管理界面修改"
    return 0
}

# 等待关键容器就绪
wait_for_container "sui-master" || true
wait_for_container "sui-node" || true

# 修复bcrypt
fix_bcrypt_generation

print_log "bcrypt修复完成"