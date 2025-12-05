<div align="center">

# 🚀 SUI Solo

**Distributed Proxy Cluster Management System**

Deploy and manage Sing-box + AdGuard Home nodes with one command

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Docker](https://img.shields.io/badge/Docker-Required-blue?logo=docker)](https://www.docker.com/)
[![Python](https://img.shields.io/badge/Python-3.11+-green?logo=python)](https://www.python.org/)



</div>

---

## ⚠️ Before Installation

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
- Domain name for Master and each Node
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

## 🖥️ Same Server Deployment (Master + Node)

You can run both Master and Node on the same server using a shared Caddy gateway:

### Option 1: One-Click Install (Recommended)

```bash
curl -fsSL https://raw.githubusercontent.com/pjonix/SUIS/main/install.sh | sudo bash -s -- --both
```

### Option 2: Step by Step

```bash
# 1. Install Master first
curl -fsSL https://raw.githubusercontent.com/pjonix/SUIS/main/install.sh | sudo bash -s -- --master

# 2. Install Node (auto-detects Master, uses shared gateway)
curl -fsSL https://raw.githubusercontent.com/pjonix/SUIS/main/install.sh | sudo bash -s -- --node

# 3. Add the Node in Master panel
```

> ⚠️ Both domains must point to the same server IP

---

## 📖 Architecture

```
┌─────────────────┐         ┌─────────────────┐
│     Master      │         │      Node       │
│  (Control Panel)│◄───────►│  (Proxy Agent)  │
│                 │  HTTPS  │                 │
│  - Web UI       │         │  - Sing-box     │
│  - Node Mgmt    │         │  - AdGuard Home │
│  - Monitoring   │         │  - Caddy        │
└─────────────────┘         └─────────────────┘
```

- **Master**: Control panel for managing and monitoring all Nodes
- **Node**: Runs proxy services (Sing-box) and DNS filtering (AdGuard Home)

### Access Services

| Service | URL |
|---------|-----|
| Master Control Panel | `https://panel.example.com` |
| Node AdGuard Home | `https://node.example.com/adguard/` |
| Node API (internal) | `https://node.example.com/{hidden_path}/api/v1/` |

---

## 🔧 Management Commands

```bash
# View status
cd /opt/sui-solo/master && docker compose ps
cd /opt/sui-solo/node && docker compose ps

# View logs
cd /opt/sui-solo/master && docker compose logs -f
cd /opt/sui-solo/node && docker compose logs -f

# Restart services
cd /opt/sui-solo/master && docker compose restart
cd /opt/sui-solo/node && docker compose restart
```

### Uninstall

```bash
curl -fsSL https://raw.githubusercontent.com/pjonix/SUIS/main/install.sh | sudo bash -s -- --uninstall
```

---

## 📁 Configuration Files

```
/opt/sui-solo/
├── gateway/                    # Shared Caddy gateway
│   ├── docker-compose.yml
│   └── Caddyfile
├── master/
│   ├── .env                    # Master config (contains Secret)
│   └── docker-compose.yml
└── node/
    ├── .env                    # Node config
    ├── docker-compose.yml
    └── config/
        ├── singbox/config.json # Sing-box config
        └── adguard/            # AdGuard config
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

## 🔧 Troubleshooting

| Issue | Solution |
|-------|----------|
| SSL certificate error | Check DNS: `dig +short YOUR_DOMAIN` |
| Rate limit exceeded | Wait 60-120 seconds |
| Token error | Check Secret in `.env` files on both Master and Node |
| Port in use | `sudo lsof -i :80` or `sudo ss -tlnp \| grep :80` |
| Node offline | Check Node services: `cd /opt/sui-solo/node && docker compose ps` |
| Blank page | Rebuild containers: `docker compose down && docker compose up -d --build` |

---

## ⚠️ Disclaimer

This project is for **educational purposes only**. Users must comply with local laws.

---

## 📄 License

MIT License - see [LICENSE](LICENSE)

---

<div align="center">
Made with ❤️ for the open source community
</div>
