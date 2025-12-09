# SUI Proxy 部署和测试指南

## 前置要求

### 服务器要求
- Ubuntu 20.04+ 或 Debian 11+
- 至少 1GB RAM
- 2 个域名（Master 和 Node）已解析到服务器 IP
- 端口 80 和 443 可访问（防火墙已开放）

### 必需软件
```bash
# 安装 Docker
curl -fsSL https://get.docker.com | sh
sudo systemctl enable docker
sudo systemctl start docker

# 安装 Docker Compose
sudo apt-get update
sudo apt-get install -y docker-compose-plugin

# 安装测试工具
sudo apt-get install -y jq netcat-openbsd curl
```

## 部署步骤

### 1. 上传代码到服务器

```bash
# 在本地打包
tar -czf sui-proxy.tar.gz \
  install.sh \
  node/ \
  gateway/ \
  --exclude='node_modules' \
  --exclude='.git'

# 上传到服务器
scp sui-proxy.tar.gz user@your-server:/tmp/

# 在服务器上解压
ssh user@your-server
cd /tmp
tar -xzf sui-proxy.tar.gz
```

### 2. 运行安装脚本

```bash
# 赋予执行权限
chmod +x install.sh

# 运行安装（需要 root 权限）
sudo ./install.sh
```

安装脚本会提示你输入：
- Master 域名（例如：master.example.com）
- Node 域名（例如：node.example.com）
- ACME 邮箱（用于 Let's Encrypt 证书）

安装完成后会显示：
- VLESS UUID
- Hysteria2 密码
- AdGuard 管理员密码

**重要：保存这些凭证！**

### 3. 启动服务

```bash
# 启动 Gateway
cd /opt/sui-proxy/gateway
sudo docker compose up -d

# 等待 Gateway 启动（约 10 秒）
sleep 10

# 启动 Node（包含 Sing-box）
cd /opt/sui-proxy/node
sudo docker compose up -d
```

### 4. 验证部署

```bash
# 检查容器状态
sudo docker ps

# 应该看到以下容器运行中：
# - sui-gateway
# - sui-singbox

# 检查端口绑定
sudo ss -tlnp | grep -E ':(80|443)'

# 应该看到：
# - 0.0.0.0:80  (Caddy)
# - 0.0.0.0:443 (Sing-box)

# 查看日志
sudo docker logs sui-gateway
sudo docker logs sui-singbox
```

## 使用 AI-CLI 进行测试

### 安装 AI-CLI

```bash
# 安装 Node.js（如果还没有）
curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
sudo apt-get install -y nodejs

# 安装 AI-CLI（假设使用 OpenAI）
npm install -g @openai/cli
# 或者使用其他 AI CLI 工具
```

### 测试脚本

创建测试脚本 `test-deployment.sh`：

```bash
#!/bin/bash

# 测试配置
MASTER_DOMAIN="master.example.com"  # 替换为你的域名
NODE_DOMAIN="node.example.com"      # 替换为你的域名
VLESS_UUID="your-uuid-here"         # 从安装输出获取

echo "=== SUI Proxy 部署测试 ==="
echo ""

# 测试 1: 端口绑定
echo "测试 1: 检查端口绑定"
if ss -tlnp | grep -q ":80.*caddy"; then
    echo "✓ Caddy 正在监听端口 80"
else
    echo "✗ Caddy 未在端口 80 上监听"
fi

if ss -tlnp | grep -q ":443.*sing-box"; then
    echo "✓ Sing-box 正在监听端口 443"
else
    echo "✗ Sing-box 未在端口 443 上监听"
fi
echo ""

# 测试 2: HTTP 访问（Caddy）
echo "测试 2: HTTP 访问 Caddy"
if curl -s -o /dev/null -w "%{http_code}" http://localhost:80/health | grep -q "200"; then
    echo "✓ Caddy HTTP 健康检查通过"
else
    echo "✗ Caddy HTTP 健康检查失败"
fi
echo ""

# 测试 3: HTTPS 访问（通过 Sing-box fallback 到 Caddy）
echo "测试 3: HTTPS 访问（Sing-box → Caddy fallback）"
response=$(curl -k -s -o /dev/null -w "%{http_code}" https://${MASTER_DOMAIN}/ 2>/dev/null || echo "000")
if [ "$response" = "200" ] || [ "$response" = "301" ] || [ "$response" = "302" ]; then
    echo "✓ HTTPS 访问成功（状态码: $response）"
else
    echo "✗ HTTPS 访问失败（状态码: $response）"
fi
echo ""

# 测试 4: Docker 网络连接
echo "测试 4: Docker 网络连接"
if docker network inspect sui-master-net &>/dev/null; then
    echo "✓ sui-master-net 网络存在"
else
    echo "✗ sui-master-net 网络不存在"
fi

if docker network inspect sui-node-net &>/dev/null; then
    echo "✓ sui-node-net 网络存在"
else
    echo "✗ sui-node-net 网络不存在"
fi
echo ""

# 测试 5: 容器健康状态
echo "测试 5: 容器健康状态"
gateway_health=$(docker inspect --format='{{.State.Health.Status}}' sui-gateway 2>/dev/null || echo "unknown")
singbox_status=$(docker inspect --format='{{.State.Status}}' sui-singbox 2>/dev/null || echo "unknown")

echo "Gateway 健康状态: $gateway_health"
echo "Sing-box 运行状态: $singbox_status"
echo ""

# 测试 6: 配置文件验证
echo "测试 6: 配置文件验证"
if jq empty /opt/sui-proxy/node/config/singbox/config.json 2>/dev/null; then
    echo "✓ Sing-box 配置 JSON 有效"
    
    # 检查 fallback 配置
    if jq -e '.inbounds[] | select(.type == "vless") | .fallback' /opt/sui-proxy/node/config/singbox/config.json &>/dev/null; then
        echo "✓ Sing-box fallback 配置存在"
    else
        echo "✗ Sing-box fallback 配置缺失"
    fi
else
    echo "✗ Sing-box 配置 JSON 无效"
fi
echo ""

# 测试 7: TLS 证书
echo "测试 7: TLS 证书检查"
cert_info=$(echo | openssl s_client -connect ${NODE_DOMAIN}:443 -servername ${NODE_DOMAIN} 2>/dev/null | openssl x509 -noout -subject 2>/dev/null || echo "")
if [ -n "$cert_info" ]; then
    echo "✓ TLS 证书已配置"
    echo "  $cert_info"
else
    echo "⚠ TLS 证书尚未配置（可能需要等待 ACME 完成）"
fi
echo ""

echo "=== 测试完成 ==="
```

### 运行测试

```bash
# 赋予执行权限
chmod +x test-deployment.sh

# 运行测试
sudo ./test-deployment.sh
```

## 使用 AI-CLI 进行智能测试

### 方案 1: 使用 AI 分析日志

```bash
# 收集日志
sudo docker logs sui-gateway > gateway.log 2>&1
sudo docker logs sui-singbox > singbox.log 2>&1

# 使用 AI-CLI 分析
ai "分析这些 Docker 日志，找出任何错误或警告：" < gateway.log
ai "检查 Sing-box 日志中的 fallback 相关信息：" < singbox.log
```

### 方案 2: 使用 AI 生成测试用例

```bash
# 让 AI 生成 VLESS 客户端配置
ai "根据以下信息生成 VLESS 客户端配置：
域名: ${NODE_DOMAIN}
UUID: ${VLESS_UUID}
端口: 443
协议: VLESS + TLS"

# 让 AI 生成 curl 测试命令
ai "生成测试 HTTPS fallback 的 curl 命令，目标域名是 ${MASTER_DOMAIN}"
```

### 方案 3: 使用 AI 诊断问题

```bash
# 如果遇到问题，让 AI 帮助诊断
ai "我的 Sing-box 无法启动，这是错误日志：$(sudo docker logs sui-singbox 2>&1 | tail -20)"

# 检查配置问题
ai "检查这个 Sing-box 配置是否正确：" < /opt/sui-proxy/node/config/singbox/config.json
```

## 常见问题排查

### 问题 1: 端口 80 或 443 被占用

```bash
# 查看占用端口的进程
sudo lsof -i :80
sudo lsof -i :443

# 停止占用的服务
sudo systemctl stop nginx  # 如果是 nginx
sudo systemctl stop apache2  # 如果是 apache
```

### 问题 2: 容器无法启动

```bash
# 查看详细日志
sudo docker logs sui-gateway --tail 100
sudo docker logs sui-singbox --tail 100

# 检查配置文件
sudo jq . /opt/sui-proxy/node/config/singbox/config.json
sudo cat /opt/sui-proxy/node/config/caddy/Caddyfile
```

### 问题 3: ACME 证书获取失败

```bash
# 确保域名已正确解析
dig ${NODE_DOMAIN}
dig ${MASTER_DOMAIN}

# 确保端口 80 可从外部访问（用于 HTTP-01 挑战）
curl -v http://${MASTER_DOMAIN}/.well-known/acme-challenge/test

# 查看 Caddy 日志中的 ACME 信息
sudo docker logs sui-gateway | grep -i acme
```

### 问题 4: Fallback 不工作

```bash
# 测试 Sing-box 到 Gateway 的连接
sudo docker exec sui-singbox ping -c 3 sui-gateway

# 检查网络配置
sudo docker network inspect sui-master-net
sudo docker network inspect sui-node-net

# 验证 fallback 配置
sudo jq '.inbounds[] | select(.type == "vless") | .fallback' \
  /opt/sui-proxy/node/config/singbox/config.json
```

## 性能测试

### 测试 VLESS 代理性能

```bash
# 使用 iperf3 测试（需要配置 VLESS 客户端）
# 这需要在客户端机器上运行

# 测试延迟
ping -c 10 ${NODE_DOMAIN}

# 测试 HTTPS 响应时间
time curl -k https://${MASTER_DOMAIN}/
```

### 测试 Fallback 性能

```bash
# 测试直接访问 Caddy (HTTP)
ab -n 1000 -c 10 http://localhost:80/health

# 测试通过 Sing-box fallback 访问 (HTTPS)
ab -n 1000 -c 10 https://${MASTER_DOMAIN}/
```

## 清理和重新部署

```bash
# 停止所有容器
cd /opt/sui-proxy/node
sudo docker compose down

cd /opt/sui-proxy/gateway
sudo docker compose down

# 清理配置（可选）
sudo rm -rf /opt/sui-proxy

# 重新运行安装
sudo ./install.sh
```

## 监控建议

### 使用 Docker 监控

```bash
# 实时查看容器状态
watch -n 2 'docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"'

# 监控资源使用
docker stats sui-gateway sui-singbox
```

### 设置日志轮转

```bash
# 配置 Docker 日志轮转
sudo tee /etc/docker/daemon.json > /dev/null <<EOF
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  }
}
EOF

sudo systemctl restart docker
```

## 下一步

部署成功后，你可以：

1. 配置 VLESS 客户端连接到 Node 域名
2. 访问 Master 域名的管理面板
3. 配置 AdGuard Home（如果需要）
4. 设置监控和告警
5. 配置备份策略

## 支持

如果遇到问题：
1. 查看日志：`sudo docker logs sui-gateway` 和 `sudo docker logs sui-singbox`
2. 检查配置文件是否正确生成
3. 验证域名 DNS 解析
4. 确保防火墙规则正确
5. 使用 AI-CLI 分析错误信息
