<div align="center">

# 🚀 SUI Solo

**Distributed Proxy Cluster Management System**

一键部署和管理 Sing-box + AdGuard Home 节点的分布式代理集群系统

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Docker](https://img.shields.io/badge/Docker-Required-blue?logo=docker)](https://www.docker.com/)
[![Python](https://img.shields.io/badge/Python-3.11+-green?logo=python)](https://www.python.org/)
[![Security](https://img.shields.io/badge/Security-Hardened-green.svg)](#-security-features)

[English](#-quick-start) | [简体中文](#-快速开始)

</div>

---

## ⚠️ Before Installation | 安装前必读

> **DNS must be configured BEFORE running the installer!**
> 
> Caddy needs to verify domain ownership for SSL certificates.

```bash
dig +short panel.example.com
dig +short node1.example.com
```

---

## 🚀 Quick Start

### Prerequisites

- Docker 20.10+ with Docker Compose
- Domain name for Master & each Node
- Ports: 80, 443 (both), 53 (Node only)

### Step 1: Install Master

```bash
curl -fsSL https://raw.githubusercontent.com/pjonix/SUIS/main/install.sh | sudo bash -s -- --master
```

> 📝 **Save the Cluster Secret** - only shown once during installation!

### Step 2: Install Node(s)

On each node server:

```bash
curl -fsSL https://raw.githubusercontent.com/pjonix/SUIS/main/install.sh | sudo bash -s -- --node
```

Enter the Cluster Secret when prompted.

### Step 3: Add Node to Master

1. Open `https://YOUR_MASTER_DOMAIN`
2. Click **"+ Add Node"**
3. Enter node name and domain
4. Click "Check" to verify connection

---

## 🚀 快速开始

### 环境要求

- Docker 20.10+ (含 Docker Compose)
- Master 和每个 Node 都需要独立域名
- 端口: 80, 443 (两者都需要), 53 (仅 Node 需要)

### 第一步：安装主控 (Master)

```bash
curl -fsSL https://raw.githubusercontent.com/pjonix/SUIS/main/install.sh | sudo bash -s -- --master
```

> 📝 **务必保存 Cluster Secret** - 安装时只显示一次！

### 第二步：安装节点 (Node)

在每台节点服务器上执行：

```bash
curl -fsSL https://raw.githubusercontent.com/pjonix/SUIS/main/install.sh | sudo bash -s -- --node
```

按提示输入 Cluster Secret。

### 第三步：在主控添加节点

1. 打开 `https://你的主控域名`
2. 点击 **"+ Add Node"**
3. 输入节点名称和域名
4. 点击 "Check" 验证连接

---

## 🖥️ 同一服务器部署 Master + Node

可以在同一台服务器上同时运行 Master 和 Node，但需要使用不同域名：

```bash
# 1. 先安装 Master
curl -fsSL https://raw.githubusercontent.com/pjonix/SUIS/main/install.sh | sudo bash -s -- --master
# 域名输入: panel.example.com

# 2. 再安装 Node (使用不同域名)
curl -fsSL https://raw.githubusercontent.com/pjonix/SUIS/main/install.sh | sudo bash -s -- --node
# 域名输入: node.example.com
# Secret 输入: 第一步显示的 Cluster Secret

# 3. 在 Master 面板添加这个 Node
# 打开 https://panel.example.com → Add Node → 输入 node.example.com
```

> ⚠️ **注意**: 两个域名必须都指向同一服务器 IP

---

## 📖 使用说明

### 架构说明

```
┌─────────────────┐         ┌─────────────────┐
│     Master      │         │      Node       │
│  (Control Panel)│◄───────►│  (Proxy Agent)  │
│                 │  HTTPS  │                 │
│  - Web UI       │         │  - Sing-box     │
│  - Node管理     │         │  - AdGuard Home │
│  - 状态监控     │         │  - Caddy        │
└─────────────────┘         └─────────────────┘
```

- **Master**: 只是控制面板，用于管理和监控所有 Node
- **Node**: 实际运行代理服务 (Sing-box) 和 DNS 过滤 (AdGuard Home)

### 访问服务

| 服务 | 地址 |
|------|------|
| Master 控制面板 | `https://panel.example.com` |
| Node AdGuard Home | `https://node.example.com/adguard/` |
| Node API (内部) | `https://node.example.com/{hidden_path}/api/v1/` |

### 管理命令

```bash
# 查看状态
cd /opt/sui-solo/master && docker compose ps
cd /opt/sui-solo/node && docker compose ps

# 查看日志
cd /opt/sui-solo/master && docker compose logs -f
cd /opt/sui-solo/node && docker compose logs -f

# 重启服务
cd /opt/sui-solo/master && docker compose restart
cd /opt/sui-solo/node && docker compose restart

# 卸载
cd /opt/sui-solo/master && docker compose down -v
cd /opt/sui-solo/node && docker compose down -v
rm -rf /opt/sui-solo
```

### 配置文件位置

```
/opt/sui-solo/
├── master/
│   ├── .env                    # Master 配置 (含 Secret)
│   └── config/caddy/Caddyfile  # Caddy 配置
└── node/
    ├── .env                    # Node 配置
    ├── config/caddy/Caddyfile  # Caddy 配置
    ├── config/singbox/config.json  # Sing-box 配置
    └── config/adguard/         # AdGuard 配置
```

---

## 🔒 Security Features

| Layer | Protection |
|-------|------------|
| HTTPS | All traffic TLS encrypted via Caddy |
| Hidden Path | API path = `SHA256(SALT:secret)[:16]` |
| Token Auth | `X-SUI-Token` header validation |
| Rate Limiting | 5 auth attempts/min/IP |
| Input Sanitization | Whitelist validation |
| Command Whitelist | Only allowed docker commands |

---

## 🔧 Troubleshooting | 常见问题

| 问题 | 解决方案 |
|------|----------|
| SSL 证书错误 | 检查 DNS: `dig +short YOUR_DOMAIN` |
| 频率限制 | 等待 60-120 秒 |
| Token 错误 | 检查 Master 和 Node 的 `.env` 中 Secret 是否一致 |
| 端口占用 | `sudo lsof -i :80` 或 `sudo ss -tlnp \| grep :80` |
| Node 离线 | 检查 Node 服务: `cd /opt/sui-solo/node && docker compose ps` |
| 页面空白 | 重建容器: `docker compose down && docker compose up -d --build` |

---

## ⚠️ Disclaimer | 免责声明

This project is for **educational purposes only**. Users must comply with local laws.

本项目仅供**教育和技术研究目的**。用户必须遵守当地法律法规。

---

## 📄 License

MIT License - see [LICENSE](LICENSE)

---

<div align="center">
Made with ❤️ for the open source community
</div>
