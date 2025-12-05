# Changelog

All notable changes to SUI Solo will be documented in this file.

## [1.9.22] - 2025-12-06

### Added
- **Diagnostic tools**: New diagnostics system for troubleshooting
  - `diagnose.sh` script for system-wide health checks
  - Node Agent `/api/v1/diagnostics` endpoint
  - Checks Docker, iptables, networks, containers, configs
  - Auto-fix suggestions for common issues
- **Installation improvements**: Proactive issue detection
  - Auto-detect and fix iptables/nftables conflicts
  - Verify Docker networks exist before starting containers
  - Container health checks after installation
  - Better error messages with fix suggestions

### Changed
- **Firewall management redesigned**: Now provides SSH commands instead of direct control
  - Shows ready-to-use commands for UFW, firewalld, and iptables
  - Select firewall type from dropdown
  - Copy commands to clipboard
  - More secure (doesn't require privileged container)

### Fixed
- Fixed Master update function: use Python `requests` instead of `curl` (not available in container)
- **Fixed service status showing "not found"**: Installed docker-ce-cli in agent container
  - Agent can now properly check container status via Docker CLI
  - Services (singbox, adguard) now show correct "running" status
- **Fixed iptables conflict**: Auto-switch to iptables-legacy on systems using nftables
- **Fixed missing Docker networks**: Auto-create networks with proper error handling

---

## [1.9.21] - 2025-12-06

### Added
- **Firewall management from Master panel**: 
  - New "Firewall" button on each node card
  - View current firewall status and allowed ports
  - Configure allowed ports with support for port ranges (e.g., 8445-8450)
  - Supports UFW, firewalld, and iptables
- Node Agent firewall API: GET/POST `/api/v1/firewall`

---

## [1.9.20] - 2025-12-06

### Fixed
- Fixed container name mismatch in Node Agent: `sui-gateway` → `sui-caddy`
- This fixes the "not found" status for Caddy service

### Added
- **Firewall configuration**: Install script now offers to configure firewall
  - Supports UFW, firewalld, and iptables
  - Default allows: SSH(22), HTTP(80), HTTPS(443), DNS(53), VLESS(8443), Hysteria2(8444)
  - Blocks AdGuard Home direct port (3000) - access via reverse proxy instead
  - Option to add custom port ranges for Hysteria2 multi-port

---

## [1.9.19] - 2025-12-06

### Added
- **update.sh**: Standalone update script for command-line updates
  - Usage: `./update.sh [master|node|all]`
  - Auto-downloads latest version from GitHub
  - Auto-restarts containers after update
  - Creates backups before updating

### Changed
- Master update API now auto-restarts container after update (no manual restart needed)
- Update runs in background thread so API response is sent before restart

---

## [1.9.18] - 2025-12-06

### Fixed
- Fixed Master update function - now uses correct file paths instead of hardcoded `/opt/sui-solo/master`
- Fixed subscription URL generation - auto-detects domain from request if `MASTER_DOMAIN` env not set
- Simplified subscription URLs (removed redundant `?format=base64` for default format)

---

## [1.9.17] - 2025-12-06

### Added
- **Sing-box config validation**: Node agent now validates JSON format and structure before saving
  - Checks for valid JSON syntax
  - Validates required fields (outbounds)
  - Validates inbound/outbound types against sing-box spec
  - Validates port ranges (1-65535)
  - Re-serializes JSON for consistent formatting

### Security
- Config validation prevents malformed configurations from being saved

---

## [1.9.16] - 2025-12-06

### Removed
- Removed "System Controls" section from dashboard (Restart Master, Restart Gateway, Update Master, Update All Nodes buttons)

### Fixed
- Fixed node services status showing "not found" on page load - now auto-checks node status first before loading services

---

## [1.9.15] - 2025-12-06

### Added
- **Preset Templates Auto-Init**: Node automatically generates 3 preset proxy configs on first run
  - VLESS + XTLS-Vision + Reality (port 10000)
  - VMess + WebSocket (port 10001)
  - Hysteria2 (port 10002)
- **Preset Management UI**: New "Presets" button on node cards to toggle templates on/off
- **Aggregated Subscription**: Master collects all node presets into unified subscription links
- **Hidden Subscription Path**: Secure subscription URL with hashed path
- **Auto-Restart on Config Save**: Services automatically restart after config changes

### Changed
- Subscribe modal now shows both public and hidden subscription URLs
- Config save now shows progress (Saving... → Restarting...)
- Improved subscription link generation with proper protocol formats

---

## [1.9.14] - 2025-12-06

### Added
- Sing-box config templates: VLESS+Reality, VLESS+WS, VMess+WS, Hysteria2, Trojan
- Template auto-fills with generated UUID
- Config modal now shows template buttons for singbox service

### Changed
- Expanded config modal for better editing experience

---

## [1.9.13] - 2025-12-06

### Added
- Master panel: "System Controls" section with Rebuild Master/Gateway buttons
- Master panel: "Subscribe" button with subscription URL modal
- Subscription API: `/api/subscribe` supports base64, clash, singbox formats
- Subscription URL API: `/api/subscribe/url` returns all format URLs
- Master rebuild API: `/api/master/rebuild`
- Gateway rebuild API: `/api/gateway/rebuild`

### Changed
- Improved dashboard layout with quick action buttons

---

## [1.9.12] - 2025-12-06

### Added
- Master panel: Added "Rebuild" button to restart all Node containers remotely
- Node Agent: Added `/rebuild` API endpoint for container rebuild
- `--both` installation: Auto-connects Node to Master (no manual add needed)

### Changed
- Node is automatically registered in Master when using `--both` installation

---

## [1.9.11] - 2025-12-06

### Fixed
- Fixed Master-Node status communication (services showing "not found")
- Changed caddy container name from `sui-caddy` to `sui-gateway` in agent.py
- Removed `cap_drop: ALL` and `read_only: true` from agent container (was blocking docker commands)
- Fixed uptime command to use `/proc/uptime` instead of `uptime -p` (not available in container)
- Improved uptime display format (e.g., "2d 5h 30m")

---

## [1.9.10] - 2025-12-06

### Fixed
- `kill_port_process` now stops SUI Solo Docker containers before killing port processes
- Added support for OpenRC and SysVinit (not just systemd) for Docker service management
- Better compatibility with Alpine Linux and other non-systemd distributions

---

## [1.9.9] - 2025-12-06

### Fixed
- Added Docker startup wait loop after installation
- Script now waits up to 30 seconds for Docker daemon to be ready
- Better error message if Docker fails to start

---

## [1.9.8] - 2025-12-06

### Fixed
- Changed all GitHub download links from Eng branch to main branch
- Fixed install.sh, master/app.py, node/agent.py update URLs

---

## [1.9.7] - 2025-12-06

### Fixed
- Fixed sui-singbox container restarting (exit code 0)
- Added explicit `command: ["run", "-c", "/etc/sing-box/config.json"]` to singbox service
- sing-box now properly loads config file on startup

---

## [1.9.6] - 2025-12-06

### Fixed
- Fixed Caddyfile syntax error causing gateway to fail
- Changed `header { }` blocks to multi-line format
- Changed `handle { }` blocks to multi-line format

---

## [1.9.5] - 2025-12-06

### Added
- Auto-detect existing installation and show current domain/email
- Option to keep existing settings or enter new ones during reinstall

---

## [1.9.4] - 2025-12-06

### Fixed
- Added secret display at end of `--both` installation
- Removed deprecated `version: '3.8'` from all docker-compose.yml files

---

## [1.9.3] - 2025-12-06

### Fixed
- Replaced ALL `[[ ]] && { }` patterns with proper `if/then/fi` blocks
- Fixed `generate_shared_caddyfile()` causing script exit when node not installed
- Fixed `load_env_defaults()`, `install_both()`, and `main()` functions

---

## [1.9.2] - 2025-12-06

### Fixed
- Fixed `start_shared_gateway()` silently failing due to `set -e`
- Added proper error handling for `docker compose up` commands
- Now shows docker logs when container startup fails

---

## [1.9.1] - 2025-12-06

### Fixed
- Fixed script exiting immediately due to `set -e` with conditional expressions
- Added `|| true` to all `[[ ]] && action` patterns to prevent false exit codes
- Improved `detect_script_dir()` robustness for `curl | bash` mode
- Fixed `check_os()` and `check_root()` functions to not trigger `set -e`

---

## [1.9.0] - 2025-12-06

### Changed
- Simplified installation script to English-only
- Simplified dashboard to English-only
- Removed i18n system and language selection (was causing script exit issues)
- Cleaner, more maintainable codebase
- All GitHub links now point to `Eng` branch

### Removed
- Removed Chinese language support from install script
- Removed `MSG_EN`, `MSG_ZH` arrays and `msg()` function
- Removed `select_language()` function
- Removed language toggle button from dashboard
- Removed `README_CN.md` (Chinese documentation)

---

## [1.7.0] - 2025-12-06

### Added
- **Shared Gateway Architecture**: Master and Node now share a single Caddy instance
- **`--both` Command**: One-click installation of Master + Node on same server
- **Smart Port Detection**: Automatically detects if ports are used by SUI Solo containers
- **Docker Network Isolation**: Separate networks for Master and Node services

### Changed
- Refactored installation to use shared `/opt/sui-solo/gateway` for Caddy
- Master and Node docker-compose files no longer include Caddy
- Improved uninstall to properly handle shared gateway cleanup
- Gateway Caddyfile auto-regenerates when components are added/removed

### Fixed
- Fixed port conflict when installing Node after Master on same server
- Fixed "Kill process" option failing for SUI Solo's own containers

---

## [1.6.1] - 2025-12-06

### Fixed
- Fixed overwrite installation not updating Caddy config (domain stuck on old value)
- Added detection for existing installation with option to overwrite or cancel
- Containers now properly stopped before overwrite to ensure new config takes effect

---

## [1.6.0] - 2025-12-05

### Changed
- Version bump to 1.6.0
- Enabled auto version increment for future code changes

---

## [1.5.0] - 2025-12-05

### Added
- **Update System**: Master can now update itself and all nodes remotely
- **Settings Panel**: New settings modal with auto-update toggle
- **Version Check**: Check for updates from GitHub
- **Node Update Button**: Update individual nodes from the dashboard
- **Update All Nodes**: One-click update for all connected nodes
- **Version Display**: Show current version in header
- **Uninstall Command**: `--uninstall` flag for easy removal
- **Reinstall Command**: `--reinstall` flag with option to keep or delete settings
- **Port Conflict Resolution**: Option to kill processes occupying required ports

### Changed
- Improved node card UI with more actions
- Better error handling for API calls
- Improved installation output formatting
- Better visual display of Cluster Secret after installation

### Fixed
- Fixed output formatting issues (URL display)

### Security
- Removed secret display from dashboard (security fix)
- Removed `/api/secret` endpoint

---

## [1.1.0] - 2025-12-05

### Added
- **One-line Installation**: `curl | bash` support for easy deployment
- **Auto Download**: Script automatically downloads source files if not found locally
- **AdGuard Home Links**: Quick access to AdGuard Home from node cards
- **Service Status Grid**: Visual display of Sing-box, AdGuard, Caddy status
- **Logs Viewer**: View service logs from dashboard
- **Config Editor**: Edit Sing-box configuration remotely
- **Service Restart**: Restart individual services from dashboard

### Fixed
- Fixed `read` command not working in pipe mode (added `/dev/tty`)
- Fixed version number not syncing in banner
- Fixed app.py regex pattern corruption
- Fixed unzip not being auto-installed

### Changed
- Improved path detection for extracted zip files
- Better error messages for missing source files
- Support for multiple package managers (apt, yum, dnf, pacman, apk, brew)

---

## [1.0.0] - 2025-12-04

### Added
- Initial release
- Master control panel with Flask backend
- Node agent with security hardening
- Caddy reverse proxy with automatic HTTPS
- Sing-box proxy integration
- AdGuard Home DNS filtering
- Rate limiting protection
- Hidden API paths with SHA256 hashing
- Token-based authentication
- Docker Compose deployment
- Interactive installation script

### Security
- HTTPS enforced via Caddy
- Hidden API endpoints
- X-SUI-Token header authentication
- Rate limiting (5 auth attempts/min)
- Input sanitization
- Command whitelist for docker operations
- Read-only containers where possible
- Dropped capabilities
