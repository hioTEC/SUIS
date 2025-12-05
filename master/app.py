#!/usr/bin/env python3
"""SUI Solo Master Controller - Flask Backend with Security Hardening"""

import os
import re
import hashlib
import json
import time
from datetime import datetime
from collections import defaultdict
from functools import wraps
from flask import Flask, render_template, request, jsonify
import requests

app = Flask(__name__)

DATA_DIR = os.environ.get('DATA_DIR', '/data')
CLUSTER_SECRET = os.environ.get('CLUSTER_SECRET', '')
NODES_FILE = os.path.join(DATA_DIR, 'nodes.json')
SALT = "SUI_Solo_Secured_2024"


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
    if not domain or not re.match(r'^[a-zA-Z0-9]([a-zA-Z0-9\-\.]{0,253}[a-zA-Z0-9])?$', domain):
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


def load_nodes():
    return json.load(open(NODES_FILE)) if os.path.exists(NODES_FILE) else {}


def save_nodes(nodes):
    os.makedirs(DATA_DIR, exist_ok=True)
    json.dump(nodes, open(NODES_FILE, 'w'), indent=2)


def get_node_api_url(node):
    protocol = 'https' if node.get('https', True) else 'http'
    return f"{protocol}://{node['domain']}/{get_hidden_path(CLUSTER_SECRET)}/api/v1"


def call_node_api(node, endpoint, method='GET', data=None):
    url = f"{get_node_api_url(node)}/{endpoint}"
    headers = {'X-SUI-Token': CLUSTER_SECRET}
    try:
        resp = requests.get(url, headers=headers, timeout=10) if method == 'GET' else requests.post(url, headers=headers, json=data, timeout=30)
        return resp.json() if resp.ok else {'error': resp.text}
    except Exception as e:
        return {'error': str(e)}


@app.route('/')
@rate_limit(api_limiter)
def index():
    return render_template('index.html', nodes=load_nodes(), secret=CLUSTER_SECRET)


@app.route('/api/nodes', methods=['GET'])
@rate_limit(api_limiter)
def list_nodes():
    return jsonify(load_nodes())


@app.route('/api/nodes', methods=['POST'])
@rate_limit(api_limiter)
def add_node():
    data = request.json or {}
    try:
        name, domain = sanitize_name(data.get('name')), sanitize_domain(data.get('domain'))
        if not name or not domain:
            return jsonify({'error': 'Missing name or domain'}), 400
    except ValueError as e:
        return jsonify({'error': str(e)}), 400
    nodes = load_nodes()
    node_id = hashlib.md5(domain.encode()).hexdigest()[:8]
    nodes[node_id] = {'name': name, 'domain': domain, 'https': data.get('https', True), 'added_at': datetime.now().isoformat(), 'status': 'unknown'}
    save_nodes(nodes)
    return jsonify({'id': node_id, 'node': nodes[node_id]})


@app.route('/api/nodes/<node_id>', methods=['DELETE'])
@rate_limit(api_limiter)
def delete_node(node_id):
    if not re.match(r'^[a-f0-9]{8}$', node_id):
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
    if not re.match(r'^[a-f0-9]{8}$', node_id):
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
    if not re.match(r'^[a-f0-9]{8}$', node_id):
        return jsonify({'error': 'Invalid node ID'}), 400
    nodes = load_nodes()
    return jsonify({'error': 'Node not found'}) if node_id not in nodes else jsonify(call_node_api(nodes[node_id], 'services'))


@app.route('/api/nodes/<node_id>/restart/<service>', methods=['POST'])
@rate_limit(auth_limiter)
def restart_service(node_id, service):
    if not re.match(r'^[a-f0-9]{8}$', node_id):
        return jsonify({'error': 'Invalid node ID'}), 400
    try:
        service = sanitize_service(service)
    except ValueError as e:
        return jsonify({'error': str(e)}), 400
    nodes = load_nodes()
    return jsonify({'error': 'Node not found'}) if node_id not in nodes else jsonify(call_node_api(nodes[node_id], f'restart/{service}', 'POST'))


@app.route('/api/nodes/<node_id>/config/<service>', methods=['GET', 'POST'])
@rate_limit(auth_limiter if request.method == 'POST' else api_limiter)
def config(node_id, service):
    if not re.match(r'^[a-f0-9]{8}$', node_id):
        return jsonify({'error': 'Invalid node ID'}), 400
    try:
        service = sanitize_service(service)
    except ValueError as e:
        return jsonify({'error': str(e)}), 400
    nodes = load_nodes()
    if node_id not in nodes:
        return jsonify({'error': 'Node not found'}), 404
    return jsonify(call_node_api(nodes[node_id], f'config/{service}', request.method, request.json if request.method == 'POST' else None))


@app.route('/api/secret')
@rate_limit(auth_limiter)
def get_secret():
    return jsonify({'secret': CLUSTER_SECRET})


@app.route('/health')
def health():
    return jsonify({'status': 'healthy'})


if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000)
