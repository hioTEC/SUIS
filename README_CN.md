<div align="center">

# 🚀 SUI Solo

**分布式代理集群管理系统**

一键部署和管理 Sing-box + AdGuard Home 节点

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Docker](https://img.shields.io/badge/Docker-Required-blue?logo=docker)](https://www.docker.com/)
[![Python](https://img.shields.io/badge/Python-3.11+-green?logo=python)](https://www.python.org/)

[English](README.md) | [简体中文](README_CN.md)

</div>

---

## ⚠️ 安装前必读

> **安装前必须先配置好 DNS！**
> 
> Caddy 需要验证域名所有权才能签发 SSL 证书。
> 如果 DNS 未指向服务器，安装将失败。

```bash
dig +short panel.example.com
dig +short node1.example.com
```

---

## 🚀 快速开始

### 环境要求

- Docker 20.10+ (含 Docker Compose)
- 主控和每个节点都需要独立域名
- 端口: 80, 443 (主控和节点), 53 (仅节点)

### 第一步：安装主控

```bash
curl -fsSL https://raw.githubusercontent.com/pjonix/SUIS/main/install.sh | sudo bash -s -- --master
```

> 📝 **务必保存集群密钥** - 安装时只显示一次！

### 第二步：安装节点

在每台节点服务器上执行：

```bash
curl -fsSL https://raw.githubusercontent.com/pjonix/SUIS/main/install.sh | sudo bash -s -- --node
```

按提示输入集群密钥。

### 第三步：在主控添加节点

1. 打开 `https://你的主控域名`
2. 点击 **"+ Add Node"**
3. 输入节点名称和域名
4. 点击 "Check" 验证连接

---

## 🖥️ 同一服务器部署主控和节点

可以在同一台服务器上同时运行主控和节点，使用共享 Caddy 网关：

### 方式一：一键安装（推荐）

```bash
curl -fsSL https://raw.githubusercontent.com/pjonix/SUIS/main/install.sh | sudo bash -s -- --both
```

### 方式二：分步安装

```bash
# 1. 先安装主控
curl -fsSL https://raw.githubusercontent.com/pjonix/SUIS/main/install.sh | sudo bash -s -- --master

# 2. 再安装节点 (自动检测主控，使用共享网关)
curl -fsSL https://raw.githubusercontent.com/pjonix/SUIS/main/install.sh | sudo bash -s -- --node

# 3. 在主控面板添加这个节点
```

> ⚠️ 两个域名必须都指向同一服务器 IP

---

## 📖 架构说明

```
┌─────────────────┐         ┌─────────────────┐
│      主控       │         │      节点       │
│   (控制面板)    │◄───────►│   (代理服务)    │
│                 │  HTTPS  │                 │
│  - 网页界面     │         │  - Sing-box     │
│  - 节点管理     │         │  - AdGuard Home │
│  - 状态监控     │         │  - Caddy        │
└─────────────────┘         └─────────────────┘
```

- **主控**: 控制面板，用于管理和监控所有节点
- **节点**: 实际运行代理服务 (Sing-box) 和 DNS 过滤 (AdGuard Home)

### 访问服务

| 服务 | 地址 |
|------|------|
| 主控面板 | `https://panel.example.com` |
| 节点 AdGuard Home | `https://node.example.com/adguard/` |
| 节点 API (内部) | `https://node.example.com/{隐藏路径}/api/v1/` |

---

## 🔧 管理命令

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
```

### 卸载

```bash
curl -fsSL https://raw.githubusercontent.com/pjonix/SUIS/main/install.sh | sudo bash -s -- --uninstall
```

---

## 📁 配置文件位置

```
/opt/sui-solo/
├── gateway/                    # 共享 Caddy 网关
│   ├── docker-compose.yml
│   └── Caddyfile
├── master/
│   ├── .env                    # 主控配置 (含密钥)
│   └── docker-compose.yml
└── node/
    ├── .env                    # 节点配置
    ├── docker-compose.yml
    └── config/
        ├── singbox/config.json # Sing-box 配置
        └── adguard/            # AdGuard 配置
```

---

## 🔒 安全特性

| 层级 | 保护措施 |
|------|----------|
| HTTPS | 全链路 TLS 加密 (Caddy) |
| 隐藏路径 | API 路径 = `SHA256(盐:密钥)[:16]` |
| Token 认证 | `X-SUI-Token` 请求头验证 |
| 频率限制 | 每 IP 每分钟 5 次认证尝试 |
| 输入清洗 | 白名单验证 |
| 命令白名单 | 仅允许特定 docker 命令 |

---

## 🔧 常见问题

| 问题 | 解决方案 |
|------|----------|
| SSL 证书错误 | 检查 DNS: `dig +short 你的域名` |
| 频率限制 | 等待 60-120 秒 |
| Token 错误 | 检查主控和节点的 `.env` 中密钥是否一致 |
| 端口占用 | `sudo lsof -i :80` 或 `sudo ss -tlnp \| grep :80` |
| 节点离线 | 检查节点服务: `cd /opt/sui-solo/node && docker compose ps` |
| 页面空白 | 重建容器: `docker compose down && docker compose up -d --build` |

---

## ⚠️ 免责声明

本项目仅供**教育和技术研究目的**。用户必须遵守当地法律法规。

---

## 📄 许可证

MIT License - 详见 [LICENSE](LICENSE)

---

<div align="center">
Made with ❤️ for the open source community
</div>
