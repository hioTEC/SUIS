# GitHub 发布清单

## ✅ 发布前检查

### 1. 更新仓库地址

在以下文件中将 `your-username/sui-proxy` 替换为你的实际仓库地址：

- [ ] `README.md` - 所有 GitHub 链接
- [ ] `QUICK-START.md` - 克隆命令
- [ ] `SERVER-GUIDE.md` - 克隆命令
- [ ] `server-deploy.sh` - GITHUB_REPO 变量

**快速替换命令**:
```bash
# 替换为你的 GitHub 用户名
YOUR_USERNAME="your-actual-username"

# 批量替换
sed -i '' "s/your-username\/sui-proxy/${YOUR_USERNAME}\/sui-proxy/g" README.md
sed -i '' "s/your-username\/sui-proxy/${YOUR_USERNAME}\/sui-proxy/g" QUICK-START.md
sed -i '' "s/your-username\/sui-proxy/${YOUR_USERNAME}\/sui-proxy/g" SERVER-GUIDE.md
sed -i '' "s/your-username\/sui-proxy/${YOUR_USERNAME}\/sui-proxy/g" server-deploy.sh

# Linux 用户使用（不带 ''）
sed -i "s/your-username\/sui-proxy/${YOUR_USERNAME}\/sui-proxy/g" README.md
```

### 2. 验证文件完整性

确保以下文件存在且可执行：

- [ ] `install.sh` (可执行)
- [ ] `test-deployment.sh` (可执行)
- [ ] `ai-test-helper.sh` (可执行)
- [ ] `server-deploy.sh` (可执行)

```bash
# 检查文件
ls -la *.sh

# 添加执行权限
chmod +x install.sh test-deployment.sh ai-test-helper.sh server-deploy.sh
```

### 3. 验证配置文件

- [ ] `node/templates/singbox-config.json.template` - 包含 fallback 配置
- [ ] `node/templates/Caddyfile.template` - HTTP-only 配置
- [ ] `node/docker-compose.yml` - 端口 443 配置
- [ ] `gateway/docker-compose.yml` - 端口 80 配置

### 4. 验证测试文件

- [ ] `tests/test_singbox_config.bats`
- [ ] `tests/test_caddy_config.bats`
- [ ] `tests/test_gateway_compose.bats`
- [ ] `tests/test_node_compose.bats`
- [ ] `tests/test_docker_network.bats`
- [ ] `tests/test_install_script.bats`

### 5. 验证文档

- [ ] `README.md` - 主文档
- [ ] `README-DEPLOYMENT.md` - 文档导航
- [ ] `QUICK-START.md` - 快速开始
- [ ] `DEPLOYMENT.md` - 详细部署
- [ ] `AI-TESTING-GUIDE.md` - AI 测试
- [ ] `SERVER-GUIDE.md` - 服务器指南

### 6. 检查 .gitignore

- [ ] `.gitignore` 存在
- [ ] 敏感文件已排除（*.env, config.env 等）

## 📤 Git 提交和推送

### 1. 初始化 Git（如果还没有）

```bash
git init
git add .
git commit -m "Initial commit: Sing-box 443 Fallback architecture"
```

### 2. 添加远程仓库

```bash
# 替换为你的仓库地址
git remote add origin https://github.com/your-username/sui-proxy.git
```

### 3. 推送到 GitHub

```bash
# 推送到 main 分支
git branch -M main
git push -u origin main
```

### 4. 创建标签（可选）

```bash
# 创建版本标签
git tag -a v1.0.0 -m "Release v1.0.0: Initial release with Sing-box 443 Fallback"
git push origin v1.0.0
```

## 🚀 GitHub 仓库设置

### 1. 仓库描述

```
A smart proxy solution based on Sing-box and Caddy with port 443 fallback architecture
```

### 2. 主题标签

添加以下标签：
- `proxy`
- `sing-box`
- `caddy`
- `docker`
- `vless`
- `hysteria2`
- `fallback`
- `tls`
- `acme`
- `ai-testing`

### 3. 启用功能

- [ ] Issues
- [ ] Discussions
- [ ] Wiki（可选）
- [ ] Projects（可选）

### 4. 设置 README

GitHub 会自动使用 `README.md` 作为仓库首页

### 5. 添加 License

如果还没有，创建 LICENSE 文件：

```bash
# MIT License 示例
cat > LICENSE << 'EOF'
MIT License

Copyright (c) 2024 [Your Name]

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
EOF
```

## 📝 创建 Release

### 1. 在 GitHub 上创建 Release

1. 进入仓库页面
2. 点击 "Releases"
3. 点击 "Create a new release"
4. 填写信息：
   - Tag: `v1.0.0`
   - Title: `v1.0.0 - Initial Release`
   - Description: 参考下面的模板

### Release 描述模板

```markdown
## 🎉 SUI Proxy v1.0.0 - Initial Release

### ✨ Features

- ✅ Sing-box on port 443 with intelligent fallback
- ✅ Caddy on port 80 for HTTP and ACME challenges
- ✅ Docker-based deployment
- ✅ Automatic TLS certificate management
- ✅ 32+ property-based tests
- ✅ AI-assisted testing and diagnostics

### 🏗️ Architecture

```
Internet → Port 443 (Sing-box)
    ├─→ VLESS/Hysteria2 → Proxy
    └─→ HTTPS → Fallback → Caddy (Port 80) → Web App
```

### 🚀 Quick Start

**One-line deployment:**
```bash
curl -fsSL https://raw.githubusercontent.com/your-username/sui-proxy/main/server-deploy.sh | sudo bash
```

**Manual deployment:**
```bash
git clone https://github.com/your-username/sui-proxy.git
cd sui-proxy
sudo ./install.sh
```

### 📚 Documentation

- [Quick Start Guide](QUICK-START.md)
- [Deployment Guide](DEPLOYMENT.md)
- [AI Testing Guide](AI-TESTING-GUIDE.md)
- [Server Guide](SERVER-GUIDE.md)

### 🧪 Testing

- 32+ property-based tests
- Automated deployment testing
- AI-assisted diagnostics

### 📦 What's Included

- Complete installation scripts
- Docker Compose configurations
- Configuration templates
- Comprehensive test suite
- AI testing tools
- Full documentation

### 🔧 Requirements

- Ubuntu 20.04+ or Debian 11+
- 1GB+ RAM
- Docker and Docker Compose
- Two domains with DNS configured

### 🤝 Contributing

Contributions are welcome! Please feel free to submit issues and pull requests.

### 📄 License

MIT License - see [LICENSE](LICENSE) file for details
```

## 🧪 测试一键部署

在发布后，测试一键部署脚本：

```bash
# 在干净的服务器上测试
curl -fsSL https://raw.githubusercontent.com/your-username/sui-proxy/main/server-deploy.sh | sudo bash
```

## 📢 宣传

### 1. 更新 README badges（可选）

在 README.md 顶部添加：

```markdown
![GitHub release](https://img.shields.io/github/v/release/your-username/sui-proxy)
![GitHub stars](https://img.shields.io/github/stars/your-username/sui-proxy)
![GitHub issues](https://img.shields.io/github/issues/your-username/sui-proxy)
![License](https://img.shields.io/github/license/your-username/sui-proxy)
```

### 2. 社交媒体

分享到：
- Twitter/X
- Reddit (r/selfhosted, r/docker)
- Hacker News
- V2EX
- 相关论坛和社区

### 3. 博客文章（可选）

写一篇介绍文章，包括：
- 架构设计思路
- 为什么选择 Sing-box + Caddy
- Fallback 机制的优势
- 部署和测试经验

## ✅ 最终检查清单

发布前最后检查：

- [ ] 所有文件已提交到 Git
- [ ] 仓库地址已更新
- [ ] 脚本有执行权限
- [ ] 文档链接正确
- [ ] .gitignore 配置正确
- [ ] LICENSE 文件存在
- [ ] README.md 完整
- [ ] 测试通过
- [ ] 一键部署脚本可用

## 🎯 发布后

- [ ] 在服务器上测试一键部署
- [ ] 验证所有文档链接
- [ ] 回复 Issues 和 Discussions
- [ ] 收集用户反馈
- [ ] 计划下一个版本

---

完成以上步骤后，你的项目就可以正式发布了！🎉
