#!/usr/bin/env python3
"""NexusProxy Master Controller - Flask Backend"""

import os
import hashlib
import secrets
import json
from datetime import datetime
from flask import Flask, render_template, request, jsonify, redirect, url_for
import requests

app = Flask(__name__)

# Configuration
DATA_DIR = os.environ.get('DATA_DIR', '/data')
CLUSTER_SECRET = os.environ.get('CLUSTER_SECRET', '')
NODES_FILE = os.path.join(DATA_DIR, 'nodes.json')

# Security: Hardcoded salt for path generation
SALT = "NexusProxy_Secured_2024"


def get_hidden_path(token: str) -> str:
    """
    Generate deterministic hidden API path from token.
    
    Security Design:
    - Salt prevents rainbow table attacks
    - SHA256 ensures uniform distribution
    - 16-char prefix provides 64-bit entropy (sufficient for URL obscurity)
    - Same token always produces same path (deterministic)
    
    Args:
        token: The cluster secret token
        
    Returns:
        Hidden path prefix (16 hex characters)
    """
    combined = f"{SALT}:{token}"
    hash_val = hashlib.sha256(combined.encode()).hexdigest()
    return hash_val[:16]


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
    headers = {'X-Nexus-Token': CLUSTER_SECRET}
    
    try:
        if method == 'GET':
            resp = requests.get(url, headers=headers, timeout=10)
        elif method == 'POST':
            resp = requests.post(url, headers=headers, json=data, timeout=30)
        return resp.json() if resp.ok else {'error': resp.text}
    except Exception as e:
        return {'error': str(e)}


@app.route('/')
def index():
    """Dashboard home page"""
    nodes = load_nodes()
    return render_template('index.html', nodes=nodes, secret=CLUSTER_SECRET)


@app.route('/api/nodes', methods=['GET'])
def list_nodes():
    """List all registered nodes"""
    return jsonify(load_nodes())


@app.route('/api/nodes', methods=['POST'])
def add_node():
    """Add a new node"""
    data = request.json
    if not data or 'name' not in data or 'domain' not in data:
        return jsonify({'error': 'Missing name or domain'}), 400
    
    nodes = load_nodes()
    node_id = hashlib.md5(data['domain'].encode()).hexdigest()[:8]
    
    nodes[node_id] = {
        'name': data['name'],
        'domain': data['domain'],
        'https': data.get('https', True),
        'added_at': datetime.now().isoformat(),
        'status': 'unknown'
    }
    save_nodes(nodes)
    return jsonify({'id': node_id, 'node': nodes[node_id]})


@app.route('/api/nodes/<node_id>', methods=['DELETE'])
def delete_node(node_id):
    """Delete a node"""
    nodes = load_nodes()
    if node_id in nodes:
        del nodes[node_id]
        save_nodes(nodes)
        return jsonify({'success': True})
    return jsonify({'error': 'Node not found'}), 404


@app.route('/api/nodes/<node_id>/status', methods=['GET'])
def node_status(node_id):
    """Get node status"""
    nodes = load_nodes()
    if node_id not in nodes:
        return jsonify({'error': 'Node not found'}), 404
    
    result = call_node_api(nodes[node_id], 'status')
    
    # Update cached status
    nodes[node_id]['status'] = 'online' if 'error' not in result else 'offline'
    nodes[node_id]['last_check'] = datetime.now().isoformat()
    save_nodes(nodes)
    
    return jsonify(result)


@app.route('/api/nodes/<node_id>/services', methods=['GET'])
def node_services(node_id):
    """Get node services status"""
    nodes = load_nodes()
    if node_id not in nodes:
        return jsonify({'error': 'Node not found'}), 404
    return jsonify(call_node_api(nodes[node_id], 'services'))


@app.route('/api/nodes/<node_id>/restart/<service>', methods=['POST'])
def restart_service(node_id, service):
    """Restart a service on node"""
    nodes = load_nodes()
    if node_id not in nodes:
        return jsonify({'error': 'Node not found'}), 404
    return jsonify(call_node_api(nodes[node_id], f'restart/{service}', method='POST'))


@app.route('/api/nodes/<node_id>/config/<service>', methods=['GET'])
def get_config(node_id, service):
    """Get service configuration"""
    nodes = load_nodes()
    if node_id not in nodes:
        return jsonify({'error': 'Node not found'}), 404
    return jsonify(call_node_api(nodes[node_id], f'config/{service}'))


@app.route('/api/nodes/<node_id>/config/<service>', methods=['POST'])
def update_config(node_id, service):
    """Update service configuration"""
    nodes = load_nodes()
    if node_id not in nodes:
        return jsonify({'error': 'Node not found'}), 404
    return jsonify(call_node_api(nodes[node_id], f'config/{service}', method='POST', data=request.json))


@app.route('/api/secret')
def get_secret():
    """Get cluster secret for display"""
    return jsonify({'secret': CLUSTER_SECRET})


@app.route('/api/compute-path', methods=['POST'])
def compute_path():
    """Compute hidden API path"""
    path_prefix = get_hidden_path(CLUSTER_SECRET)
    return jsonify({
        'path_prefix': path_prefix,
        'full_path': f'/{path_prefix}/api/v1'
    })


if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000, debug=os.environ.get('DEBUG', False))
