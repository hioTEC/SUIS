# 服务器端部署指南

## 🚀 从 GitHub 一键部署

### 方法 1: 使用一键部署脚本（最简单）

```bash
# 直接运行（会自动下载并部署）
curl -fsSL https://raw.githubusercontent.com/your-username/sui-proxy/main/server-deploy.sh | sudo bash
```

这个脚本会自动：
1. ✅ 检查系统环境
2. ✅ 安装 Docker 和依赖
3. ✅ 从 GitHub 下载最新代码
4. ✅ 运行安装配置
5. ✅ 启动所有服务
6. ✅ 运行测试验证
7. ✅ 显示配置信息

### 方法 2: 手动克隆并部署

```bash
# 1. 克隆仓库
git clone https://github.com/your-username/sui-proxy.git
cd sui-proxy

# 2. 运行安装
sudo ./install.sh

# 3. 启动服务
cd /opt/sui-proxy/gateway
sudo docker compose up -d

sleep 10

cd /opt/sui-proxy/node
sudo docker compose up -d

# 4. 验证部署
sudo ./test-deployment.sh
```

## 📝 部署前准备

### 1. 准备域名

你需要两个域名，并将它们解析到服务器 IP：

```bash
# 检查域名解析
dig master.example.com
dig node.example.com

# 或使用 nslookup
nslookup master.example.com
nslookup node.example.com
```

### 2. 开放端口

确保防火墙开放以下端口：

```bash
# Ubuntu/Debian (UFW)
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
sudo ufw allow 22/tcp  # SSH

# CentOS/RHEL (firewalld)
sudo firewall-cmd --permanent --add-port=80/tcp
sudo firewall-cmd --permanent --add-port=443/tcp
sudo firewall-cmd --reload

# 验证端口开放
sudo ufw status
```

### 3. 检查端口占用

```bash
# 检查端口 80 和 443 是否被占用
sudo lsof -i :80
sudo lsof -i :443

# 如果被占用，停止占用的服务
sudo systemctl stop nginx
sudo systemctl stop apache2
```

## 🔧 配置说明

### 安装过程中的输入

安装脚本会提示你输入：

1. **Master 域名**
   - 例如：`master.example.com`
   - 用于管理面板访问

2. **Node 域名**
   - 例如：`node.example.com`
   - 用于代理服务

3. **ACME 邮箱**
   - 例如：`admin@example.com`
   - 用于 Let's Encrypt 证书通知

### 自动生成的凭证

安装完成后会显示：

- **VLESS UUID**: 用于 VLESS 客户端
- **Hysteria2 密码**: 用于 Hysteria2 客户端
- **AdGuard 密码**: 用于 AdGuard Home 管理

**重要**: 请保存这些凭证！

配置文件位置：`/opt/sui-proxy/config/config.env`

## 📊 验证部署

### 1. 检查容器状态

```bash
# 查看运行中的容器
docker ps

# 应该看到：
# - sui-gateway
# - sui-singbox
```

### 2. 检查端口监听

```bash
# 查看端口绑定
sudo ss -tlnp | grep -E ':(80|443)'

# 应该看到：
# 0.0.0.0:80  ... caddy
# 0.0.0.0:443 ... sing-box
```

### 3. 运行自动化测试

```bash
cd /tmp/sui-proxy-deploy  # 或你的代码目录
sudo ./test-deployment.sh
```

### 4. 查看日志

```bash
# Gateway 日志
docker logs sui-gateway

# Sing-box 日志
docker logs sui-singbox

# 实时日志
docker logs -f sui-singbox
```

## 🤖 使用 AI-CLI 测试

### 安装 AI-CLI 工具

**选项 1: OpenAI（推荐用于生产）**

```bash
npm install -g @openai/cli
export OPENAI_API_KEY="your-api-key"
```

**选项 2: Anthropic Claude**

```bash
pip install anthropic-cli
export ANTHROPIC_API_KEY="your-api-key"
```

**选项 3: Ollama（本地免费）**

```bash
# 安装 Ollama
curl -fsSL https://ollama.ai/install.sh | sh

# 下载模型
ollama pull llama2

# 设置别名
alias ai='ollama run llama2'
```

### 运行 AI 测试

```bash
cd /tmp/sui-proxy-deploy  # 或你的代码目录

# 交互式菜单
sudo ./ai-test-helper.sh

# 或直接运行特定测试
sudo ./ai-test-helper.sh deploy    # 分析部署状态
sudo ./ai-test-helper.sh config    # 分析配置
sudo ./ai-test-helper.sh error     # 诊断错误
sudo ./ai-test-helper.sh client    # 生成客户端配置
sudo ./ai-test-helper.sh all       # 全面检查
```

## 📱 配置客户端

### 获取配置信息

```bash
# 查看保存的配置
cat /opt/sui-proxy/config/config.env

# 或使用 AI 生成客户端配置
cd /tmp/sui-proxy-deploy
sudo ./ai-test-helper.sh client
```

### VLESS 客户端配置

基本信息：
- **服务器地址**: 你的 Node 域名
- **端口**: 443
- **UUID**: 从 config.env 获取
- **传输协议**: TCP
- **安全**: TLS
- **Flow**: xtls-rprx-vision

### 测试连接

```bash
# 测试 HTTPS 访问（通过 fallback）
curl -k https://your-master-domain.com/

# 测试 HTTP 访问
curl http://your-master-domain.com/
```

## 🔧 日常管理

### 查看状态

```bash
# 容器状态
docker ps

# 资源使用
docker stats sui-gateway sui-singbox

# 实时监控
watch -n 2 'docker ps --format "table {{.Names}}\t{{.Status}}"'
```

### 重启服务

```bash
# 重启 Gateway
cd /opt/sui-proxy/gateway
docker compose restart

# 重启 Node
cd /opt/sui-proxy/node
docker compose restart

# 重启所有
docker restart sui-gateway sui-singbox
```

### 停止服务

```bash
# 停止 Node
cd /opt/sui-proxy/node
docker compose down

# 停止 Gateway
cd /opt/sui-proxy/gateway
docker compose down
```

### 更新服务

```bash
# 拉取最新镜像
cd /opt/sui-proxy/gateway
docker compose pull
docker compose up -d

cd /opt/sui-proxy/node
docker compose pull
docker compose up -d
```

### 查看日志

```bash
# 最近日志
docker logs sui-gateway --tail 50
docker logs sui-singbox --tail 50

# 实时日志
docker logs -f sui-singbox

# 保存日志到文件
docker logs sui-gateway > gateway.log 2>&1
docker logs sui-singbox > singbox.log 2>&1
```

## 🔍 故障排查

### 问题 1: 容器无法启动

```bash
# 查看详细日志
docker logs sui-singbox --tail 100

# 检查配置文件
jq . /opt/sui-proxy/node/config/singbox/config.json

# 使用 AI 诊断
cd /tmp/sui-proxy-deploy
sudo ./ai-test-helper.sh error
```

### 问题 2: 端口冲突

```bash
# 查看占用端口的进程
sudo lsof -i :80
sudo lsof -i :443

# 停止占用的服务
sudo systemctl stop nginx
sudo systemctl stop apache2
```

### 问题 3: 证书获取失败

```bash
# 检查域名解析
dig your-domain.com

# 检查端口 80 可访问性
curl -v http://your-domain.com/.well-known/acme-challenge/test

# 查看 Caddy 日志
docker logs sui-gateway | grep -i acme
```

### 问题 4: Fallback 不工作

```bash
# 测试容器连接
docker exec sui-singbox ping -c 3 sui-gateway

# 检查网络
docker network inspect sui-master-net

# 验证 fallback 配置
jq '.inbounds[0].fallback' /opt/sui-proxy/node/config/singbox/config.json
```

### 使用 AI 诊断

```bash
cd /tmp/sui-proxy-deploy

# 分析错误
sudo ./ai-test-helper.sh error

# 获取故障排查指南
sudo ./ai-test-helper.sh troubleshoot
```

## 🔒 安全加固

### 1. 配置防火墙

```bash
# 只开放必要端口
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow 22/tcp   # SSH
sudo ufw allow 80/tcp   # HTTP
sudo ufw allow 443/tcp  # HTTPS
sudo ufw enable
```

### 2. 定期更新

```bash
# 更新系统
sudo apt update && sudo apt upgrade -y

# 更新 Docker 镜像
cd /opt/sui-proxy/gateway && docker compose pull
cd /opt/sui-proxy/node && docker compose pull
```

### 3. 备份配置

```bash
# 创建备份
sudo tar -czf sui-proxy-backup-$(date +%Y%m%d).tar.gz \
  /opt/sui-proxy/config/

# 定期备份（添加到 crontab）
echo "0 2 * * * tar -czf /backup/sui-proxy-\$(date +\%Y\%m\%d).tar.gz /opt/sui-proxy/config/" | crontab -
```

### 4. 监控日志

```bash
# 检查错误
docker logs sui-gateway | grep -i error
docker logs sui-singbox | grep -i error

# 使用 AI 安全检查
cd /tmp/sui-proxy-deploy
sudo ./ai-test-helper.sh security
```

## 📈 性能优化

### 启用 BBR

```bash
echo "net.core.default_qdisc=fq" | sudo tee -a /etc/sysctl.conf
echo "net.ipv4.tcp_congestion_control=bbr" | sudo tee -a /etc/sysctl.conf
sudo sysctl -p
```

### 配置 Docker 日志轮转

```bash
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

### 监控资源使用

```bash
# 实时监控
docker stats sui-gateway sui-singbox

# 使用 AI 性能分析
cd /tmp/sui-proxy-deploy
sudo ./ai-test-helper.sh perf
```

## 🆘 获取帮助

1. **查看文档**
   - [快速开始](QUICK-START.md)
   - [详细部署](DEPLOYMENT.md)
   - [AI 测试指南](AI-TESTING-GUIDE.md)

2. **运行测试**
   ```bash
   sudo ./test-deployment.sh
   ```

3. **使用 AI 诊断**
   ```bash
   sudo ./ai-test-helper.sh error
   ```

4. **查看日志**
   ```bash
   docker logs sui-gateway
   docker logs sui-singbox
   ```

## 📞 支持

- 📖 文档: [README-DEPLOYMENT.md](README-DEPLOYMENT.md)
- 🐛 问题: GitHub Issues
- 💬 讨论: GitHub Discussions

---

祝部署顺利！🚀
