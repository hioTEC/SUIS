# Changelog

All notable changes to SUI Solo will be documented in this file.

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
