#!/usr/bin/env python3
"""NexusProxy Node Agent - Local Control API"""

import os
import hashlib
import subprocess
import json
from functools import wraps
from flask import Flask, request, jsonify

app = Flask(__name__)

# Configuration
CLUSTER_SECRET = os.environ.get('CLUSTER_SECRET', '')
NODE_DOMAIN = os.environ.get('NODE_DOMAIN', '')
CONFIG_DIR = os.environ.get('CONFIG_DIR', '/config')

# Compute hidden API path
def compute_api_path(secret: str, domain: str) -> str:
    combined = f"{secret}:{domain}"
    return hashlib.sha256(combined.encode()).hexdigest()[:8]

API_PATH = compute_api_path(CLUSTER_SECRET, NODE_DOMAIN)


def require_auth(f):
    """Decorator to require X-Nexus-Token authentication"""
    @wraps(f)
    def decorated(*args, **kwargs):
        token = request.headers.get('X-Nexus-Token', '')
        if token != CLUSTER_SECRET:
            return jsonify({'error': 'Unauthorized'}), 401
        return f(*args, **kwargs)
    return decorated


def run_cmd(cmd: list) -> tuple:
    """Run shell command and return (success, output)"""
    try:
        result = subprocess.run(cmd, capture_output=True, text=True, timeout=30)
        return result.returncode == 0, result.stdout + result.stderr
    except Exception as e:
        return False, str(e)


def get_container_status(name: str) -> str:
    """Get Docker container status"""
    success, output = run_cmd(['docker', 'inspect', '-f', '{{.State.Status}}', name])
    return output.strip() if success else 'not found'


@app.route(f'/api/{API_PATH}/status', methods=['GET'])
@require_auth
def status():
    """Get node status"""
    success, uptime = run_cmd(['uptime', '-p'])
    return jsonify({
        'status': 'online',
        'domain': NODE_DOMAIN,
        'uptime': uptime.strip() if success else 'unknown',
        'api_path': API_PATH
    })


@app.route(f'/api/{API_PATH}/services', methods=['GET'])
@require_auth
def services():
    """Get all services status"""
    return jsonify({
        'services': {
            'singbox': get_container_status('nexus-singbox'),
            'adguard': get_container_status('nexus-adguard'),
            'caddy': get_container_status('nexus-caddy'),
            'agent': 'running'
        }
    })


@app.route(f'/api/{API_PATH}/restart/<service>', methods=['POST'])
@require_auth
def restart_service(service):
    """Restart a specific service"""
    container_map = {
        'singbox': 'nexus-singbox',
        'adguard': 'nexus-adguard',
        'caddy': 'nexus-caddy'
    }
    
    if service not in container_map:
        return jsonify({'error': f'Unknown service: {service}'}), 400
    
    container = container_map[service]
    success, output = run_cmd(['docker', 'restart', container])
    
    return jsonify({
        'success': success,
        'service': service,
        'message': output.strip()
    })


@app.route(f'/api/{API_PATH}/config/<service>', methods=['GET'])
@require_auth
def get_config(service):
    """Get service configuration"""
    config_files = {
        'singbox': os.path.join(CONFIG_DIR, 'singbox', 'config.json'),
        'adguard': os.path.join(CONFIG_DIR, 'adguard', 'AdGuardHome.yaml'),
        'caddy': os.path.join(CONFIG_DIR, 'caddy', 'Caddyfile')
    }
    
    if service not in config_files:
        return jsonify({'error': f'Unknown service: {service}'}), 400
    
    config_path = config_files[service]
    if not os.path.exists(config_path):
        return jsonify({'error': 'Config file not found'}), 404
    
    with open(config_path, 'r') as f:
        content = f.read()
    
    return jsonify({
        'service': service,
        'path': config_path,
        'content': content
    })


@app.route(f'/api/{API_PATH}/config/<service>', methods=['POST'])
@require_auth
def update_config(service):
    """Update service configuration"""
    config_files = {
        'singbox': os.path.join(CONFIG_DIR, 'singbox', 'config.json'),
        'adguard': os.path.join(CONFIG_DIR, 'adguard', 'AdGuardHome.yaml'),
        'caddy': os.path.join(CONFIG_DIR, 'caddy', 'Caddyfile')
    }
    
    if service not in config_files:
        return jsonify({'error': f'Unknown service: {service}'}), 400
    
    data = request.json
    if not data or 'content' not in data:
        return jsonify({'error': 'Missing content'}), 400
    
    config_path = config_files[service]
    os.makedirs(os.path.dirname(config_path), exist_ok=True)
    
    with open(config_path, 'w') as f:
        f.write(data['content'])
    
    return jsonify({
        'success': True,
        'service': service,
        'message': 'Configuration updated'
    })


@app.route(f'/api/{API_PATH}/logs/<service>', methods=['GET'])
@require_auth
def get_logs(service):
    """Get service logs"""
    container_map = {
        'singbox': 'nexus-singbox',
        'adguard': 'nexus-adguard',
        'caddy': 'nexus-caddy'
    }
    
    if service not in container_map:
        return jsonify({'error': f'Unknown service: {service}'}), 400
    
    lines = request.args.get('lines', '100')
    success, output = run_cmd(['docker', 'logs', '--tail', lines, container_map[service]])
    
    return jsonify({
        'service': service,
        'logs': output
    })


# Health check endpoint (no auth required)
@app.route('/health', methods=['GET'])
def health():
    return jsonify({'status': 'healthy'})


if __name__ == '__main__':
    print(f"[NexusProxy Agent] Starting on domain: {NODE_DOMAIN}")
    print(f"[NexusProxy Agent] API Path: /api/{API_PATH}/")
    app.run(host='0.0.0.0', port=5001, debug=os.environ.get('DEBUG', False))
