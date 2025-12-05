#!/usr/bin/env python3
"""SUI Solo Node Agent - Security Hardened"""

import os
import re
import hashlib
import time
from collections import defaultdict
from functools import wraps
from flask import Flask, request, jsonify

app = Flask(__name__)

# Configuration
CLUSTER_SECRET = os.environ.get('CLUSTER_SECRET', '')
NODE_DOMAIN = os.environ.get('NODE_DOMAIN', '')
CONFIG_DIR = os.environ.get('CONFIG_DIR', '/config')

# Security: Hardcoded salt (must match master)
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
        self.blocked_until = defaultdict(float)  # IP -> unblock timestamp
    
    def is_allowed(self, client_ip: str) -> bool:
        """Check if request is allowed for this IP"""
        now = time.time()
        
        # Check if IP is temporarily blocked
        if now < self.blocked_until[client_ip]:
            return False
        
        # Clean old entries
        self.requests[client_ip] = [
            t for t in self.requests[client_ip] 
            if now - t < self.window_seconds
        ]
        
        # Check limit
        if len(self.requests[client_ip]) >= self.max_requests:
            # Block for extended period after hitting limit
            self.blocked_until[client_ip] = now + (self.window_seconds * 2)
            return False
        
        self.requests[client_ip].append(now)
        return True


# Strict rate limiter for auth endpoints
auth_limiter = RateLimiter(max_requests=5, window_seconds=60)
api_limiter = RateLimiter(max_requests=20, window_seconds=60)


def get_client_ip():
    """Get real client IP (handles reverse proxy)"""
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
                    'error': 'Rate limit exceeded. Too many requests.',
                    'retry_after': limiter.window_seconds
                }), 429
            return f(*args, **kwargs)
        return decorated
    return decorator


#=============================================================================
# INPUT SANITIZATION
#=============================================================================
def sanitize_service(service: str) -> str:
    """Whitelist-based service validation"""
    allowed = {'singbox', 'adguard', 'caddy'}
    if service not in allowed:
        raise ValueError(f'Invalid service: {service}')
    return service


def sanitize_lines(lines: str) -> str:
    """Sanitize log lines parameter"""
    try:
        num = int(lines)
        if num < 1 or num > 1000:
            return '100'
        return str(num)
    except (ValueError, TypeError):
        return '100'


#=============================================================================
# SECURE COMMAND EXECUTION
#=============================================================================
# Instead of mounting docker.sock, we use a restricted command proxy
# This file will be executed by a separate privileged sidecar container

COMMAND_SOCKET = '/run/sui-cmd/cmd.sock'
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
    'uptime': ['uptime', '-p'],
}


def execute_allowed_command(cmd_key: str, **kwargs) -> tuple:
    """
    Execute only pre-defined allowed commands.
    This prevents command injection by using a whitelist approach.
    """
    import subprocess
    
    if cmd_key not in ALLOWED_COMMANDS:
        return False, f'Command not allowed: {cmd_key}'
    
    cmd = ALLOWED_COMMANDS[cmd_key].copy()
    
    # Substitute parameters safely
    for i, part in enumerate(cmd):
        if '{lines}' in part:
            cmd[i] = part.format(lines=sanitize_lines(kwargs.get('lines', '100')))
    
    try:
        result = subprocess.run(cmd, capture_output=True, text=True, timeout=30)
        return result.returncode == 0, result.stdout + result.stderr
    except subprocess.TimeoutExpired:
        return False, 'Command timed out'
    except Exception as e:
        return False, str(e)


def get_container_status(service: str) -> str:
    """Get Docker container status using allowed command"""
    success, output = execute_allowed_command(f'status_{service}')
    return output.strip() if success else 'not found'


#=============================================================================
# AUTHENTICATION
#=============================================================================
def get_hidden_path(token: str) -> str:
    """Generate deterministic hidden API path from token."""
    combined = f"{SALT}:{token}"
    return hashlib.sha256(combined.encode()).hexdigest()[:16]


PATH_PREFIX = get_hidden_path(CLUSTER_SECRET)


def require_auth(f):
    """Decorator to require X-SUI-Token authentication with rate limiting"""
    @wraps(f)
    def decorated(*args, **kwargs):
        client_ip = get_client_ip()
        
        # Rate limit auth attempts
        if not auth_limiter.is_allowed(client_ip):
            return jsonify({
                'error': 'Too many authentication attempts. IP temporarily blocked.',
                'retry_after': auth_limiter.window_seconds * 2
            }), 429
        
        token = request.headers.get('X-SUI-Token', '')
        
        # Constant-time comparison to prevent timing attacks
        if not _secure_compare(token, CLUSTER_SECRET):
            # Log failed attempt (in production, send to monitoring)
            app.logger.warning(f'Auth failed from IP: {client_ip}')
            return jsonify({'error': 'Unauthorized'}), 401
        
        return f(*args, **kwargs)
    return decorated


def _secure_compare(a: str, b: str) -> bool:
    """Constant-time string comparison to prevent timing attacks"""
    if len(a) != len(b):
        return False
    result = 0
    for x, y in zip(a.encode(), b.encode()):
        result |= x ^ y
    return result == 0


#=============================================================================
# API ROUTES
#=============================================================================
@app.route(f'/{PATH_PREFIX}/api/v1/status', methods=['GET'])
@require_auth
@rate_limit(api_limiter)
def status():
    success, uptime = execute_allowed_command('uptime')
    return jsonify({
        'status': 'online',
        'domain': NODE_DOMAIN,
        'uptime': uptime.strip() if success else 'unknown',
        'path_prefix': PATH_PREFIX
    })


@app.route(f'/{PATH_PREFIX}/api/v1/services', methods=['GET'])
@require_auth
@rate_limit(api_limiter)
def services():
    return jsonify({
        'services': {
            'singbox': get_container_status('singbox'),
            'adguard': get_container_status('adguard'),
            'caddy': get_container_status('caddy'),
            'agent': 'running'
        }
    })


@app.route(f'/{PATH_PREFIX}/api/v1/restart/<service>', methods=['POST'])
@require_auth
@rate_limit(api_limiter)
def restart_service(service):
    try:
        service = sanitize_service(service)
    except ValueError as e:
        return jsonify({'error': str(e)}), 400
    
    success, output = execute_allowed_command(f'restart_{service}')
    return jsonify({
        'success': success,
        'service': service,
        'message': output.strip()
    })


@app.route(f'/{PATH_PREFIX}/api/v1/config/<service>', methods=['GET'])
@require_auth
@rate_limit(api_limiter)
def get_config(service):
    try:
        service = sanitize_service(service)
    except ValueError as e:
        return jsonify({'error': str(e)}), 400
    
    config_files = {
        'singbox': os.path.join(CONFIG_DIR, 'singbox', 'config.json'),
        'adguard': os.path.join(CONFIG_DIR, 'adguard', 'AdGuardHome.yaml'),
        'caddy': os.path.join(CONFIG_DIR, 'caddy', 'Caddyfile')
    }
    
    config_path = config_files[service]
    
    # Prevent path traversal
    real_path = os.path.realpath(config_path)
    if not real_path.startswith(os.path.realpath(CONFIG_DIR)):
        return jsonify({'error': 'Invalid path'}), 400
    
    if not os.path.exists(config_path):
        return jsonify({'error': 'Config not found'}), 404
    
    with open(config_path, 'r') as f:
        return jsonify({'service': service, 'content': f.read()})


@app.route(f'/{PATH_PREFIX}/api/v1/config/<service>', methods=['POST'])
@require_auth
@rate_limit(api_limiter)
def update_config(service):
    try:
        service = sanitize_service(service)
    except ValueError as e:
        return jsonify({'error': str(e)}), 400
    
    data = request.json
    if not data or 'content' not in data:
        return jsonify({'error': 'Missing content'}), 400
    
    config_files = {
        'singbox': os.path.join(CONFIG_DIR, 'singbox', 'config.json'),
        'adguard': os.path.join(CONFIG_DIR, 'adguard', 'AdGuardHome.yaml'),
        'caddy': os.path.join(CONFIG_DIR, 'caddy', 'Caddyfile')
    }
    
    config_path = config_files[service]
    
    # Prevent path traversal
    real_path = os.path.realpath(os.path.dirname(config_path))
    if not real_path.startswith(os.path.realpath(CONFIG_DIR)):
        return jsonify({'error': 'Invalid path'}), 400
    
    os.makedirs(os.path.dirname(config_path), exist_ok=True)
    with open(config_path, 'w') as f:
        f.write(data['content'])
    
    return jsonify({'success': True, 'message': 'Updated'})


@app.route(f'/{PATH_PREFIX}/api/v1/logs/<service>', methods=['GET'])
@require_auth
@rate_limit(api_limiter)
def get_logs(service):
    try:
        service = sanitize_service(service)
    except ValueError as e:
        return jsonify({'error': str(e)}), 400
    
    lines = sanitize_lines(request.args.get('lines', '100'))
    success, output = execute_allowed_command(f'logs_{service}', lines=lines)
    return jsonify({'service': service, 'logs': output})


# Health check (public, but rate limited)
@app.route('/health', methods=['GET'])
@rate_limit(api_limiter)
def health():
    return jsonify({'status': 'healthy'})


if __name__ == '__main__':
    print(f"[SUI Solo Agent] Domain: {NODE_DOMAIN}")
    print(f"[SUI Solo Agent] API: /{PATH_PREFIX}/api/v1/")
    print(f"[SUI Solo Agent] Security: Rate limiting enabled, command whitelist active")
    app.run(host='0.0.0.0', port=5001)
