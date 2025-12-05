#!/bin/sh
#
# Minimal Docker Command Proxy
# Only allows specific whitelisted commands
# Reduces attack surface by not exposing full docker.sock to agent
#

set -e

SOCKET_PATH="/run/sui-cmd/cmd.sock"
mkdir -p /run/sui-cmd

echo "[Docker Proxy] Starting with restricted command set..."
echo "[Docker Proxy] Allowed: restart/inspect/logs for sui-* containers only"

# Create named pipe for command communication
rm -f "$SOCKET_PATH"
mkfifo "$SOCKET_PATH"

while true; do
    if read cmd < "$SOCKET_PATH"; then
        case "$cmd" in
            # Restart commands
            "restart:singbox")
                docker restart sui-singbox 2>&1 || echo "ERROR: Failed to restart sui-singbox"
                ;;
            "restart:adguard")
                docker restart sui-adguard 2>&1 || echo "ERROR: Failed to restart sui-adguard"
                ;;
            "restart:caddy")
                docker restart sui-caddy 2>&1 || echo "ERROR: Failed to restart sui-caddy"
                ;;
            # Status commands
            "status:singbox")
                docker inspect -f '{{.State.Status}}' sui-singbox 2>&1 || echo "not found"
                ;;
            "status:adguard")
                docker inspect -f '{{.State.Status}}' sui-adguard 2>&1 || echo "not found"
                ;;
            "status:caddy")
                docker inspect -f '{{.State.Status}}' sui-caddy 2>&1 || echo "not found"
                ;;
            # Log commands (limited to 100 lines)
            "logs:singbox")
                docker logs --tail 100 sui-singbox 2>&1 || echo "ERROR: No logs"
                ;;
            "logs:adguard")
                docker logs --tail 100 sui-adguard 2>&1 || echo "ERROR: No logs"
                ;;
            "logs:caddy")
                docker logs --tail 100 sui-caddy 2>&1 || echo "ERROR: No logs"
                ;;
            *)
                echo "ERROR: Command not allowed: $cmd"
                ;;
        esac
    fi
done
