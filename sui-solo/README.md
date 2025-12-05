<div align="center">

# 🚀 SUI Solo

**Distributed Proxy Cluster Management System**

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Docker](https://img.shields.io/badge/Docker-Required-blue?logo=docker)](https://www.docker.com/)
[![Python](https://img.shields.io/badge/Python-3.11+-green?logo=python)](https://www.python.org/)
[![Security](https://img.shields.io/badge/Security-Hardened-green)](SECURITY.md)

[English](README.md) | [简体中文](README_CN.md)

</div>

---

## ⚠️ Before You Start

> **IMPORTANT: DNS must be configured BEFORE installation!**
> 
> Caddy needs to verify domain ownership to issue SSL certificates.
> If DNS is not pointing to your server, installation will fail.

```bash
# Verify DNS is working:
dig +short panel.example.com  # Should return your server IP
dig +short node1.example.com  # Should return your server IP
```

---

## 🚀 Quick Start

### Prerequisites

- Docker 20.10+ with Docker Compose
- **Domain name for Master** (required for HTTPS)
- Domain name for each Node
- Ports: 80, 443 (Master & Node), 53 (Node only)
- **DNS configured and propagated**

### Install Master

```bash
git clone https://github.com/yourusername/sui-solo.git
cd sui-solo
sudo ./install.sh --master
```

You'll be prompted for:
1. **Master domain** (e.g., `panel.example.com`)
2. **Email** for SSL certificates

> 📝 **Save the Cluster Secret** displayed after installation!

### Install Node

```bash
sudo ./install.sh --node
# Enter: Cluster Secret, Node Domain, Email
```

### Add Node to Master

Open `https://YOUR_MASTER_DOMAIN` → Click **"+ Add Node"**

---

## 🔒 Security Features

### Defense in Depth

```
┌─────────────────────────────────────────────────────────────┐
│                    SECURITY LAYERS                           │
├─────────────────────────────────────────────────────────────┤
│  Layer 1: HTTPS/TLS          - All traffic encrypted        │
│  Layer 2: Hidden API Path    - SHA256(SALT:token)[:16]      │
│  Layer 3: Token Auth         - X-SUI-Token header           │
│  Layer 4: Rate Limiting      - 5 auth attempts/min/IP       │
│  Layer 5: Input Sanitization - Whitelist validation         │
│  Layer 6: Command Whitelist  - Only allowed docker cmds     │
└─────────────────────────────────────────────────────────────┘
```

### Rate Limiting

| Endpoint Type | Limit | Window |
|---------------|-------|--------|
| General API | 30 req | 60 sec |
| Auth-sensitive | 5 req | 60 sec |
| After limit hit | Blocked | 120 sec |

### Input Sanitization

- Domain: Regex whitelist `^[a-zA-Z0-9][a-zA-Z0-9\-\.]*$`
- Service: Whitelist `{singbox, adguard, caddy}`
- Node ID: Hex format `^[a-f0-9]{8}$`
- Constant-time token comparison (prevents timing attacks)

---

## ⚠️ Security Warnings

### Docker Socket Access

> **⚠️ MEDIUM RISK**

The Agent container requires Docker socket access to restart services.
This grants elevated privileges. Mitigations in place:

- ✅ Command whitelist (only `restart`, `inspect`, `logs`)
- ✅ Container name whitelist (`sui-*` only)
- ✅ Read-only socket mount
- ✅ Dropped capabilities
- ✅ `no-new-privileges` security option

**For maximum security**, consider:
1. Using Sing-box's auto-reload feature instead of restart
2. Running a separate privileged sidecar with minimal commands

### Recommendations

```bash
# 1. Use strong, unique Cluster Secret (auto-generated)
# 2. Keep Docker and all images updated
# 3. Monitor logs for suspicious activity
docker logs sui-agent | grep -i "auth failed"

# 4. Use firewall to restrict access
ufw allow from YOUR_IP to any port 443
```

---

## 📁 Project Structure

```
sui-solo/
├── install.sh              # Interactive installer
├── README.md / README_CN.md
├── master/
│   ├── docker-compose.yml  # Caddy (gateway) + Flask (internal)
│   ├── app.py              # Rate limiting, input sanitization
│   └── config/caddy/       # Generated Caddyfile with HSTS
└── node/
    ├── docker-compose.yml  # Security-hardened containers
    ├── agent.py            # Command whitelist, rate limiting
    └── templates/          # Caddyfile template
```

---

## ⚙️ Configuration

### Master `.env`

```env
CLUSTER_SECRET=<64-char-hex>
MASTER_DOMAIN=panel.example.com
ACME_EMAIL=admin@example.com
```

### Node `.env`

```env
CLUSTER_SECRET=<from-master>
NODE_DOMAIN=node1.example.com
PATH_PREFIX=<16-char-computed>
ACME_EMAIL=admin@example.com
```

---

## 🔧 Troubleshooting

| Issue | Solution |
|-------|----------|
| SSL certificate error | Verify DNS: `dig +short YOUR_DOMAIN` |
| "Rate limit exceeded" | Wait 60-120 seconds, check for attacks |
| Token error | Verify secret matches in both `.env` files |
| Port in use | `sudo lsof -i :80` to find process |
| Container won't start | Check logs: `docker logs sui-agent` |

### View Security Logs

```bash
# Check for auth failures
docker logs sui-agent 2>&1 | grep -i "auth\|rate\|blocked"

# Check Caddy access logs
docker exec sui-caddy cat /var/log/caddy/access.log | tail -20
```

---

## 📡 API Reference

### Authentication

All API requests require:
- Path: `/{PATH_PREFIX}/api/v1/...`
- Header: `X-SUI-Token: <CLUSTER_SECRET>`

### Endpoints

| Endpoint | Method | Rate Limit |
|----------|--------|------------|
| `/status` | GET | 30/min |
| `/services` | GET | 30/min |
| `/restart/<service>` | POST | 5/min |
| `/config/<service>` | GET/POST | 5/min (POST) |
| `/logs/<service>` | GET | 30/min |

---

## ⚠️ Disclaimer

This project is for **educational purposes only**. Users must comply with local laws. Authors are not responsible for misuse.

---

## 📄 License

MIT License - see [LICENSE](LICENSE)

---

<div align="center">
Made with ❤️ for the open source community
</div>
