# SUI Solo - Troubleshooting Guide

This guide covers common issues encountered during installation and operation, along with their solutions.

## Quick Diagnostics

Run the diagnostic script to automatically check for common issues:

```bash
curl -fsSL https://raw.githubusercontent.com/hioTEC/SUIS/main/diagnose.sh | bash
```

Or if you have the repository cloned:

```bash
./diagnose.sh
```

## Common Issues

### 1. Service Status Shows "not found"

**Symptom:** Node services (singbox, adguard) show as "not found" in Master panel

**Cause:** Agent container missing Docker CLI

**Solution:**
```bash
cd /opt/sui-solo/node
docker compose build --no-cache agent
docker compose up -d
```

**Prevention:** This is now fixed in v1.9.22+ with docker-ce-cli installed in the agent container.

---

### 2. Docker Fails to Start / iptables Errors

**Symptom:** 
- Docker service won't start
- Error: "iptables: No chain/target/match by that name"
- Containers fail to create networks

**Cause:** Conflict between iptables-nft and iptables-legacy

**Solution:**
```bash
# Switch to iptables-legacy
update-alternatives --set iptables /usr/sbin/iptables-legacy
update-alternatives --set ip6tables /usr/sbin/ip6tables-legacy

# Restart Docker
systemctl restart docker
```

**Prevention:** The install script now auto-detects and fixes this issue.

---

### 3. Docker Network Not Found

**Symptom:**
- Error: "network sui-node-net not found"
- Containers fail to start

**Cause:** Docker networks not created

**Solution:**
```bash
docker network create sui-master-net
docker network create sui-node-net
```

**Prevention:** The install script now creates networks with proper error handling.

---

### 4. Port Already in Use

**Symptom:**
- Installation fails with "port already in use"
- Containers won't start

**Check which process is using the port:**
```bash
# Check port 80
lsof -i :80
# or
ss -tulpn | grep :80

# Check port 443
lsof -i :443
```

**Solution:**
```bash
# If it's an old SUI Solo container
docker stop sui-gateway sui-master sui-agent
docker rm sui-gateway sui-master sui-agent

# If it's another service (nginx, apache, etc.)
systemctl stop nginx  # or apache2, httpd, etc.
systemctl disable nginx
```

---

### 5. Containers Keep Restarting

**Check container logs:**
```bash
# Master
docker logs sui-master --tail 50

# Node
docker logs sui-agent --tail 50
docker logs sui-singbox --tail 50
docker logs sui-adguard --tail 50

# Gateway
docker logs sui-gateway --tail 50
```

**Common causes:**

#### Config file errors
```bash
# Check singbox config
cat /opt/sui-solo/node/config/singbox/config.json | jq .

# If invalid JSON, regenerate:
cd /opt/sui-solo/node
docker compose down
rm -rf config/singbox/*
docker compose up -d
```

#### Permission issues
```bash
# Fix permissions
chown -R root:root /opt/sui-solo
chmod -R 755 /opt/sui-solo
```

---

### 6. Cannot Access Master Panel

**Symptom:** Cannot access https://your-domain.com

**Check DNS:**
```bash
# Verify domain resolves to your server IP
dig your-domain.com +short
nslookup your-domain.com
```

**Check Gateway:**
```bash
# Is gateway running?
docker ps | grep sui-gateway

# Check gateway logs
docker logs sui-gateway

# Check Caddy config
docker exec sui-gateway cat /etc/caddy/Caddyfile
```

**Check firewall:**
```bash
# UFW
ufw status
ufw allow 80/tcp
ufw allow 443/tcp

# firewalld
firewall-cmd --list-all
firewall-cmd --permanent --add-port=80/tcp
firewall-cmd --permanent --add-port=443/tcp
firewall-cmd --reload

# iptables
iptables -L -n | grep -E '80|443'
```

---

### 7. Node Not Connecting to Master

**Check cluster secret:**
```bash
# On Master
cat /opt/sui-solo/master/.env | grep CLUSTER_SECRET

# On Node
cat /opt/sui-solo/node/.env | grep CLUSTER_SECRET

# They must match!
```

**Check node domain:**
```bash
# Node must be accessible from Master
curl -k https://node-domain.com

# Check from Master server
curl -H "X-SUI-Token: YOUR_SECRET" "http://node-ip:5001/HIDDEN_PATH/api/v1/status"
```

**Regenerate hidden path:**
```bash
# Calculate hidden path
echo -n "SUI_Solo_Secured_2025:YOUR_CLUSTER_SECRET" | sha256sum | cut -c1-16
```

---

### 8. Subscription Links Not Working

**Check node presets:**
```bash
# View presets
cat /opt/sui-solo/node/config/presets.json

# Regenerate presets
curl -X POST -H "X-SUI-Token: YOUR_SECRET" \
  "http://localhost:5001/HIDDEN_PATH/api/v1/presets/regenerate"
```

**Check singbox config:**
```bash
# Verify inbounds are configured
cat /opt/sui-solo/node/config/singbox/config.json | jq .inbounds
```

---

## Manual Recovery

### Complete Reinstall (Keep Data)

```bash
# Backup data
cp -r /opt/sui-solo/master/data /tmp/master-backup
cp -r /opt/sui-solo/node/config /tmp/node-backup

# Uninstall
curl -fsSL https://raw.githubusercontent.com/hioTEC/SUIS/main/install.sh | bash -s -- --uninstall

# Reinstall
curl -fsSL https://raw.githubusercontent.com/hioTEC/SUIS/main/install.sh | bash

# Restore data
cp -r /tmp/master-backup/* /opt/sui-solo/master/data/
cp -r /tmp/node-backup/* /opt/sui-solo/node/config/

# Restart containers
cd /opt/sui-solo/master && docker compose restart
cd /opt/sui-solo/node && docker compose restart
```

### Reset Everything

```bash
# WARNING: This deletes all data!
curl -fsSL https://raw.githubusercontent.com/hioTEC/SUIS/main/install.sh | bash -s -- --uninstall
rm -rf /opt/sui-solo
docker network rm sui-master-net sui-node-net
```

---

## Getting Help

If you're still experiencing issues:

1. **Run diagnostics:**
   ```bash
   curl -fsSL https://raw.githubusercontent.com/hioTEC/SUIS/main/diagnose.sh | bash
   ```

2. **Collect logs:**
   ```bash
   docker logs sui-master > master.log 2>&1
   docker logs sui-agent > agent.log 2>&1
   docker logs sui-gateway > gateway.log 2>&1
   ```

3. **Check system info:**
   ```bash
   uname -a
   docker version
   docker compose version
   ```

4. **Open an issue:** https://github.com/hioTEC/SUIS/issues

Include:
- Output from diagnostic script
- Relevant log files
- System information
- Steps to reproduce the issue
