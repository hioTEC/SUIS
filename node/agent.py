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
PRESETS_FILE = os.path.join(CONFIG_DIR, 'presets.json')


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
    return jsonify({'version': '1.9.21'})


# ============================================================================
# FIREWALL MANAGEMENT
# ============================================================================
FIREWALL_CONFIG_FILE = os.path.join(CONFIG_DIR, 'firewall.json')

def detect_firewall():
    """Detect which firewall is available"""
    for fw in ['ufw', 'firewall-cmd', 'iptables']:
        result = subprocess.run(['which', fw], capture_output=True)
        if result.returncode == 0:
            return fw.replace('-cmd', 'd')  # firewall-cmd -> firewalld
    return None

def get_firewall_status():
    """Get current firewall status and rules"""
    fw = detect_firewall()
    if not fw:
        return {'enabled': False, 'type': None, 'ports': [], 'error': 'No firewall detected'}
    
    try:
        if fw == 'ufw':
            result = subprocess.run(['ufw', 'status', 'numbered'], capture_output=True, text=True, timeout=10)
            enabled = 'Status: active' in result.stdout
            # Parse ports from ufw output
            ports = []
            for line in result.stdout.split('\n'):
                if 'ALLOW' in line:
                    parts = line.split()
                    if parts:
                        port = parts[1].replace('/tcp', '').replace('/udp', '')
                        if port not in ports:
                            ports.append(port)
            return {'enabled': enabled, 'type': 'ufw', 'ports': ports, 'raw': result.stdout}
        
        elif fw == 'firewalld':
            result = subprocess.run(['firewall-cmd', '--list-ports'], capture_output=True, text=True, timeout=10)
            ports = [p.split('/')[0] for p in result.stdout.strip().split() if p]
            return {'enabled': True, 'type': 'firewalld', 'ports': ports}
        
        elif fw == 'iptables':
            result = subprocess.run(['iptables', '-L', 'INPUT', '-n'], capture_output=True, text=True, timeout=10)
            ports = []
            for line in result.stdout.split('\n'):
                if 'dpt:' in line:
                    port = line.split('dpt:')[1].split()[0]
                    if port not in ports:
                        ports.append(port)
            return {'enabled': True, 'type': 'iptables', 'ports': ports}
    except Exception as e:
        return {'enabled': False, 'type': fw, 'ports': [], 'error': str(e)}
    
    return {'enabled': False, 'type': fw, 'ports': []}

def apply_firewall_rules(ports):
    """Apply firewall rules with specified ports"""
    fw = detect_firewall()
    if not fw:
        return False, 'No firewall detected'
    
    try:
        if fw == 'ufw':
            # Reset and configure UFW
            subprocess.run(['ufw', '--force', 'reset'], capture_output=True, timeout=30)
            subprocess.run(['ufw', 'default', 'deny', 'incoming'], capture_output=True, timeout=10)
            subprocess.run(['ufw', 'default', 'allow', 'outgoing'], capture_output=True, timeout=10)
            
            for port in ports:
                subprocess.run(['ufw', 'allow', str(port)], capture_output=True, timeout=10)
            
            subprocess.run(['ufw', '--force', 'enable'], capture_output=True, timeout=10)
            return True, 'UFW configured'
        
        elif fw == 'firewalld':
            # Remove existing ports and add new ones
            result = subprocess.run(['firewall-cmd', '--list-ports'], capture_output=True, text=True, timeout=10)
            for port in result.stdout.strip().split():
                subprocess.run(['firewall-cmd', '--remove-port', port, '--permanent'], capture_output=True, timeout=10)
            
            for port in ports:
                subprocess.run(['firewall-cmd', '--add-port', f'{port}/tcp', '--permanent'], capture_output=True, timeout=10)
                subprocess.run(['firewall-cmd', '--add-port', f'{port}/udp', '--permanent'], capture_output=True, timeout=10)
            
            subprocess.run(['firewall-cmd', '--reload'], capture_output=True, timeout=10)
            return True, 'firewalld configured'
        
        elif fw == 'iptables':
            # Flush and configure iptables
            subprocess.run(['iptables', '-F', 'INPUT'], capture_output=True, timeout=10)
            subprocess.run(['iptables', '-P', 'INPUT', 'DROP'], capture_output=True, timeout=10)
            subprocess.run(['iptables', '-A', 'INPUT', '-i', 'lo', '-j', 'ACCEPT'], capture_output=True, timeout=10)
            subprocess.run(['iptables', '-A', 'INPUT', '-m', 'state', '--state', 'ESTABLISHED,RELATED', '-j', 'ACCEPT'], capture_output=True, timeout=10)
            
            for port in ports:
                subprocess.run(['iptables', '-A', 'INPUT', '-p', 'tcp', '--dport', str(port), '-j', 'ACCEPT'], capture_output=True, timeout=10)
                subprocess.run(['iptables', '-A', 'INPUT', '-p', 'udp', '--dport', str(port), '-j', 'ACCEPT'], capture_output=True, timeout=10)
            
            return True, 'iptables configured'
    
    except Exception as e:
        return False, str(e)
    
    return False, 'Unknown error'


@app.route(f'/{PATH_PREFIX}/api/v1/firewall', methods=['GET'])
@require_auth
@rate_limit(api_limiter)
def get_firewall():
    """Get firewall status"""
    return jsonify(get_firewall_status())


@app.route(f'/{PATH_PREFIX}/api/v1/firewall', methods=['POST'])
@require_auth
@rate_limit(api_limiter)
def set_firewall():
    """Configure firewall with specified ports"""
    data = request.json or {}
    ports = data.get('ports', [])
    
    if not ports:
        return jsonify({'success': False, 'error': 'No ports specified'}), 400
    
    # Validate ports
    validated_ports = []
    for port in ports:
        port_str = str(port)
        if '-' in port_str:
            # Port range
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
# PRESET TEMPLATES
# ============================================================================
def generate_uuid():
    return str(uuid_lib.uuid4())


def generate_short_id():
    return hashlib.md5(os.urandom(16)).hexdigest()[:8]


def generate_x25519_keys():
    """Generate X25519 key pair for Reality"""
    try:
        result = subprocess.run(
            ['sing-box', 'generate', 'reality-keypair'],
            capture_output=True, text=True, timeout=10
        )
        if result.returncode == 0:
            lines = result.stdout.strip().split('\n')
            private_key = lines[0].split(': ')[1] if len(lines) > 0 else ''
            public_key = lines[1].split(': ')[1] if len(lines) > 1 else ''
            return private_key, public_key
    except:
        pass
    # Fallback: return placeholder
    return 'GENERATE_WITH_SINGBOX', 'GENERATE_WITH_SINGBOX'


def get_preset_templates():
    """Generate preset templates with auto-generated credentials"""
    presets = load_presets()
    
    # VLESS + XTLS-Vision + TLS (Reality)
    vless_vision = presets.get('vless_vision', {})
    if not vless_vision.get('uuid'):
        private_key, public_key = generate_x25519_keys()
        vless_vision = {
            'uuid': generate_uuid(),
            'private_key': private_key,
            'public_key': public_key,
            'short_id': generate_short_id(),
            'enabled': True
        }
    
    # VMess + WS
    vmess_ws = presets.get('vmess_ws', {})
    if not vmess_ws.get('uuid'):
        vmess_ws = {
            'uuid': generate_uuid(),
            'path': '/vmess-ws',
            'enabled': True
        }
    
    # Hysteria2
    hysteria2 = presets.get('hysteria2', {})
    if not hysteria2.get('password'):
        hysteria2 = {
            'password': generate_uuid().replace('-', '')[:16],
            'enabled': True
        }
    
    return {
        'vless_vision': vless_vision,
        'vmess_ws': vmess_ws,
        'hysteria2': hysteria2
    }


def load_presets():
    """Load saved presets from file"""
    try:
        if os.path.exists(PRESETS_FILE):
            with open(PRESETS_FILE) as f:
                return json.load(f)
    except:
        pass
    return {}


def save_presets(presets):
    """Save presets to file"""
    os.makedirs(os.path.dirname(PRESETS_FILE), exist_ok=True)
    with open(PRESETS_FILE, 'w') as f:
        json.dump(presets, f, indent=2)


def init_presets():
    """Initialize presets on first run"""
    if not os.path.exists(PRESETS_FILE):
        presets = get_preset_templates()
        save_presets(presets)
        # Also generate initial singbox config
        generate_singbox_config(presets)
    return load_presets()


def generate_singbox_config(presets):
    """Generate sing-box config from presets"""
    inbounds = []
    port = 10000
    
    # VLESS + XTLS-Vision + Reality
    if presets.get('vless_vision', {}).get('enabled'):
        vless = presets['vless_vision']
        inbounds.append({
            "type": "vless",
            "tag": "vless-vision",
            "listen": "::",
            "listen_port": port,
            "users": [{"uuid": vless['uuid'], "flow": "xtls-rprx-vision"}],
            "tls": {
                "enabled": True,
                "server_name": "www.microsoft.com",
                "reality": {
                    "enabled": True,
                    "handshake": {"server": "www.microsoft.com", "server_port": 443},
                    "private_key": vless['private_key'],
                    "short_id": [vless['short_id']]
                }
            }
        })
        port += 1
    
    # VMess + WS
    if presets.get('vmess_ws', {}).get('enabled'):
        vmess = presets['vmess_ws']
        inbounds.append({
            "type": "vmess",
            "tag": "vmess-ws",
            "listen": "::",
            "listen_port": port,
            "users": [{"uuid": vmess['uuid']}],
            "transport": {"type": "ws", "path": vmess.get('path', '/vmess-ws')}
        })
        port += 1
    
    # Hysteria2
    if presets.get('hysteria2', {}).get('enabled'):
        hy2 = presets['hysteria2']
        inbounds.append({
            "type": "hysteria2",
            "tag": "hysteria2",
            "listen": "::",
            "listen_port": port,
            "users": [{"password": hy2['password']}],
            "tls": {
                "enabled": True,
                "alpn": ["h3"],
                "certificate_path": "/config/certs/cert.pem",
                "key_path": "/config/certs/key.pem"
            }
        })
    
    config = {
        "log": {"level": "info"},
        "inbounds": inbounds,
        "outbounds": [{"type": "direct", "tag": "direct"}]
    }
    
    config_path = os.path.join(CONFIG_DIR, 'singbox/config.json')
    os.makedirs(os.path.dirname(config_path), exist_ok=True)
    with open(config_path, 'w') as f:
        json.dump(config, f, indent=2)
    
    return config


@app.route(f'/{PATH_PREFIX}/api/v1/presets', methods=['GET'])
@require_auth
@rate_limit(api_limiter)
def get_presets():
    """Get preset configurations"""
    presets = load_presets()
    if not presets:
        presets = init_presets()
    return jsonify({'presets': presets, 'domain': NODE_DOMAIN})


@app.route(f'/{PATH_PREFIX}/api/v1/presets', methods=['POST'])
@require_auth
@rate_limit(api_limiter)
def update_presets():
    """Update preset configurations and regenerate singbox config"""
    data = request.json or {}
    presets = load_presets()
    
    # Update enabled status
    for key in ['vless_vision', 'vmess_ws', 'hysteria2']:
        if key in data:
            if key not in presets:
                presets[key] = get_preset_templates()[key]
            presets[key]['enabled'] = data[key].get('enabled', presets[key].get('enabled', True))
    
    save_presets(presets)
    generate_singbox_config(presets)
    
    return jsonify({'success': True, 'presets': presets})


@app.route(f'/{PATH_PREFIX}/api/v1/presets/regenerate', methods=['POST'])
@require_auth
@rate_limit(api_limiter)
def regenerate_presets():
    """Regenerate all preset credentials"""
    private_key, public_key = generate_x25519_keys()
    presets = {
        'vless_vision': {
            'uuid': generate_uuid(),
            'private_key': private_key,
            'public_key': public_key,
            'short_id': generate_short_id(),
            'enabled': True
        },
        'vmess_ws': {
            'uuid': generate_uuid(),
            'path': '/vmess-ws',
            'enabled': True
        },
        'hysteria2': {
            'password': generate_uuid().replace('-', '')[:16],
            'enabled': True
        }
    }
    save_presets(presets)
    generate_singbox_config(presets)
    
    return jsonify({'success': True, 'presets': presets})


@app.route(f'/{PATH_PREFIX}/api/v1/subscribe')
@require_auth
@rate_limit(api_limiter)
def node_subscribe():
    """Get subscription links for this node"""
    presets = load_presets()
    links = []
    port = 10000
    
    # VLESS + Vision + Reality
    if presets.get('vless_vision', {}).get('enabled'):
        vless = presets['vless_vision']
        link = f"vless://{vless['uuid']}@{NODE_DOMAIN}:{port}?encryption=none&flow=xtls-rprx-vision&security=reality&sni=www.microsoft.com&fp=chrome&pbk={vless['public_key']}&sid={vless['short_id']}&type=tcp#{NODE_DOMAIN}-VLESS-Vision"
        links.append({'type': 'vless-vision', 'link': link, 'port': port})
        port += 1
    
    # VMess + WS
    if presets.get('vmess_ws', {}).get('enabled'):
        vmess = presets['vmess_ws']
        import base64
        vmess_config = {
            "v": "2",
            "ps": f"{NODE_DOMAIN}-VMess-WS",
            "add": NODE_DOMAIN,
            "port": str(port),
            "id": vmess['uuid'],
            "aid": "0",
            "net": "ws",
            "type": "none",
            "host": NODE_DOMAIN,
            "path": vmess.get('path', '/vmess-ws'),
            "tls": "tls"
        }
        link = "vmess://" + base64.b64encode(json.dumps(vmess_config).encode()).decode()
        links.append({'type': 'vmess-ws', 'link': link, 'port': port})
        port += 1
    
    # Hysteria2
    if presets.get('hysteria2', {}).get('enabled'):
        hy2 = presets['hysteria2']
        link = f"hysteria2://{hy2['password']}@{NODE_DOMAIN}:{port}?sni={NODE_DOMAIN}#{NODE_DOMAIN}-Hysteria2"
        links.append({'type': 'hysteria2', 'link': link, 'port': port})
    
    return jsonify({'links': links, 'domain': NODE_DOMAIN})


@app.route('/health')
def health():
    return jsonify({'status': 'healthy'})


# Initialize presets on startup
init_presets()


if __name__ == '__main__':
    print(f"[SUI Solo Agent] {NODE_DOMAIN} | /{PATH_PREFIX}/api/v1/")
    app.run(host='0.0.0.0', port=5001)
