# SUI Proxy 部署文档总览

## 📚 文档导航

本项目包含完整的部署和测试文档，请根据你的需求选择：

### 🚀 快速开始
- **[QUICK-START.md](QUICK-START.md)** - 5 分钟快速部署指南
  - 适合：想要快速部署的用户
  - 包含：最简化的部署步骤

### 📖 详细部署
- **[DEPLOYMENT.md](DEPLOYMENT.md)** - 完整部署和测试指南
  - 适合：需要详细了解每个步骤的用户
  - 包含：详细说明、故障排查、监控建议

### 🤖 AI 辅助测试
- **[AI-TESTING-GUIDE.md](AI-TESTING-GUIDE.md)** - AI-CLI 测试推荐方案
  - 适合：想要使用 AI 进行智能测试的用户
  - 包含：AI 工具选择、测试场景、最佳实践

## 🎯 推荐部署流程

### 新手用户

```bash
1. 阅读 QUICK-START.md
2. 运行 install.sh
3. 运行 test-deployment.sh
4. 完成！
```

### 进阶用户

```bash
1. 阅读 DEPLOYMENT.md
2. 运行 install.sh
3. 运行 test-deployment.sh
4. 安装 AI-CLI 工具
5. 运行 ai-test-helper.sh
6. 根据 AI 建议优化
```

### 专业用户

```bash
1. 阅读所有文档
2. 自定义配置
3. 运行完整测试套件
4. 使用 AI 进行深度分析
5. 性能调优
6. 安全加固
```

## 📁 项目结构

```
sui-proxy/
├── install.sh                    # 主安装脚本
├── test-deployment.sh            # 部署测试脚本
├── ai-test-helper.sh            # AI 辅助测试脚本
│
├── node/                         # Node 配置
│   ├── docker-compose.yml       # Node Docker Compose
│   ├── templates/
│   │   ├── singbox-config.json.template
│   │   └── Caddyfile.template
│   └── config/                  # 生成的配置（安装后）
│
├── gateway/                      # Gateway 配置
│   └── docker-compose.yml       # Gateway Docker Compose
│
├── tests/                        # 属性测试
│   ├── test_singbox_config.bats
│   ├── test_caddy_config.bats
│   ├── test_gateway_compose.bats
│   ├── test_node_compose.bats
│   ├── test_docker_network.bats
│   └── test_install_script.bats
│
└── docs/                         # 文档
    ├── QUICK-START.md
    ├── DEPLOYMENT.md
    └── AI-TESTING-GUIDE.md
```

## 🔧 核心脚本说明

### install.sh
主安装脚本，负责：
- 检查系统要求
- 收集配置信息
- 生成配置文件
- 创建 Docker 网络
- 验证配置

**使用方法**:
```bash
sudo ./install.sh
```

### test-deployment.sh
部署测试脚本，验证：
- 端口绑定
- 容器状态
- 网络配置
- 配置文件
- HTTP/HTTPS 访问
- TLS 证书
- 容器连接
- 日志错误

**使用方法**:
```bash
sudo ./test-deployment.sh
```

### ai-test-helper.sh
AI 辅助测试脚本，提供：
- 部署状态分析
- 配置文件分析
- 错误诊断
- 测试命令生成
- 客户端配置生成
- 性能分析
- 安全检查
- 故障排查指南

**使用方法**:
```bash
# 交互式菜单
sudo ./ai-test-helper.sh

# 直接运行特定功能
sudo ./ai-test-helper.sh deploy
sudo ./ai-test-helper.sh config
sudo ./ai-test-helper.sh error
sudo ./ai-test-helper.sh all
```

## 🏗️ 架构说明

### 新架构（Sing-box 443 Fallback）

```
Internet
    ↓
Port 443 (Sing-box)
    ├─→ VLESS 流量 → Proxy Outbound
    └─→ HTTPS 流量 → Fallback → Gateway (Port 80) → Master App
    
Port 80 (Caddy Gateway)
    └─→ HTTP 流量 → Master App
    └─→ ACME HTTP-01 Challenge
```

### 关键特性

1. **Sing-box 在端口 443**
   - TLS 终止
   - 协议检测
   - VLESS 代理
   - Fallback 机制

2. **Caddy 在端口 80**
   - HTTP-only
   - 反向代理
   - ACME 挑战

3. **Docker 网络**
   - sui-master-net
   - sui-node-net
   - 容器间通信

## ✅ 测试覆盖

### 单元测试（BATS）
- ✅ Sing-box 配置模板
- ✅ Caddy 配置模板
- ✅ Gateway Docker Compose
- ✅ Node Docker Compose
- ✅ Docker 网络配置
- ✅ 安装脚本输出

**运行方法**:
```bash
bats tests/*.bats
```

### 集成测试
- ✅ 端口绑定验证
- ✅ 容器状态检查
- ✅ 网络连接测试
- ✅ HTTP 访问测试
- ✅ HTTPS Fallback 测试
- ✅ TLS 证书验证
- ✅ 配置文件验证
- ✅ 日志错误检查

**运行方法**:
```bash
sudo ./test-deployment.sh
```

### AI 辅助测试
- 🤖 智能日志分析
- 🤖 配置文件审查
- 🤖 性能评估
- 🤖 安全审计
- 🤖 故障诊断

**运行方法**:
```bash
sudo ./ai-test-helper.sh all
```

## 📊 测试结果示例

### 成功部署
```
========================================
           测试报告
========================================

通过: 32
失败: 0
警告: 2

✓ 所有关键测试通过！

部署成功！你可以：
1. 配置 VLESS 客户端连接
2. 访问 Master 管理面板
3. 查看详细日志
```

### 部分问题
```
========================================
           测试报告
========================================

通过: 28
失败: 2
警告: 5

✗ 有 2 个测试失败

请检查：
1. 容器日志
2. 配置文件
3. 网络配置
```

## 🔍 故障排查

### 快速诊断

```bash
# 1. 运行测试
sudo ./test-deployment.sh

# 2. 如果有失败，使用 AI 诊断
sudo ./ai-test-helper.sh error

# 3. 查看详细日志
docker logs sui-gateway
docker logs sui-singbox

# 4. 检查配置
jq . /opt/sui-proxy/node/config/singbox/config.json
cat /opt/sui-proxy/node/config/caddy/Caddyfile
```

### 常见问题

| 问题 | 解决方案 | 文档 |
|------|---------|------|
| 端口被占用 | 停止占用服务 | DEPLOYMENT.md |
| 容器无法启动 | 检查日志和配置 | DEPLOYMENT.md |
| HTTPS 无法访问 | 检查域名和防火墙 | DEPLOYMENT.md |
| Fallback 不工作 | 验证网络和配置 | DEPLOYMENT.md |
| 证书获取失败 | 检查 DNS 和端口 80 | DEPLOYMENT.md |

## 🎓 学习资源

### 了解技术栈
- **Sing-box**: https://sing-box.sagernet.org/
- **Caddy**: https://caddyserver.com/
- **Docker Compose**: https://docs.docker.com/compose/
- **VLESS Protocol**: https://xtls.github.io/

### 相关概念
- **TLS Termination**: TLS 在入口点解密
- **SNI Routing**: 基于 SNI 的流量路由
- **Fallback Mechanism**: 协议检测失败时的回退
- **ACME HTTP-01**: Let's Encrypt 验证方式

## 🚀 性能优化

部署成功后，可以考虑：

1. **启用 BBR**
```bash
echo "net.core.default_qdisc=fq" >> /etc/sysctl.conf
echo "net.ipv4.tcp_congestion_control=bbr" >> /etc/sysctl.conf
sysctl -p
```

2. **配置日志轮转**
```bash
# 编辑 /etc/docker/daemon.json
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  }
}
```

3. **监控设置**
```bash
# 使用 Prometheus + Grafana
# 或简单的脚本监控
watch -n 5 'docker stats --no-stream'
```

## 🔒 安全建议

1. **定期更新**
```bash
# 更新 Docker 镜像
cd /opt/sui-proxy/gateway && docker compose pull
cd /opt/sui-proxy/node && docker compose pull
```

2. **备份配置**
```bash
# 备份配置文件
tar -czf sui-proxy-backup-$(date +%Y%m%d).tar.gz /opt/sui-proxy/config/
```

3. **监控日志**
```bash
# 定期检查异常
docker logs sui-gateway | grep -i error
docker logs sui-singbox | grep -i error
```

## 📞 获取帮助

1. **查看文档**
   - QUICK-START.md - 快速开始
   - DEPLOYMENT.md - 详细部署
   - AI-TESTING-GUIDE.md - AI 测试

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

## 🎉 部署成功后

恭喜！你已经成功部署了 SUI Proxy。

接下来：
1. ✅ 配置 VLESS 客户端
2. ✅ 访问 Master 管理面板
3. ✅ 设置监控和告警
4. ✅ 配置自动备份
5. ✅ 优化性能参数

享受你的代理服务！🚀

---

**版本**: 1.0.0  
**最后更新**: 2024-12  
**架构**: Sing-box 443 Fallback
