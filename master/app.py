#!/usr/bin/env python3
"""SUI Solo Master Controller - Flask Backend with Security Hardening"""

import os
import re
import hashlib
import json
import time
import subprocess
from datetime import datetime
from collections import defaultdict
from functools import wraps
from flask import Flask, render_template, request, jsonify
import requests

app = Flask(__name__)

DATA_DIR = os.environ.get('DATA_DIR', '/data')
CLUSTER_SECRET = os.environ.get('CLUSTER_SECRET', '')
NODES_FILE = os.path.join(DATA_DIR, 'nodes.json')
SETTINGS_FILE = os.path.join(DATA_DIR, 'settings.json')
SALT = "SUI_Solo_Secured_2025"
VERSION = "1.9.21"
GITHUB_REPO = "https://github.com/pjonix/SUIS"
GITHUB_RAW = "https://raw.githubusercontent.com/pjonix/SUIS/main"

# Regex patterns
DOMAIN_PATTERN = re.compile(r'^[a-zA-Z0-9]([a-zA-Z0-9\-\.]{0,253}[a-zA-Z0-9])?$')
NODE_ID_PATTERN = re.compile(r'^[a-f0-9]{8}$')


class RateLimiter:
    def __init__(self, max_requests: int = 10, window_seconds: int = 60):
        self.max_requests = max_requests
        self.window_seconds = window_seconds
        self.requests = defaultdict(list)

    def is_allowed(self, client_ip: str) -> bool:
        now = time.time()
        self.requests[client_ip] = [t for t in self.requests[client_ip] if now - t < self.window_seconds]
        if len(self.requests[client_ip]) >= self.max_requests:
            return False
        self.requests[client_ip].append(now)
        return True


api_limiter = RateLimiter(max_requests=30, window_seconds=60)
auth_limiter = RateLimiter(max_requests=5, window_seconds=60)


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


def sanitize_domain(domain):
    if not domain or not DOMAIN_PATTERN.match(domain):
        raise ValueError(f'Invalid domain: {domain}')
    return domain.lower()


def sanitize_name(name):
    return re.sub(r'[^a-zA-Z0-9\-_\s]', '', name or '')[:64]


def sanitize_service(service):
    if service not in {'singbox', 'adguard', 'caddy'}:
        raise ValueError(f'Invalid service: {service}')
    return service


def get_hidden_path(token):
    return hashlib.sha256(f"{SALT}:{token}".encode()).hexdigest()[:16]


def load_json(filepath, default=None):
    try:
        if os.path.exists(filepath):
            with open(filepath, 'r') as f:
                return json.load(f)
    except Exception:
        pass
    return default if default is not None else {}


def save_json(filepath, data):
    os.makedirs(os.path.dirname(filepath), exist_ok=True)
    with open(filepath, 'w') as f:
        json.dump(data, f, indent=2)


def load_nodes():
    return load_json(NODES_FILE, {})


def save_nodes(nodes):
    save_json(NODES_FILE, nodes)


def load_settings():
    return load_json(SETTINGS_FILE, {'auto_update': False, 'last_update_check': None})


def save_settings(settings):
    save_json(SETTINGS_FILE, settings)


def get_node_api_url(node):
    protocol = 'https' if node.get('https', True) else 'http'
    return f"{protocol}://{node['domain']}/{get_hidden_path(CLUSTER_SECRET)}/api/v1"


def call_node_api(node, endpoint, method='GET', data=None, timeout=30):
    url = f"{get_node_api_url(node)}/{endpoint}"
    headers = {'X-SUI-Token': CLUSTER_SECRET}
    try:
        if method == 'GET':
            resp = requests.get(url, headers=headers, timeout=timeout)
        else:
            resp = requests.post(url, headers=headers, json=data, timeout=timeout)
        return resp.json() if resp.ok else {'error': resp.text}
    except Exception as e:
        return {'error': str(e)}


def check_for_updates():
    """Check GitHub for latest version"""
    try:
        resp = requests.get(f"{GITHUB_RAW}/master/app.py", timeout=10)
        if resp.ok:
            match = re.search(r'VERSION\s*=\s*["\']([^"\']+)["\']', resp.text)
            if match:
                return {'current': VERSION, 'latest': match.group(1), 'update_available': match.group(1) != VERSION}
    except Exception:
        pass
    return {'current': VERSION, 'latest': VERSION, 'update_available': False}


@app.route('/')
@rate_limit(api_limiter)
def index():
    settings = load_settings()
    return render_template('index.html', nodes=load_nodes(), settings=settings, version=VERSION)


@app.route('/api/nodes', methods=['GET'])
@rate_limit(api_limiter)
def list_nodes():
    return jsonify(load_nodes())


@app.route('/api/nodes', methods=['POST'])
@rate_limit(api_limiter)
def add_node():
    data = request.json or {}
    try:
        name = sanitize_name(data.get('name'))
        domain = sanitize_domain(data.get('domain'))
        if not name or not domain:
            return jsonify({'error': 'Missing name or domain'}), 400
    except ValueError as e:
        return jsonify({'error': str(e)}), 400
    
    nodes = load_nodes()
    node_id = hashlib.md5(domain.encode()).hexdigest()[:8]
    nodes[node_id] = {
        'name': name,
        'domain': domain,
        'https': data.get('https', True),
        'added_at': datetime.now().isoformat(),
        'status': 'unknown'
    }
    save_nodes(nodes)
    return jsonify({'id': node_id, 'node': nodes[node_id]})


@app.route('/api/nodes/<node_id>', methods=['DELETE'])
@rate_limit(api_limiter)
def delete_node(node_id):
    if not NODE_ID_PATTERN.match(node_id):
        return jsonify({'error': 'Invalid node ID'}), 400
    nodes = load_nodes()
    if node_id in nodes:
        del nodes[node_id]
        save_nodes(nodes)
        return jsonify({'success': True})
    return jsonify({'error': 'Node not found'}), 404


@app.route('/api/nodes/<node_id>/status')
@rate_limit(api_limiter)
def node_status(node_id):
    if not NODE_ID_PATTERN.match(node_id):
        return jsonify({'error': 'Invalid node ID'}), 400
    nodes = load_nodes()
    if node_id not in nodes:
        return jsonify({'error': 'Node not found'}), 404
    result = call_node_api(nodes[node_id], 'status')
    nodes[node_id]['status'] = 'online' if 'error' not in result else 'offline'
    nodes[node_id]['last_check'] = datetime.now().isoformat()
    save_nodes(nodes)
    return jsonify(result)


@app.route('/api/nodes/<node_id>/services')
@rate_limit(api_limiter)
def node_services(node_id):
    if not NODE_ID_PATTERN.match(node_id):
        return jsonify({'error': 'Invalid node ID'}), 400
    nodes = load_nodes()
    if node_id not in nodes:
        return jsonify({'error': 'Node not found'}), 404
    return jsonify(call_node_api(nodes[node_id], 'services'))


@app.route('/api/nodes/<node_id>/restart/<service>', methods=['POST'])
@rate_limit(auth_limiter)
def restart_service(node_id, service):
    if not NODE_ID_PATTERN.match(node_id):
        return jsonify({'error': 'Invalid node ID'}), 400
    try:
        service = sanitize_service(service)
    except ValueError as e:
        return jsonify({'error': str(e)}), 400
    nodes = load_nodes()
    if node_id not in nodes:
        return jsonify({'error': 'Node not found'}), 404
    return jsonify(call_node_api(nodes[node_id], f'restart/{service}', 'POST'))


@app.route('/api/nodes/<node_id>/config/<service>', methods=['GET', 'POST'])
@rate_limit(api_limiter)
def config(node_id, service):
    if not NODE_ID_PATTERN.match(node_id):
        return jsonify({'error': 'Invalid node ID'}), 400
    try:
        service = sanitize_service(service)
    except ValueError as e:
        return jsonify({'error': str(e)}), 400
    nodes = load_nodes()
    if node_id not in nodes:
        return jsonify({'error': 'Node not found'}), 404
    
    if request.method == 'POST':
        return jsonify(call_node_api(nodes[node_id], f'config/{service}', 'POST', request.json))
    return jsonify(call_node_api(nodes[node_id], f'config/{service}'))


@app.route('/api/nodes/<node_id>/logs/<service>')
@rate_limit(api_limiter)
def node_logs(node_id, service):
    if not NODE_ID_PATTERN.match(node_id):
        return jsonify({'error': 'Invalid node ID'}), 400
    try:
        service = sanitize_service(service)
    except ValueError as e:
        return jsonify({'error': str(e)}), 400
    nodes = load_nodes()
    if node_id not in nodes:
        return jsonify({'error': 'Node not found'}), 404
    lines = request.args.get('lines', '100')
    return jsonify(call_node_api(nodes[node_id], f'logs/{service}?lines={lines}'))


@app.route('/api/nodes/<node_id>/update', methods=['POST'])
@rate_limit(auth_limiter)
def update_node(node_id):
    """Trigger update on a specific node"""
    if not NODE_ID_PATTERN.match(node_id):
        return jsonify({'error': 'Invalid node ID'}), 400
    nodes = load_nodes()
    if node_id not in nodes:
        return jsonify({'error': 'Node not found'}), 404
    return jsonify(call_node_api(nodes[node_id], 'update', 'POST', timeout=120))


@app.route('/api/nodes/<node_id>/restart-all', methods=['POST'])
@rate_limit(auth_limiter)
def restart_node_all(node_id):
    """Restart all containers on a node"""
    if not NODE_ID_PATTERN.match(node_id):
        return jsonify({'error': 'Invalid node ID'}), 400
    nodes = load_nodes()
    if node_id not in nodes:
        return jsonify({'error': 'Node not found'}), 404
    return jsonify(call_node_api(nodes[node_id], 'restart-all', 'POST', timeout=60))


@app.route('/api/nodes/<node_id>/proxies')
@rate_limit(api_limiter)
def node_proxies(node_id):
    """Get all proxy configurations from a node"""
    if not NODE_ID_PATTERN.match(node_id):
        return jsonify({'error': 'Invalid node ID'}), 400
    nodes = load_nodes()
    if node_id not in nodes:
        return jsonify({'error': 'Node not found'}), 404
    return jsonify(call_node_api(nodes[node_id], 'proxies'))


@app.route('/api/nodes/<node_id>/firewall', methods=['GET'])
@rate_limit(api_limiter)
def get_node_firewall(node_id):
    """Get firewall status from a node"""
    if not NODE_ID_PATTERN.match(node_id):
        return jsonify({'error': 'Invalid node ID'}), 400
    nodes = load_nodes()
    if node_id not in nodes:
        return jsonify({'error': 'Node not found'}), 404
    return jsonify(call_node_api(nodes[node_id], 'firewall'))


@app.route('/api/nodes/<node_id>/firewall', methods=['POST'])
@rate_limit(auth_limiter)
def set_node_firewall(node_id):
    """Configure firewall on a node"""
    if not NODE_ID_PATTERN.match(node_id):
        return jsonify({'error': 'Invalid node ID'}), 400
    nodes = load_nodes()
    if node_id not in nodes:
        return jsonify({'error': 'Node not found'}), 404
    return jsonify(call_node_api(nodes[node_id], 'firewall', 'POST', request.json))


# Settings & Update APIs
@app.route('/api/settings', methods=['GET', 'POST'])
@rate_limit(api_limiter)
def settings():
    if request.method == 'GET':
        return jsonify(load_settings())
    
    data = request.json or {}
    current = load_settings()
    if 'auto_update' in data:
        current['auto_update'] = bool(data['auto_update'])
    save_settings(current)
    return jsonify(current)


@app.route('/api/update/check')
@rate_limit(api_limiter)
def update_check():
    """Check for available updates"""
    result = check_for_updates()
    settings = load_settings()
    settings['last_update_check'] = datetime.now().isoformat()
    save_settings(settings)
    return jsonify(result)


@app.route('/api/update/master', methods=['POST'])
@rate_limit(auth_limiter)
def update_master():
    """Update master to latest version and restart"""
    import shutil
    import threading
    import zipfile
    import io
    
    try:
        # Get the directory where app.py is located
        app_dir = os.path.dirname(os.path.abspath(__file__))
        templates_dir = os.path.join(app_dir, 'templates')
        
        # Download latest using requests (curl not available in container)
        resp = requests.get('https://github.com/pjonix/SUIS/archive/main.zip', timeout=30)
        if resp.status_code != 200:
            return jsonify({'success': False, 'error': f'Download failed: HTTP {resp.status_code}'})
        
        # Extract zip in memory
        with zipfile.ZipFile(io.BytesIO(resp.content)) as zf:
            # Extract to /tmp
            zf.extractall('/tmp/')
        
        # Backup and copy new files
        for f in ['app.py']:
            src = f'/tmp/SUIS-main/master/{f}'
            dst = os.path.join(app_dir, f)
            if os.path.exists(src):
                if os.path.exists(dst):
                    shutil.copy(dst, f'{dst}.bak')
                shutil.copy(src, dst)
        
        for f in ['index.html']:
            src = f'/tmp/SUIS-main/master/templates/{f}'
            dst = os.path.join(templates_dir, f)
            if os.path.exists(src):
                if os.path.exists(dst):
                    shutil.copy(dst, f'{dst}.bak')
                shutil.copy(src, dst)
        
        # Cleanup
        shutil.rmtree('/tmp/SUIS-main', ignore_errors=True)
        
        # Schedule restart in background (so response can be sent first)
        def delayed_restart():
            import time
            time.sleep(1)
            subprocess.run(['docker', 'restart', 'sui-master'], capture_output=True, timeout=30)
        
        threading.Thread(target=delayed_restart, daemon=True).start()
        
        return jsonify({'success': True, 'message': 'Update complete. Restarting in 1 second...'})
    except Exception as e:
        return jsonify({'success': False, 'error': str(e)})


@app.route('/api/update/all-nodes', methods=['POST'])
@rate_limit(auth_limiter)
def update_all_nodes():
    """Trigger update on all nodes"""
    nodes = load_nodes()
    results = {}
    for node_id, node in nodes.items():
        results[node_id] = call_node_api(node, 'update', 'POST', timeout=120)
    return jsonify(results)


@app.route('/api/master/restart', methods=['POST'])
@rate_limit(auth_limiter)
def restart_master():
    """Restart Master container"""
    try:
        result = subprocess.run(
            ['sh', '-c', 'cd /opt/sui-solo/master && docker compose restart'],
            capture_output=True, text=True, timeout=60
        )
        return jsonify({'success': result.returncode == 0, 'output': result.stdout + result.stderr})
    except Exception as e:
        return jsonify({'success': False, 'error': str(e)})


@app.route('/api/gateway/restart', methods=['POST'])
@rate_limit(auth_limiter)
def restart_gateway():
    """Restart Gateway container"""
    try:
        result = subprocess.run(
            ['sh', '-c', 'cd /opt/sui-solo/gateway && docker compose restart'],
            capture_output=True, text=True, timeout=60
        )
        return jsonify({'success': result.returncode == 0, 'output': result.stdout + result.stderr})
    except Exception as e:
        return jsonify({'success': False, 'error': str(e)})


# ============================================================================
# SUBSCRIPTION API - Enhanced with Preset Support
# ============================================================================
@app.route('/api/nodes/<node_id>/presets')
@rate_limit(api_limiter)
def node_presets(node_id):
    """Get preset configurations from a node"""
    if not NODE_ID_PATTERN.match(node_id):
        return jsonify({'error': 'Invalid node ID'}), 400
    nodes = load_nodes()
    if node_id not in nodes:
        return jsonify({'error': 'Node not found'}), 404
    return jsonify(call_node_api(nodes[node_id], 'presets'))


@app.route('/api/nodes/<node_id>/presets', methods=['POST'])
@rate_limit(api_limiter)
def update_node_presets(node_id):
    """Update preset configurations on a node"""
    if not NODE_ID_PATTERN.match(node_id):
        return jsonify({'error': 'Invalid node ID'}), 400
    nodes = load_nodes()
    if node_id not in nodes:
        return jsonify({'error': 'Node not found'}), 404
    return jsonify(call_node_api(nodes[node_id], 'presets', 'POST', request.json))


@app.route('/api/nodes/<node_id>/subscribe')
@rate_limit(api_limiter)
def node_subscribe(node_id):
    """Get subscription links from a specific node"""
    if not NODE_ID_PATTERN.match(node_id):
        return jsonify({'error': 'Invalid node ID'}), 400
    nodes = load_nodes()
    if node_id not in nodes:
        return jsonify({'error': 'Node not found'}), 404
    return jsonify(call_node_api(nodes[node_id], 'subscribe'))


@app.route('/api/subscribe')
@rate_limit(api_limiter)
def subscribe():
    """Generate aggregated subscription for all nodes with presets"""
    import base64
    nodes = load_nodes()
    format_type = request.args.get('format', 'base64')  # base64, clash, singbox
    
    all_links = []
    all_proxies = []
    
    for node_id, node in nodes.items():
        # Try to get preset-based subscription first
        result = call_node_api(node, 'subscribe')
        if 'links' in result:
            for link_info in result['links']:
                link_info['node_name'] = node['name']
                link_info['node_domain'] = node['domain']
                all_links.append(link_info)
    
    if format_type == 'base64':
        # Return base64 encoded links
        links_text = '\n'.join([l['link'] for l in all_links])
        from flask import Response
        return Response(base64.b64encode(links_text.encode()).decode(), mimetype='text/plain')
    
    elif format_type == 'clash':
        # Return Clash format
        proxies = []
        for link_info in all_links:
            proxy = {
                'name': f"{link_info['node_name']}-{link_info['type']}",
                'server': link_info['node_domain'],
                'port': link_info['port']
            }
            if 'vless' in link_info['type']:
                proxy['type'] = 'vless'
                # Parse UUID from link
                if link_info['link'].startswith('vless://'):
                    proxy['uuid'] = link_info['link'].split('://')[1].split('@')[0]
                proxy['tls'] = True
                if 'vision' in link_info['type']:
                    proxy['flow'] = 'xtls-rprx-vision'
            elif 'vmess' in link_info['type']:
                proxy['type'] = 'vmess'
                # Decode vmess link
                try:
                    vmess_data = json.loads(base64.b64decode(link_info['link'].replace('vmess://', '')))
                    proxy['uuid'] = vmess_data.get('id', '')
                    proxy['alterId'] = int(vmess_data.get('aid', 0))
                    proxy['network'] = vmess_data.get('net', 'tcp')
                    if proxy['network'] == 'ws':
                        proxy['ws-opts'] = {'path': vmess_data.get('path', '/')}
                    proxy['tls'] = vmess_data.get('tls') == 'tls'
                except:
                    continue
            elif 'hysteria2' in link_info['type']:
                proxy['type'] = 'hysteria2'
                # Parse password from link
                if link_info['link'].startswith('hysteria2://'):
                    proxy['password'] = link_info['link'].split('://')[1].split('@')[0]
                proxy['sni'] = link_info['node_domain']
            proxies.append(proxy)
        
        clash_config = {
            'proxies': proxies,
            'proxy-groups': [{
                'name': 'auto',
                'type': 'url-test',
                'proxies': [p['name'] for p in proxies],
                'url': 'http://www.gstatic.com/generate_204',
                'interval': 300
            }]
        }
        return jsonify(clash_config)
    
    elif format_type == 'singbox':
        # Return sing-box outbound format
        outbounds = []
        for link_info in all_links:
            tag = f"{link_info['node_name']}-{link_info['type']}"
            outbound = {'tag': tag, 'server': link_info['node_domain'], 'server_port': link_info['port']}
            
            if 'vless' in link_info['type']:
                outbound['type'] = 'vless'
                if link_info['link'].startswith('vless://'):
                    outbound['uuid'] = link_info['link'].split('://')[1].split('@')[0]
                if 'vision' in link_info['type']:
                    outbound['flow'] = 'xtls-rprx-vision'
                    outbound['tls'] = {
                        'enabled': True,
                        'server_name': 'www.microsoft.com',
                        'reality': {'enabled': True, 'public_key': '', 'short_id': ''}
                    }
                    # Parse reality params from link
                    if 'pbk=' in link_info['link']:
                        outbound['tls']['reality']['public_key'] = link_info['link'].split('pbk=')[1].split('&')[0]
                    if 'sid=' in link_info['link']:
                        outbound['tls']['reality']['short_id'] = link_info['link'].split('sid=')[1].split('&')[0]
            elif 'vmess' in link_info['type']:
                outbound['type'] = 'vmess'
                try:
                    vmess_data = json.loads(base64.b64decode(link_info['link'].replace('vmess://', '')))
                    outbound['uuid'] = vmess_data.get('id', '')
                    if vmess_data.get('net') == 'ws':
                        outbound['transport'] = {'type': 'ws', 'path': vmess_data.get('path', '/')}
                    if vmess_data.get('tls') == 'tls':
                        outbound['tls'] = {'enabled': True, 'server_name': link_info['node_domain']}
                except:
                    continue
            elif 'hysteria2' in link_info['type']:
                outbound['type'] = 'hysteria2'
                if link_info['link'].startswith('hysteria2://'):
                    outbound['password'] = link_info['link'].split('://')[1].split('@')[0]
                outbound['tls'] = {'enabled': True, 'server_name': link_info['node_domain']}
            
            outbounds.append(outbound)
        
        singbox_config = {
            'log': {'level': 'info'},
            'outbounds': outbounds + [{'type': 'direct', 'tag': 'direct'}],
            'route': {'final': outbounds[0]['tag'] if outbounds else 'direct'}
        }
        return jsonify(singbox_config)
    
    # Default: return raw links
    return jsonify({'links': all_links})


@app.route('/api/subscribe/url')
@rate_limit(api_limiter)
def subscribe_url():
    """Get subscription URL info"""
    master_domain = os.environ.get('MASTER_DOMAIN', '')
    # Try to get domain from request if not set in env
    if not master_domain:
        master_domain = request.host.split(':')[0]
    hidden_path = get_hidden_path(CLUSTER_SECRET)
    return jsonify({
        'base64': f"https://{master_domain}/{hidden_path}/sub",
        'clash': f"https://{master_domain}/{hidden_path}/sub?format=clash",
        'singbox': f"https://{master_domain}/{hidden_path}/sub?format=singbox",
        'public_base64': f"https://{master_domain}/api/subscribe",
        'public_clash': f"https://{master_domain}/api/subscribe?format=clash",
        'public_singbox': f"https://{master_domain}/api/subscribe?format=singbox"
    })


# Hidden subscription endpoint (more secure)
@app.route(f'/<path:hidden>/sub')
@rate_limit(api_limiter)
def hidden_subscribe(hidden):
    """Hidden subscription endpoint"""
    if hidden != get_hidden_path(CLUSTER_SECRET):
        return jsonify({'error': 'Not found'}), 404
    return subscribe()


@app.route('/health')
def health():
    return jsonify({'status': 'healthy', 'version': VERSION})


if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000)
