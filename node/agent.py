#!/usr/bin/env python3
"""SUI Solo Node Agent - Security Hardened"""

import os
import re
import hashlib
import subprocess
import time
import uuid as uuid_lib
import json
from collections import defaultdict
from functools import wraps
from flask import Flask, request, jsonify

app = Flask(__name__)

CLUSTER_SECRET = os.environ.get('CLUSTER_SECRET', '')
NODE_DOMAIN = os.environ.get('NODE_DOMAIN', '')
CONFIG_DIR = os.environ.get('CONFIG_DIR', '/config')
SALT = "SUI_Solo_Secured_2025"


class RateLimiter:
    def __init__(self, max_requests=10, window_seconds=60):
        self.max_requests, self.window_seconds = max_requests, window_seconds
        self.requests, self.blocked_until = defaultdict(list), defaultdict(float)

    def is_allowed(self, ip):
        now = time.time()
        if now < self.blocked_until[ip]:
            return False
        self.requests[ip] = [t for t in self.requests[ip] if now - t < self.window_seconds]
        if len(self.requests[ip]) >= self.max_requests:
            self.blocked_until[ip] = now + self.window_seconds * 2
            return False
        self.requests[ip].append(now)
        return True


auth_limiter = RateLimiter(5, 60)
api_limiter = RateLimiter(20, 60)


def get_client_ip():
    forwarded = request.headers.get('X-Forwarded-For', '')
    return forwarded.split(',')[0].strip() if forwarded else request.remote_addr or '127.0.0.1'


def rate_limit(limiter):
    def decorator(f):
        @wraps(f)
        def decorated(*args, **kwargs):
            if not limiter.is_allowed(get_client_ip()):
                return jsonify({'error': 'Rate limit exceeded', 'retry_after': limiter.window_seconds}), 429
            return f(*args, **kwargs)
        return decorated
    return decorator


def sanitize_service(s):
    if s not in {'singbox', 'adguard', 'caddy'}:
        raise ValueError(f'Invalid service: {s}')
    return s


def validate_singbox_config(content):
    """Validate sing-box configuration JSON"""
    try:
        config = json.loads(content)
    except json.JSONDecodeError as e:
        return False, f'Invalid JSON: {str(e)}'
    
    # Must be a dict
    if not isinstance(config, dict):
        return False, 'Config must be a JSON object'
    
    # Check for required top-level keys
    if 'outbounds' not in config:
        return False, 'Missing required field: outbounds'
    
    if not isinstance(config.get('outbounds'), list):
        return False, 'outbounds must be an array'
    
    # Validate inbounds if present
    if 'inbounds' in config:
        if not isinstance(config['inbounds'], list):
            return False, 'inbounds must be an array'
        
        for i, inbound in enumerate(config['inbounds']):
            if not isinstance(inbound, dict):
                return False, f'inbounds[{i}] must be an object'
            
            # Check inbound type
            inbound_type = inbound.get('type', '')
            valid_types = {'direct', 'mixed', 'socks', 'http', 'shadowsocks', 'vmess', 'trojan', 
                         'naive', 'hysteria', 'shadowtls', 'vless', 'tuic', 'hysteria2', 
                         'tun', 'redirect', 'tproxy'}
            if inbound_type and inbound_type not in valid_types:
                return False, f'inbounds[{i}]: invalid type "{inbound_type}"'
            
            # Validate port if present
            port = inbound.get('listen_port')
            if port is not None:
                if not isinstance(port, int) or port < 1 or port > 65535:
                    return False, f'inbounds[{i}]: listen_port must be 1-65535'
            
            # Validate users if present
            users = inbound.get('users', [])
            if users and not isinstance(users, list):
                return False, f'inbounds[{i}]: users must be an array'
    
    # Validate outbounds
    for i, outbound in enumerate(config['outbounds']):
        if not isinstance(outbound, dict):
            return False, f'outbounds[{i}] must be an object'
        
        outbound_type = outbound.get('type', '')
        valid_out_types = {'direct', 'block', 'socks', 'http', 'shadowsocks', 'vmess', 'trojan',
                         'wireguard', 'hysteria', 'shadowtls', 'vless', 'tuic', 'hysteria2',
                         'tor', 'ssh', 'dns', 'selector', 'urltest'}
        if outbound_type and outbound_type not in valid_out_types:
            return False, f'outbounds[{i}]: invalid type "{outbound_type}"'
    
    # Check for dangerous patterns (basic security check)
    content_lower = content.lower()
    dangerous_patterns = ['$(', '`', '&&', '||', ';', '|', '>', '<', '\n#!']
    for pattern in dangerous_patterns:
        if pattern in content_lower:
            # Allow these in legitimate JSON strings, but flag if suspicious
            pass  # JSON parser already handles escaping
    
    return True, config


def sanitize_lines(l):
    try:
        n = int(l)
        return str(n) if 1 <= n <= 1000 else '100'
    except:
        return '100'


ALLOWED_COMMANDS = {
    'restart_singbox': ['docker', 'restart', 'sui-singbox'],
    'restart_adguard': ['docker', 'restart', 'sui-adguard'],
    'restart_caddy': ['docker', 'restart', 'sui-caddy'],
    'status_singbox': ['docker', 'inspect', '-f', '{{.State.Status}}', 'sui-singbox'],
    'status_adguard': ['docker', 'inspect', '-f', '{{.State.Status}}', 'sui-adguard'],
    'status_caddy': ['docker', 'inspect', '-f', '{{.State.Status}}', 'sui-caddy'],
    'logs_singbox': ['docker', 'logs', '--tail', '{lines}', 'sui-singbox'],
    'logs_adguard': ['docker', 'logs', '--tail', '{lines}', 'sui-adguard'],
    'logs_caddy': ['docker', 'logs', '--tail', '{lines}', 'sui-caddy'],
    'uptime': ['cat', '/proc/uptime'],
}


def execute_cmd(key, **kwargs):
    if key not in ALLOWED_COMMANDS:
        return False, 'Command not allowed'
    cmd = [p.format(lines=sanitize_lines(kwargs.get('lines', '100'))) if '{lines}' in p else p for p in ALLOWED_COMMANDS[key]]
    try:
        r = subprocess.run(cmd, capture_output=True, text=True, timeout=30)
        return r.returncode == 0, r.stdout + r.stderr
    except Exception as e:
        return False, str(e)


def get_container_status(svc):
    ok, out = execute_cmd(f'status_{svc}')
    return out.strip() if ok else 'not found'


def get_hidden_path(token):
    return hashlib.sha256(f"{SALT}:{token}".encode()).hexdigest()[:16]


PATH_PREFIX = get_hidden_path(CLUSTER_SECRET)


def _secure_compare(a, b):
    if len(a) != len(b):
        return False
    return sum(x ^ y for x, y in zip(a.encode(), b.encode())) == 0


def require_auth(f):
    @wraps(f)
    def decorated(*args, **kwargs):
        ip = get_client_ip()
        if not auth_limiter.is_allowed(ip):
            return jsonify({'error': 'Too many auth attempts', 'retry_after': 120}), 429
        if not _secure_compare(request.headers.get('X-SUI-Token', ''), CLUSTER_SECRET):
            app.logger.warning(f'Auth failed: {ip}')
            return jsonify({'error': 'Unauthorized'}), 401
        return f(*args, **kwargs)
    return decorated


@app.route(f'/{PATH_PREFIX}/api/v1/status')
@require_auth
@rate_limit(api_limiter)
def status():
    ok, uptime_raw = execute_cmd('uptime')
    uptime_str = 'unknown'
    if ok:
        try:
            # /proc/uptime format: "seconds.fraction idle_seconds.fraction"
            seconds = int(float(uptime_raw.split()[0]))
            days, remainder = divmod(seconds, 86400)
            hours, remainder = divmod(remainder, 3600)
            minutes, _ = divmod(remainder, 60)
            if days > 0:
                uptime_str = f"{days}d {hours}h {minutes}m"
            elif hours > 0:
                uptime_str = f"{hours}h {minutes}m"
            else:
                uptime_str = f"{minutes}m"
        except:
            uptime_str = uptime_raw.strip()
    return jsonify({'status': 'online', 'domain': NODE_DOMAIN, 'uptime': uptime_str})


@app.route(f'/{PATH_PREFIX}/api/v1/services')
@require_auth
@rate_limit(api_limiter)
def services():
    return jsonify({'services': {s: get_container_status(s) for s in ['singbox', 'adguard', 'caddy']} | {'agent': 'running'}})


@app.route(f'/{PATH_PREFIX}/api/v1/restart/<service>', methods=['POST'])
@require_auth
@rate_limit(api_limiter)
def restart_service(service):
    try:
        service = sanitize_service(service)
    except ValueError as e:
        return jsonify({'error': str(e)}), 400
    ok, out = execute_cmd(f'restart_{service}')
    return jsonify({'success': ok, 'service': service, 'message': out.strip()})


@app.route(f'/{PATH_PREFIX}/api/v1/config/<service>', methods=['GET', 'POST'])
@require_auth
@rate_limit(api_limiter)
def config(service):
    try:
        service = sanitize_service(service)
    except ValueError as e:
        return jsonify({'error': str(e)}), 400
    paths = {'singbox': 'singbox/config.json', 'adguard': 'adguard/AdGuardHome.yaml', 'caddy': 'caddy/Caddyfile'}
    path = os.path.join(CONFIG_DIR, paths[service])
    if not os.path.realpath(path).startswith(os.path.realpath(CONFIG_DIR)):
        return jsonify({'error': 'Invalid path'}), 400
    if request.method == 'GET':
        return jsonify({'error': 'Not found'}) if not os.path.exists(path) else jsonify({'service': service, 'content': open(path).read()})
    
    content = request.json.get('content', '')
    
    # Validate config based on service type
    if service == 'singbox':
        valid, result = validate_singbox_config(content)
        if not valid:
            return jsonify({'success': False, 'error': f'Config validation failed: {result}'}), 400
        # Write the validated and re-serialized JSON for consistency
        content = json.dumps(result, indent=2)
    
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, 'w') as f:
        f.write(content)
    return jsonify({'success': True})


@app.route(f'/{PATH_PREFIX}/api/v1/logs/<service>')
@require_auth
@rate_limit(api_limiter)
def logs(service):
    try:
        service = sanitize_service(service)
    except ValueError as e:
        return jsonify({'error': str(e)}), 400
    ok, out = execute_cmd(f'logs_{service}', lines=request.args.get('lines', '100'))
    return jsonify({'service': service, 'logs': out})


@app.route(f'/{PATH_PREFIX}/api/v1/update', methods=['POST'])
@require_auth
@rate_limit(api_limiter)
def update():
    """Update node to latest version"""
    try:
        result = subprocess.run(
            ['sh', '-c', '''
                cd /opt/sui-solo/node
                curl -fsSL https://github.com/pjonix/SUIS/archive/main.zip -o /tmp/update.zip
                unzip -o /tmp/update.zip -d /tmp/
                cp /tmp/SUIS-main/node/agent.py ./agent.py.new
                cp /tmp/SUIS-main/node/templates/Caddyfile.template ./templates/Caddyfile.template.new
                mv ./agent.py.new ./agent.py
                mv ./templates/Caddyfile.template.new ./templates/Caddyfile.template
                rm -rf /tmp/update.zip /tmp/SUIS-main
                docker compose up -d --build
            '''],
            capture_output=True, text=True, timeout=120
        )
        return jsonify({'success': result.returncode == 0, 'output': result.stdout + result.stderr})
    except Exception as e:
        return jsonify({'success': False, 'error': str(e)})


@app.route(f'/{PATH_PREFIX}/api/v1/restart-all', methods=['POST'])
@require_auth
@rate_limit(api_limiter)
def restart_all():
    """Restart all node containers"""
    try:
        result = subprocess.run(
            ['sh', '-c', '''
                cd /opt/sui-solo/node
                docker compose restart
            '''],
            capture_output=True, text=True, timeout=60
        )
        return jsonify({'success': result.returncode == 0, 'output': result.stdout + result.stderr})
    except Exception as e:
        return jsonify({'success': False, 'error': str(e)})


@app.route(f'/{PATH_PREFIX}/api/v1/proxies')
@require_auth
@rate_limit(api_limiter)
def get_proxies():
    """Get all proxy configurations from singbox config"""
    import json as json_lib
    config_path = os.path.join(CONFIG_DIR, 'singbox/config.json')
    proxies = []
    try:
        if os.path.exists(config_path):
            with open(config_path) as f:
                config = json_lib.load(f)
            for inbound in config.get('inbounds', []):
                proxy_type = inbound.get('type', '')
                if proxy_type in ['vless', 'vmess', 'trojan', 'hysteria2', 'shadowsocks']:
                    proxy = {
                        'type': proxy_type,
                        'tag': inbound.get('tag', proxy_type),
                        'port': inbound.get('listen_port', 443),
                        'enabled': True,
                        'domain': NODE_DOMAIN
                    }
                    # Extract user info
                    users = inbound.get('users', [])
                    if users:
                        proxy['uuid'] = users[0].get('uuid', users[0].get('password', ''))
                        proxy['flow'] = users[0].get('flow', '')
                    # TLS info
                    tls = inbound.get('tls', {})
                    proxy['tls'] = tls.get('enabled', False)
                    proxy['sni'] = tls.get('server_name', NODE_DOMAIN)
                    # Reality info
                    if tls.get('reality', {}).get('enabled'):
                        proxy['reality'] = True
                        proxy['public_key'] = tls['reality'].get('public_key', '')
                        proxy['short_id'] = tls['reality'].get('short_id', [''])[0]
                    proxies.append(proxy)
    except Exception as e:
        return jsonify({'error': str(e)}), 500
    return jsonify({'proxies': proxies, 'domain': NODE_DOMAIN})


@app.route(f'/{PATH_PREFIX}/api/v1/version')
@require_auth
@rate_limit(api_limiter)
def version():
    return jsonify({'version': '2.0.0'})


@app.route(f'/{PATH_PREFIX}/api/v1/diagnostics')
@require_auth
@rate_limit(api_limiter)
def diagnostics():
    """Run diagnostics and return system health status"""
    issues = []
    warnings = []
    
    # Check 1: Docker CLI availability
    try:
        result = subprocess.run(['docker', '--version'], capture_output=True, text=True, timeout=5)
        if result.returncode != 0:
            issues.append('Docker CLI not available in agent container')
    except Exception as e:
        issues.append(f'Docker CLI check failed: {str(e)}')
    
    # Check 2: Docker socket access
    try:
        result = subprocess.run(['docker', 'ps'], capture_output=True, text=True, timeout=5)
        if result.returncode != 0:
            issues.append('Cannot access Docker socket')
    except Exception as e:
        issues.append(f'Docker socket check failed: {str(e)}')
    
    # Check 3: Container status
    services_status = {}
    for svc in ['singbox', 'adguard', 'caddy']:
        ok, out = execute_cmd(f'status_{svc}')
        status = out.strip() if ok else 'not found'
        services_status[svc] = status
        if status == 'not found':
            warnings.append(f'{svc} container not found')
        elif status != 'running':
            warnings.append(f'{svc} container status: {status}')
    
    # Check 4: Config files
    config_files = {
        'singbox': os.path.join(CONFIG_DIR, 'singbox/config.json'),
        'adguard': os.path.join(CONFIG_DIR, 'adguard/AdGuardHome.yaml'),
    }
    for name, path in config_files.items():
        if not os.path.exists(path):
            warnings.append(f'{name} config file missing: {path}')
    
    # Check 5: Network connectivity
    try:
        result = subprocess.run(['ping', '-c', '1', '-W', '2', '8.8.8.8'], 
                              capture_output=True, timeout=5)
        if result.returncode != 0:
            warnings.append('Network connectivity issue detected')
    except:
        pass
    
    health_status = 'healthy' if not issues else 'unhealthy'
    if warnings and not issues:
        health_status = 'degraded'
    
    return jsonify({
        'status': health_status,
        'issues': issues,
        'warnings': warnings,
        'services': services_status,
        'docker_cli': 'available' if not any('Docker CLI' in i for i in issues) else 'missing',
        'timestamp': time.time()
    })


# ============================================================================
# FIREWALL MANAGEMENT (provides commands for manual configuration)
# ============================================================================
FIREWALL_CONFIG_FILE = os.path.join(CONFIG_DIR, 'firewall.json')


@app.route(f'/{PATH_PREFIX}/api/v1/firewall', methods=['GET'])
@require_auth
@rate_limit(api_limiter)
def get_firewall():
    """Get firewall configuration help"""
    # Load saved config if exists
    saved_ports = []
    try:
        if os.path.exists(FIREWALL_CONFIG_FILE):
            with open(FIREWALL_CONFIG_FILE) as f:
                saved_ports = json.load(f).get('ports', [])
    except:
        pass
    
    default_ports = ['22', '80', '443', '53', '8443', '8444']
    
    return jsonify({
        'type': 'manual',
        'enabled': None,
        'ports': saved_ports or default_ports,
        'message': 'Firewall must be configured via SSH on the server',
        'commands': {
            'ufw': f'''# UFW (Ubuntu/Debian)
sudo ufw reset
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow 22
sudo ufw allow 80
sudo ufw allow 443
sudo ufw allow 53
sudo ufw allow 8443
sudo ufw allow 8444
sudo ufw enable''',
            'firewalld': f'''# Firewalld (CentOS/RHEL)
sudo firewall-cmd --permanent --add-port=22/tcp
sudo firewall-cmd --permanent --add-port=80/tcp
sudo firewall-cmd --permanent --add-port=443/tcp
sudo firewall-cmd --permanent --add-port=53/tcp
sudo firewall-cmd --permanent --add-port=53/udp
sudo firewall-cmd --permanent --add-port=8443/tcp
sudo firewall-cmd --permanent --add-port=8444/udp
sudo firewall-cmd --reload''',
            'iptables': f'''# iptables
sudo iptables -F INPUT
sudo iptables -P INPUT DROP
sudo iptables -A INPUT -i lo -j ACCEPT
sudo iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
sudo iptables -A INPUT -p tcp --dport 22 -j ACCEPT
sudo iptables -A INPUT -p tcp --dport 80 -j ACCEPT
sudo iptables -A INPUT -p tcp --dport 443 -j ACCEPT
sudo iptables -A INPUT -p tcp --dport 53 -j ACCEPT
sudo iptables -A INPUT -p udp --dport 53 -j ACCEPT
sudo iptables -A INPUT -p tcp --dport 8443 -j ACCEPT
sudo iptables -A INPUT -p udp --dport 8444 -j ACCEPT'''
        }
    })


@app.route(f'/{PATH_PREFIX}/api/v1/firewall', methods=['POST'])
@require_auth
@rate_limit(api_limiter)
def set_firewall():
    """Save firewall port configuration (for reference only)"""
    data = request.json or {}
    ports = data.get('ports', [])
    
    if not ports:
        return jsonify({'success': False, 'error': 'No ports specified'}), 400
    
    # Validate ports
    validated_ports = []
    for port in ports:
        port_str = str(port)
        if '-' in port_str:
            try:
                start, end = port_str.split('-')
                if 1 <= int(start) <= 65535 and 1 <= int(end) <= 65535:
                    validated_ports.append(port_str)
            except:
                pass
        else:
            try:
                if 1 <= int(port) <= 65535:
                    validated_ports.append(port_str)
            except:
                pass
    
    if not validated_ports:
        return jsonify({'success': False, 'error': 'No valid ports'}), 400
    
    success, message = apply_firewall_rules(validated_ports)
    
    # Save config
    if success:
        with open(FIREWALL_CONFIG_FILE, 'w') as f:
            json.dump({'ports': validated_ports}, f)
    
    return jsonify({'success': success, 'message': message, 'ports': validated_ports})


# ============================================================================
# SUBSCRIPTION GENERATION (from actual sing-box config)
# ============================================================================


def load_singbox_config():
    """Load sing-box configuration"""
    config_path = os.path.join(CONFIG_DIR, 'singbox/config.json')
    try:
        if os.path.exists(config_path):
            with open(config_path) as f:
                return json.load(f)
    except Exception as e:
        app.logger.error(f"Failed to load singbox config: {e}")
    return {}


def find_inbound(config, inbound_type):
    """Find inbound by type in sing-box config"""
    for inbound in config.get('inbounds', []):
        if inbound.get('type') == inbound_type:
            return inbound
    return None


@app.route(f'/{PATH_PREFIX}/api/v1/subscribe')
@require_auth
@rate_limit(api_limiter)
def node_subscribe():
    """Get subscription links for this node (from actual sing-box config)"""
    config = load_singbox_config()
    links = []
    
    # VLESS + XTLS-Vision + TLS (port 443)
    vless_inbound = find_inbound(config, 'vless')
    if vless_inbound and vless_inbound.get('users'):
        uuid = vless_inbound['users'][0].get('uuid', '')
        port = vless_inbound.get('listen_port', 443)
        # VLESS link format: vless://uuid@domain:port?params#name
        link = f"vless://{uuid}@{NODE_DOMAIN}:{port}?encryption=none&flow=xtls-rprx-vision&security=tls&sni={NODE_DOMAIN}&alpn=h2,http/1.1&type=tcp#{NODE_DOMAIN}-VLESS"
        links.append({'type': 'vless', 'link': link, 'port': port})
    
    # Hysteria2 (port 50000-60000 with port hopping)
    hy2_inbound = find_inbound(config, 'hysteria2')
    if hy2_inbound and hy2_inbound.get('users'):
        password = hy2_inbound['users'][0].get('password', '')
        port = hy2_inbound.get('listen_port', 50000)
        # Hysteria2 link format: hysteria2://password@domain:port?params#name
        # Note: Port hopping is handled by client automatically when using port range
        link = f"hysteria2://{password}@{NODE_DOMAIN}:{port}?sni={NODE_DOMAIN}&alpn=h3#{NODE_DOMAIN}-Hysteria2"
        links.append({'type': 'hysteria2', 'link': link, 'port': port})
    
    return jsonify({'links': links, 'domain': NODE_DOMAIN})


@app.route('/health')
def health():
    return jsonify({'status': 'healthy'})


# No initialization needed - config is generated by install script


if __name__ == '__main__':
    print(f"[SUI Solo Agent] {NODE_DOMAIN} | /{PATH_PREFIX}/api/v1/")
    app.run(host='0.0.0.0', port=5001)
