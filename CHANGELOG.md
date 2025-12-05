# Changelog

All notable changes to SUI Solo will be documented in this file.

## [1.6.0] - 2024-12-05

### Changed
- Version bump to 1.6.0
- Enabled auto version increment for future code changes

---

## [1.5.0] - 2024-12-05

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

## [1.1.0] - 2024-12-05

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

## [1.0.0] - 2024-12-04

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
