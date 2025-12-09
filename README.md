# SUI Proxy - Sing-box 443 Fallback 架构

一个基于 Sing-box 和 Caddy 的智能代理解决方案，采用端口 443 fallback 架构，实现代理流量和 Web 流量的无缝共存。

## ✨ 特性

- 🚀 **Sing-box 在端口 443** - 作为主入口，处理 VLESS/Hysteria2 代理流量
- 🔄 **智能 Fallback** - 非代理 HTTPS 流量自动转发到 Caddy
- 🌐 **Caddy 在端口 80** - 处理 HTTP 流量和 ACME 挑战
- 🐳 **Docker 部署** - 完全容器化，易于管理
- 🔒 **自动 TLS** - Let's Encrypt 自动证书管理
- 🧪 **完整测试** - 32+ 属性测试确保正确性
- 🤖 **AI 辅助** - 智能测试和诊断工具

## 🏗️ 架构

```
Internet
    ↓
Port 443 (Sing-box)
    ├─→ VLESS/Hysteria2 → Proxy Outbound
    └─→ HTTPS (非代理) → Fallback → Caddy (Port 80) → Master App
    
Port 80 (Caddy)
    ├─→ HTTP 流量 → Master App
    └─→ ACME HTTP-01 Challenge
```

## 🚀 快速开始

### 一键部署（推荐）

```bash
curl -fsSL https://raw.githubusercontent.com/your-username/sui-proxy/main/server-deploy.sh | sudo bash
```

### 手动部署

```bash
# 1. 克隆仓库
git clone https://github.com/your-username/sui-proxy.git
cd sui-proxy

# 2. 运行安装
sudo ./install.sh

# 3. 启动服务
cd /opt/sui-proxy/gateway && sudo docker compose up -d
sleep 10
cd /opt/sui-proxy/node && sudo docker compose up -d

# 4. 验证部署
sudo ./test-deployment.sh
```

## 📋 前置要求

- **操作系统**: Ubuntu 20.04+ 或 Debian 11+
- **内存**: 至少 1GB RAM
- **域名**: 两个已解析的域名（Master 和 Node）
- **端口**: 80 和 443 需要开放
- **软件**: Docker 和 Docker Compose

## 📚 文档

- [快速开始指南](QUICK-START.md) - 5 分钟快速部署
- [详细部署文档](DEPLOYMENT.md) - 完整的部署和配置说明
- [AI 测试指南](AI-TESTING-GUIDE.md) - 使用 AI-CLI 进行智能测试
- [部署文档总览](README-DEPLOYMENT.md) - 所有文档的导航

## 🧪 测试

### 运行基础测试

```bash
sudo ./test-deployment.sh
```

### 运行属性测试

```bash
# 安装 BATS
brew install bats-core  # macOS
apt-get install bats    # Ubuntu/Debian

# 运行测试
bats tests/*.bats
```

### 使用 AI 辅助测试

```bash
# 安装 AI-CLI（选择一个）
npm install -g @openai/cli              # OpenAI
pip install anthropic-cli               # Anthropic
curl -fsSL https://ollama.ai/install.sh | sh  # Ollama (本地)

# 运行 AI 测试
sudo ./ai-test-helper.sh all
```

## 🔧 配置

安装完成后，配置文件位于：

- **Sing-box**: `/opt/sui-proxy/node/config/singbox/config.json`
- **Caddy**: `/opt/sui-proxy/node/config/caddy/Caddyfile`
- **凭证**: `/opt/sui-proxy/config/config.env`

## 📊 测试覆盖

- ✅ 32+ 属性测试（Property-Based Testing）
- ✅ 配置模板验证
- ✅ Docker Compose 验证
- ✅ 网络连接测试
- ✅ 端口绑定测试
- ✅ Fallback 机制测试
- ✅ TLS 证书验证

## 🤖 AI 辅助功能

AI-CLI 测试工具提供：

- 📊 **部署状态分析** - 自动分析容器、端口、网络
- 🔍 **配置文件审查** - 验证 Sing-box 和 Caddy 配置
- 🐛 **错误诊断** - 智能分析日志，找出问题
- 🧪 **测试生成** - 自动生成测试命令
- 📱 **客户端配置** - 生成 VLESS 客户端配置
- ⚡ **性能分析** - 评估系统性能
- 🔒 **安全检查** - 进行安全审计
- 🔧 **故障排查** - 提供详细排查步骤

## 🛠️ 管理命令

```bash
# 查看容器状态
docker ps

# 查看日志
docker logs sui-gateway
docker logs sui-singbox

# 重启服务
cd /opt/sui-proxy/node && docker compose restart

# 停止服务
cd /opt/sui-proxy/node && docker compose down

# 更新服务
cd /opt/sui-proxy/gateway && docker compose pull && docker compose up -d
cd /opt/sui-proxy/node && docker compose pull && docker compose up -d
```

## 📱 客户端配置

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

使用 AI 生成完整配置：

```bash
sudo ./ai-test-helper.sh client
```

## 🔍 故障排查

### 快速诊断

```bash
# 1. 运行测试
sudo ./test-deployment.sh

# 2. 使用 AI 诊断
sudo ./ai-test-helper.sh error

# 3. 查看日志
docker logs sui-gateway --tail 50
docker logs sui-singbox --tail 50
```

### 常见问题

| 问题 | 解决方案 |
|------|---------|
| 端口被占用 | `sudo lsof -i :80` 和 `sudo lsof -i :443` 查看占用进程 |
| 容器无法启动 | 检查日志 `docker logs sui-singbox` |
| HTTPS 无法访问 | 检查域名解析和防火墙 |
| Fallback 不工作 | 验证网络配置 `docker network inspect sui-master-net` |

详细故障排查请参考 [DEPLOYMENT.md](DEPLOYMENT.md)

## 🔒 安全建议

1. **定期更新镜像**
   ```bash
   docker compose pull && docker compose up -d
   ```

2. **备份配置**
   ```bash
   tar -czf backup-$(date +%Y%m%d).tar.gz /opt/sui-proxy/config/
   ```

3. **监控日志**
   ```bash
   docker logs sui-gateway | grep -i error
   docker logs sui-singbox | grep -i error
   ```

4. **使用 AI 安全检查**
   ```bash
   sudo ./ai-test-helper.sh security
   ```

## 📈 性能优化

### 启用 BBR

```bash
echo "net.core.default_qdisc=fq" >> /etc/sysctl.conf
echo "net.ipv4.tcp_congestion_control=bbr" >> /etc/sysctl.conf
sysctl -p
```

### 配置日志轮转

```bash
cat > /etc/docker/daemon.json << EOF
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  }
}
EOF

systemctl restart docker
```

## 🤝 贡献

欢迎提交 Issue 和 Pull Request！

## 📄 许可证

[MIT License](LICENSE)

## 🙏 致谢

- [Sing-box](https://sing-box.sagernet.org/) - 通用代理平台
- [Caddy](https://caddyserver.com/) - 现代化 Web 服务器
- [Docker](https://www.docker.com/) - 容器化平台

## 📞 支持

- 📖 查看[文档](README-DEPLOYMENT.md)
- 🐛 提交 [Issue](https://github.com/your-username/sui-proxy/issues)
- 💬 参与 [Discussions](https://github.com/your-username/sui-proxy/discussions)

---

**版本**: 1.0.0  
**架构**: Sing-box 443 Fallback  
**测试覆盖**: 32+ 属性测试  
**AI 辅助**: ✅ 支持

Made with ❤️ for the proxy community
