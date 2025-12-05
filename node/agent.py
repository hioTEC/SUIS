#!/usr/bin/env python3
"""SUI Solo Node Agent - Security Hardened"""

import os
import re
import hashlib
import subprocess
import time
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
    'uptime': ['uptime', '-p'],
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
    ok, uptime = execute_cmd('uptime')
    return jsonify({'status': 'online', 'domain': NODE_DOMAIN, 'uptime': uptime.strip() if ok else 'unknown'})


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
    os.makedirs(os.path.dirname(path), exist_ok=True)
    open(path, 'w').write(request.json.get('content', ''))
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
                curl -fsSL https://github.com/pjonix/SUIS/archive/Eng.zip -o /tmp/update.zip
                unzip -o /tmp/update.zip -d /tmp/
                cp /tmp/SUIS-Eng/node/agent.py ./agent.py.new
                cp /tmp/SUIS-Eng/node/templates/Caddyfile.template ./templates/Caddyfile.template.new
                mv ./agent.py.new ./agent.py
                mv ./templates/Caddyfile.template.new ./templates/Caddyfile.template
                rm -rf /tmp/update.zip /tmp/SUIS-Eng
                docker compose up -d --build
            '''],
            capture_output=True, text=True, timeout=120
        )
        return jsonify({'success': result.returncode == 0, 'output': result.stdout + result.stderr})
    except Exception as e:
        return jsonify({'success': False, 'error': str(e)})


@app.route(f'/{PATH_PREFIX}/api/v1/version')
@require_auth
@rate_limit(api_limiter)
def version():
    return jsonify({'version': '1.9.0'})


@app.route('/health')
def health():
    return jsonify({'status': 'healthy'})


if __name__ == '__main__':
    print(f"[SUI Solo Agent] {NODE_DOMAIN} | /{PATH_PREFIX}/api/v1/")
    app.run(host='0.0.0.0', port=5001)
