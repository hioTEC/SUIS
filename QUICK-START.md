# SUI Proxy 快速部署指南

## 5 分钟快速部署

### 前提条件

1. **服务器**: Ubuntu 20.04+ 或 Debian 11+
2. **域名**: 两个已解析到服务器 IP 的域名
3. **端口**: 80 和 443 已开放

### 步骤 1: 准备服务器

```bash
# SSH 登录服务器
ssh root@your-server-ip

# 安装 Docker
curl -fsSL https://get.docker.com | sh

# 安装必要工具
apt-get update && apt-get install -y jq git
```

### 步骤 2: 下载代码

**方案 A: 使用一键部署脚本（推荐）**

```bash
# 下载并运行一键部署脚本
curl -fsSL https://raw.githubusercontent.com/your-username/sui-proxy/main/server-deploy.sh | sudo bash
```

**方案 B: 手动克隆仓库**

```bash
# 克隆仓库
cd /tmp
git clone https://github.com/your-username/sui-proxy.git
cd sui-proxy
```

**方案 C: 从本地上传**

```bash
# 在本地打包
tar -czf sui-proxy.tar.gz .

# 上传到服务器
scp sui-proxy.tar.gz root@your-server:/tmp/

# 在服务器上解压
ssh root@your-server
cd /tmp
tar -xzf sui-proxy.tar.gz
```

### 步骤 3: 运行安装

```bash
# 赋予执行权限
chmod +x install.sh

# 运行安装
./install.sh
```

安装过程中会提示输入：
- Master 域名（例如：`master.example.com`）
- Node 域名（例如：`node.example.com`）
- 邮箱（用于 Let's Encrypt）

### 步骤 4: 启动服务

```bash
# 启动 Gateway
cd /opt/sui-proxy/gateway
docker compose up -d

# 等待 10 秒
sleep 10

# 启动 Node
cd /opt/sui-proxy/node
docker compose up -d
```

### 步骤 5: 验证部署

```bash
# 下载测试脚本
cd /tmp/sui-proxy
chmod +x test-deployment.sh

# 运行测试
./test-deployment.sh
```

## 使用 AI-CLI 进行智能测试

### 安装 AI-CLI

```bash
# 方案 1: 使用 OpenAI CLI
npm install -g @openai/cli
export OPENAI_API_KEY="your-api-key"

# 方案 2: 使用 Anthropic Claude CLI
pip install anthropic-cli
export ANTHROPIC_API_KEY="your-api-key"

# 方案 3: 使用本地 Ollama
curl -fsSL https://ollama.ai/install.sh | sh
ollama pull llama2
alias ai='ollama run llama2'
```

### 运行 AI 辅助测试

```bash
# 赋予执行权限
chmod +x ai-test-helper.sh

# 交互式菜单
./ai-test-helper.sh

# 或直接运行特定测试
./ai-test-helper.sh deploy    # 分析部署状态
./ai-test-helper.sh config    # 分析配置
./ai-test-helper.sh error     # 诊断错误
./ai-test-helper.sh all       # 全面检查
```

## AI-CLI 测试示例

### 1. 分析部署状态

```bash
./ai-test-helper.sh deploy
```

AI 会分析：
- 容器运行状态
- 端口绑定情况
- 网络配置
- 日志中的问题

### 2. 生成客户端配置

```bash
./ai-test-helper.sh client
```

AI 会生成：
- V2Ray 配置
- Clash 配置
- Sing-box 客户端配置

### 3. 诊断问题

```bash
./ai-test-helper.sh error
```

AI 会：
- 分析错误日志
- 找出根本原因
- 提供解决方案

### 4. 性能分析

```bash
./ai-test-helper.sh perf
```

AI 会：
- 评估资源使用
- 分析连接数
- 提供优化建议

## 手动测试命令

### 检查端口

```bash
# 查看端口绑定
ss -tlnp | grep -E ':(80|443)'

# 应该看到：
# 0.0.0.0:80  ... caddy
# 0.0.0.0:443 ... sing-box
```

### 检查容器

```bash
# 查看运行中的容器
docker ps

# 查看日志
docker logs sui-gateway
docker logs sui-singbox
```

### 测试 HTTP

```bash
# 测试 Caddy (端口 80)
curl -v http://localhost:80/health
```

### 测试 HTTPS Fallback

```bash
# 测试通过 Sing-box fallback 到 Caddy
curl -k -v https://your-master-domain.com/
```

### 测试网络连接

```bash
# 测试容器间连接
docker exec sui-singbox ping -c 3 sui-gateway
```

### 检查配置

```bash
# 验证 Sing-box 配置
jq . /opt/sui-proxy/node/config/singbox/config.json

# 检查 fallback 配置
jq '.inbounds[] | select(.type == "vless") | .fallback' \
  /opt/sui-proxy/node/config/singbox/config.json

# 查看 Caddyfile
cat /opt/sui-proxy/node/config/caddy/Caddyfile
```

## 常见问题

### Q: 端口被占用怎么办？

```bash
# 查看占用端口的进程
lsof -i :80
lsof -i :443

# 停止占用的服务
systemctl stop nginx
systemctl stop apache2
```

### Q: 容器无法启动？

```bash
# 查看详细日志
docker logs sui-gateway --tail 100
docker logs sui-singbox --tail 100

# 使用 AI 分析
./ai-test-helper.sh error
```

### Q: HTTPS 无法访问？

```bash
# 检查域名解析
dig your-domain.com

# 检查防火墙
ufw status
ufw allow 80/tcp
ufw allow 443/tcp

# 检查证书
openssl s_client -connect your-domain.com:443 -servername your-domain.com
```

### Q: Fallback 不工作？

```bash
# 测试容器连接
docker exec sui-singbox ping sui-gateway

# 检查网络
docker network inspect sui-master-net
docker network inspect sui-node-net

# 验证 fallback 配置
jq '.inbounds[0].fallback' /opt/sui-proxy/node/config/singbox/config.json
```

## 获取凭证

```bash
# 查看保存的配置
cat /opt/sui-proxy/config/config.env

# 包含：
# - VLESS_UUID
# - HY2_PASSWORD
# - ADGUARD_ADMIN_PASS
```

## 配置客户端

### VLESS 配置示例

```json
{
  "outbounds": [
    {
      "protocol": "vless",
      "settings": {
        "vnext": [
          {
            "address": "node.example.com",
            "port": 443,
            "users": [
              {
                "id": "your-uuid-here",
                "encryption": "none",
                "flow": "xtls-rprx-vision"
              }
            ]
          }
        ]
      },
      "streamSettings": {
        "network": "tcp",
        "security": "tls",
        "tlsSettings": {
          "serverName": "node.example.com"
        }
      }
    }
  ]
}
```

## 监控和维护

### 查看实时状态

```bash
# 实时查看容器状态
watch -n 2 'docker ps --format "table {{.Names}}\t{{.Status}}"'

# 实时查看资源使用
docker stats sui-gateway sui-singbox
```

### 查看日志

```bash
# 实时日志
docker logs -f sui-gateway
docker logs -f sui-singbox

# 最近日志
docker logs sui-gateway --tail 50
docker logs sui-singbox --tail 50
```

### 重启服务

```bash
# 重启 Gateway
cd /opt/sui-proxy/gateway
docker compose restart

# 重启 Node
cd /opt/sui-proxy/node
docker compose restart
```

## 下一步

1. ✅ 部署完成
2. ✅ 测试通过
3. 📱 配置客户端
4. 🌐 访问管理面板
5. 📊 设置监控
6. 🔒 配置备份

## 支持

遇到问题？

1. 运行测试脚本：`./test-deployment.sh`
2. 使用 AI 诊断：`./ai-test-helper.sh error`
3. 查看日志：`docker logs sui-gateway && docker logs sui-singbox`
4. 查看文档：`DEPLOYMENT.md` 和 `TROUBLESHOOTING.md`

## 性能优化建议

部署成功后，可以考虑：

1. **启用 BBR 拥塞控制**
```bash
echo "net.core.default_qdisc=fq" >> /etc/sysctl.conf
echo "net.ipv4.tcp_congestion_control=bbr" >> /etc/sysctl.conf
sysctl -p
```

2. **配置日志轮转**
```bash
# 在 /etc/docker/daemon.json 中添加
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  }
}
```

3. **设置自动更新**
```bash
# 创建更新脚本
cat > /opt/sui-proxy/update.sh << 'EOF'
#!/bin/bash
cd /opt/sui-proxy/gateway && docker compose pull && docker compose up -d
cd /opt/sui-proxy/node && docker compose pull && docker compose up -d
EOF

chmod +x /opt/sui-proxy/update.sh

# 添加到 crontab（每周日凌晨 3 点）
echo "0 3 * * 0 /opt/sui-proxy/update.sh" | crontab -
```

祝部署顺利！🚀
