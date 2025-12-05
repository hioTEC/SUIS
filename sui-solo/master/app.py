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

# Configuration
DATA_DIR = os.environ.get('DATA_DIR', '/data')
CLUSTER_SECRET = os.environ.get('CLUSTER_SECRET', '')
NODES_FILE = os.path.join(DATA_DIR, 'nodes.json')

# Security: Hardcoded salt for path generation
SALT = "SUI_Solo_Secured_2024"

#=============================================================================
# RATE LIMITING - Prevent brute force attacks
#=============================================================================
class RateLimiter:
    """Simple in-memory rate limiter"""
    def __init__(self, max_requests: int = 10, window_seconds: int = 60):
        self.max_requests = max_requests
        self.window_seconds = window_seconds
        self.requests = defaultdict(list)
    
    def is_allowed(self, client_ip: str) -> bool:
        """Check if request is allowed for this IP"""
        now = time.time()
        # Clean old entries
        self.requests[client_ip] = [
            t for t in self.requests[client_ip] 
            if now - t < self.window_seconds
        ]
        # Check limit
        if len(self.requests[client_ip]) >= self.max_requests:
            return False
        self.requests[client_ip].append(now)
        return True
    
    def get_remaining(self, client_ip: str) -> int:
        """Get remaining requests for this IP"""
        now = time.time()
        recent = [t for t in self.requests[client_ip] if now - t < self.window_seconds]
        return max(0, self.max_requests - len(recent))


# Rate limiters for different endpoints
api_limiter = RateLimiter(max_requests=30, window_seconds=60)  # General API
auth_limiter = RateLimiter(max_requests=5, window_seconds=60)   # Auth-sensitive


def get_client_ip():
    """Get real client IP (handles reverse proxy)"""
    # Check X-Forwarded-For header (set by Caddy)
    forwarded = request.headers.get('X-Forwarded-For', '')
    if forwarded:
        return forwarded.split(',')[0].strip()
    return request.remote_addr or '127.0.0.1'


def rate_limit(limiter: RateLimiter):
    """Decorator for rate limiting"""
    def decorator(f):
        @wraps(f)
        def decorated(*args, **kwargs):
            client_ip = get_client_ip()
            if not limiter.is_allowed(client_ip):
                return jsonify({
                    'error': 'Rate limit exceeded',
                    'retry_after': limiter.window_seconds
                }), 429
            return f(*args, **kwargs)
        return decorated
    return decorator


#=============================================================================
# INPUT SANITIZATION - Prevent injection attacks
#=============================================================================
def sanitize_domain(domain: str) -> str:
    """Sanitize domain input to prevent injection"""
    if not domain:
        return ''
    # Only allow valid domain characters
    pattern = r'^[a-zA-Z0-9]([a-zA-Z0-9\-\.]{0,253}[a-zA-Z0-9])?$'
    if not re.match(pattern, domain):
        raise ValueError(f'Invalid domain format: {domain}')
    # Additional checks
    if '..' in domain or domain.startswith('-') or domain.endswith('-'):
        raise ValueError(f'Invalid domain format: {domain}')
    return domain.lower()


def sanitize_name(name: str) -> str:
    """Sanitize node name input"""
    if not name:
        return ''
    # Only allow alphanumeric, dash, underscore, space
    sanitized = re.sub(r'[^a-zA-Z0-9\-_\s]', '', name)
    return sanitized[:64]  # Limit length


def sanitize_service(service: str) -> str:
    """Sanitize service name - whitelist approach"""
    allowed = {'singbox', 'adguard', 'caddy'}
    if service not in allowed:
        raise ValueError(f'Invalid service: {service}')
    return service


#=============================================================================
# CORE FUNCTIONS
#=============================================================================
def get_hidden_path(token: str) -> str:
    """Generate deterministic hidden API path from token."""
    combined = f"{SALT}:{token}"
    return hashlib.sha256(combined.encode()).hexdigest()[:16]


def load_nodes():
    """Load nodes from persistent storage"""
    if os.path.exists(NODES_FILE):
        with open(NODES_FILE, 'r') as f:
            return json.load(f)
    return {}


def save_nodes(nodes):
    """Save nodes to persistent storage"""
    os.makedirs(DATA_DIR, exist_ok=True)
    with open(NODES_FILE, 'w') as f:
        json.dump(nodes, f, indent=2)


def get_node_api_url(node: dict) -> str:
    """Get full API URL for a node"""
    path_prefix = get_hidden_path(CLUSTER_SECRET)
    protocol = 'https' if node.get('https', True) else 'http'
    return f"{protocol}://{node['domain']}/{path_prefix}/api/v1"


def call_node_api(node: dict, endpoint: str, method: str = 'GET', data: dict = None):
    """Call node API with authentication"""
    base_url = get_node_api_url(node)
    url = f"{base_url}/{endpoint}"
    headers = {'X-SUI-Token': CLUSTER_SECRET}
    
    try:
        if method == 'GET':
            resp = requests.get(url, headers=headers, timeout=10, verify=True)
        elif method == 'POST':
            resp = requests.post(url, headers=headers, json=data, timeout=30, verify=True)
        return resp.json() if resp.ok else {'error': resp.text}
    except Exception as e:
        return {'error': str(e)}


#=============================================================================
# ROUTES
#=============================================================================
@app.route('/')
@rate_limit(api_limiter)
def index():
    """Dashboard home page"""
    nodes = load_nodes()
    return render_template('index.html', nodes=nodes, secret=CLUSTER_SECRET)


@app.route('/api/nodes', methods=['GET'])
@rate_limit(api_limiter)
def list_nodes():
    return jsonify(load_nodes())


@app.route('/api/nodes', methods=['POST'])
@rate_limit(api_limiter)
def add_node():
    data = request.json
    if not data:
        return jsonify({'error': 'Missing request body'}), 400
    
    try:
        name = sanitize_name(data.get('name', ''))
        domain = sanitize_domain(data.get('domain', ''))
        
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
    # Sanitize node_id (should be hex string)
    if not re.match(r'^[a-f0-9]{8}$', node_id):
        return jsonify({'error': 'Invalid node ID'}), 400
    
    nodes = load_nodes()
    if node_id in nodes:
        del nodes[node_id]
        save_nodes(nodes)
        return jsonify({'success': True})
    return jsonify({'error': 'Node not found'}), 404


@app.route('/api/nodes/<node_id>/status', methods=['GET'])
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


@app.route('/api/nodes/<node_id>/services', methods=['GET'])
@rate_limit(api_limiter)
def node_services(node_id):
    if not re.match(r'^[a-f0-9]{8}$', node_id):
        return jsonify({'error': 'Invalid node ID'}), 400
    
    nodes = load_nodes()
    if node_id not in nodes:
        return jsonify({'error': 'Node not found'}), 404
    return jsonify(call_node_api(nodes[node_id], 'services'))


@app.route('/api/nodes/<node_id>/restart/<service>', methods=['POST'])
@rate_limit(auth_limiter)  # Stricter rate limit for sensitive operations
def restart_service(node_id, service):
    if not re.match(r'^[a-f0-9]{8}$', node_id):
        return jsonify({'error': 'Invalid node ID'}), 400
    
    try:
        service = sanitize_service(service)
    except ValueError as e:
        return jsonify({'error': str(e)}), 400
    
    nodes = load_nodes()
    if node_id not in nodes:
        return jsonify({'error': 'Node not found'}), 404
    return jsonify(call_node_api(nodes[node_id], f'restart/{service}', method='POST'))


@app.route('/api/nodes/<node_id>/config/<service>', methods=['GET'])
@rate_limit(api_limiter)
def get_config(node_id, service):
    if not re.match(r'^[a-f0-9]{8}$', node_id):
        return jsonify({'error': 'Invalid node ID'}), 400
    
    try:
        service = sanitize_service(service)
    except ValueError as e:
        return jsonify({'error': str(e)}), 400
    
    nodes = load_nodes()
    if node_id not in nodes:
        return jsonify({'error': 'Node not found'}), 404
    return jsonify(call_node_api(nodes[node_id], f'config/{service}'))


@app.route('/api/nodes/<node_id>/config/<service>', methods=['POST'])
@rate_limit(auth_limiter)
def update_config(node_id, service):
    if not re.match(r'^[a-f0-9]{8}$', node_id):
        return jsonify({'error': 'Invalid node ID'}), 400
    
    try:
        service = sanitize_service(service)
    except ValueError as e:
        return jsonify({'error': str(e)}), 400
    
    nodes = load_nodes()
    if node_id not in nodes:
        return jsonify({'error': 'Node not found'}), 404
    return jsonify(call_node_api(nodes[node_id], f'config/{service}', method='POST', data=request.json))


@app.route('/api/secret')
@rate_limit(auth_limiter)
def get_secret():
    return jsonify({'secret': CLUSTER_SECRET})


@app.route('/api/compute-path', methods=['POST'])
@rate_limit(api_limiter)
def compute_path():
    path_prefix = get_hidden_path(CLUSTER_SECRET)
    return jsonify({'path_prefix': path_prefix, 'full_path': f'/{path_prefix}/api/v1'})


# Health check (no rate limit)
@app.route('/health')
def health():
    return jsonify({'status': 'healthy'})


if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000, debug=os.environ.get('DEBUG', False))
