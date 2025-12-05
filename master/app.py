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
SALT = "SUI_Solo_Secured_2024"
VERSION = "1.5.0"
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
    """Update master to latest version"""
    try:
        # Download latest files
        result = subprocess.run(
            ['sh', '-c', '''
                cd /opt/sui-solo/master
                curl -fsSL https://github.com/pjonix/SUIS/archive/main.zip -o /tmp/update.zip
                unzip -o /tmp/update.zip -d /tmp/
                cp /tmp/SUIS-main/master/app.py ./app.py.new
                cp /tmp/SUIS-main/master/templates/index.html ./templates/index.html.new
                mv ./app.py.new ./app.py
                mv ./templates/index.html.new ./templates/index.html
                rm -rf /tmp/update.zip /tmp/SUIS-main
            '''],
            capture_output=True, text=True, timeout=60
        )
        if result.returncode == 0:
            return jsonify({'success': True, 'message': 'Update downloaded. Restart container to apply.'})
        return jsonify({'success': False, 'error': result.stderr})
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


@app.route('/health')
def health():
    return jsonify({'status': 'healthy', 'version': VERSION})


if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000)
