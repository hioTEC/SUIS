#!/bin/bash
# SUI Proxy 一键安装脚本

set -e

echo "🚀 开始设置 SUI Proxy..."

# 1. 创建目录
echo "📁 创建目录结构..."
sudo mkdir -p /opt/sui-proxy/{scripts,certificates,master,node}
sudo mkdir -p /etc/sui-proxy
sudo mkdir -p /var/log/sui-proxy

# 2. 创建服务用户
echo "👤 创建服务用户..."
if ! id "sui-proxy" &>/dev/null; then
    sudo useradd -r -s /usr/sbin/nologin -d /opt/sui-proxy sui-proxy
fi

# 3. 设置权限
echo "🔒 设置权限..."
sudo chown -R sui-proxy:sui-proxy /opt/sui-proxy /etc/sui-proxy /var/log/sui-proxy

# 4. 创建基础配置文件
echo "📝 创建配置文件..."
sudo tee /etc/sui-proxy/config.env > /dev/null << 'CONFIG_EOF'
# SUI Proxy 配置文件
DOMAIN=""
EMAIL=""
VLESS_PORT=8443
ADMIN_PORT=8080
DEPLOY_MODE="both"
CONFIG_EOF

# 5. 创建主安装脚本
echo "🔧 创建 install.sh..."
sudo tee /opt/sui-proxy/install.sh > /dev/null << 'INSTALL_EOF'
#!/bin/bash
# 这里是完整的 install.sh 内容
# 由于内容很长，这里先创建框架，稍后可以替换完整内容
echo "SUI Proxy 安装框架"
echo "请从AI助手获取完整版本"
INSTALL_EOF

sudo chmod +x /opt/sui-proxy/install.sh

# 6. 创建证书更新脚本
echo "📜 创建 cert-renewal.sh..."
sudo tee /opt/sui-proxy/cert-renewal.sh > /dev/null << 'CERT_EOF'
#!/bin/bash
# 这里是完整的 cert-renewal.sh 内容
echo "证书管理脚本框架"
echo "请从AI助手获取完整版本"
CERT_EOF

sudo chmod +x /opt/sui-proxy/cert-renewal.sh

# 7. 创建健康检查脚本
echo "🏥 创建健康检查脚本..."
sudo tee /opt/sui-proxy/scripts/health-check.sh > /dev/null << 'HEALTH_EOF'
#!/bin/bash
echo "健康检查脚本"
HEALTH_EOF

sudo chmod +x /opt/sui-proxy/scripts/*.sh

echo "✅ 基础设置完成！"
echo ""
echo "下一步："
echo "1. 从AI助手获取完整的脚本内容"
echo "2. 替换框架文件中的内容"
echo "3. 运行: sudo /opt/sui-proxy/install.sh"
echo ""
echo "目录结构："
echo "  /opt/sui-proxy/          # 主安装目录"
echo "  /etc/sui-proxy/          # 配置文件"
echo "  /var/log/sui-proxy/      # 日志文件"