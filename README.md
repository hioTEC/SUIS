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
# Verify DNS:
dig +short panel.example.com  # Should return your server IP
dig +short node1.example.com
```

---

## 🚀 Quick Start

### Prerequisites

- Docker 20.10+ with Docker Compose
- Domain name for Master & each Node
- Ports: 80, 443 (both), 53 (Node only)

### Install Master

```bash
git clone https://github.com/yourusername/sui-solo.git
cd sui-solo
sudo ./install.sh --master
```

> 📝 **Save the Cluster Secret** displayed after installation!

### Install Node

```bash
sudo ./install.sh --node
# Enter: Cluster Secret, Node Domain, Email
```

### Add Node to Master

Open `https://YOUR_MASTER_DOMAIN` → Click **"+ Add Node"**

---

## 🚀 快速开始

### 环境要求

- Docker 20.10+ (含 Docker Compose)
- Master 和每个 Node 都需要域名
- 端口: 80, 443 (两者), 53 (仅 Node)

### 安装主控

```bash
git clone https://github.com/yourusername/sui-solo.git
cd sui-solo
sudo ./install.sh --master
```

> 📝 **务必保存安装后显示的 Cluster Secret！**

### 安装节点

```bash
sudo ./install.sh --node
# 输入: Cluster Secret、节点域名、邮箱
```

---

## 🔒 Security Features

| Layer | Protection |
|-------|------------|
| 1. HTTPS | All traffic TLS encrypted |
| 2. Hidden Path | `SHA256(SALT:token)[:16]` |
| 3. Token Auth | `X-SUI-Token` header |
| 4. Rate Limiting | 5 auth attempts/min/IP |
| 5. Input Sanitization | Whitelist validation |
| 6. Command Whitelist | Only allowed docker cmds |

---

## 📁 Project Structure

```
sui-solo/
├── install.sh              # Interactive installer
├── README.md
├── LICENSE
├── master/
│   ├── docker-compose.yml  # Caddy + Flask
│   ├── app.py              # Rate limiting, sanitization
│   └── templates/
└── node/
    ├── docker-compose.yml  # Hardened containers
    ├── agent.py            # Command whitelist
    └── templates/
```

---

## 🔧 Troubleshooting | 常见问题

| Issue | Solution |
|-------|----------|
| SSL error | Verify DNS: `dig +short YOUR_DOMAIN` |
| Rate limit | Wait 60-120 sec |
| Token error | Check `.env` files match |
| Port in use | `sudo lsof -i :80` |

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
