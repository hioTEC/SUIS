# Requirements Document

## Introduction

This feature modifies the SUI Proxy network architecture to position Sing-box as the primary entry point on port 443, with fallback capability to the Caddy gateway. Currently, Caddy handles both ports 80 and 443 as the gateway. The new architecture will have Sing-box listen on port 443 with TLS termination and SNI-based routing, while Caddy will only handle port 80 for HTTP traffic and ACME challenges.

## Glossary

- **Sing-box**: A universal proxy platform that handles VLESS and Hysteria2 protocols
- **Caddy**: A web server with automatic HTTPS that serves as the gateway for the Master control panel
- **Gateway Container**: The Docker container running Caddy that routes traffic to Master services
- **Node Container**: The Docker container running Sing-box for proxy services
- **SNI (Server Name Indication)**: TLS extension that allows routing based on the requested hostname
- **Fallback**: A mechanism where Sing-box forwards non-proxy traffic to another service (Caddy)
- **VLESS**: A lightweight proxy protocol
- **TLS Termination**: The process of decrypting TLS traffic at the entry point

## Requirements

### Requirement 1

**User Story:** As a system administrator, I want Sing-box to listen on port 443 as the primary entry point, so that all HTTPS traffic is handled by the proxy service first.

#### Acceptance Criteria

1. WHEN the Node container starts THEN Sing-box SHALL bind to port 443 on the host
2. WHEN Sing-box receives a connection on port 443 THEN Sing-box SHALL perform TLS termination
3. WHEN the system is deployed THEN the Gateway container SHALL NOT bind to port 443
4. WHEN a client connects to port 443 THEN Sing-box SHALL accept the connection before any other service

### Requirement 2

**User Story:** As a system administrator, I want Caddy to only listen on port 80, so that it can handle HTTP traffic and ACME HTTP-01 challenges without conflicting with Sing-box.

#### Acceptance Criteria

1. WHEN the Gateway container starts THEN Caddy SHALL bind only to port 80 on the host
2. WHEN Caddy receives an HTTP request THEN Caddy SHALL process it normally
3. WHEN ACME performs HTTP-01 challenge THEN Caddy SHALL respond to the challenge on port 80
4. WHEN the docker-compose.yml for gateway is read THEN the ports configuration SHALL specify only "80:80"

### Requirement 3

**User Story:** As a system administrator, I want Sing-box to route proxy traffic to its outbound handlers, so that legitimate proxy clients can use the service.

#### Acceptance Criteria

1. WHEN Sing-box receives a VLESS connection with valid credentials THEN Sing-box SHALL route the traffic through its proxy outbound
2. WHEN Sing-box receives a Hysteria2 connection with valid credentials THEN Sing-box SHALL route the traffic through its proxy outbound
3. WHEN proxy traffic is processed THEN Sing-box SHALL NOT forward it to the Gateway container

### Requirement 4

**User Story:** As a system administrator, I want Sing-box to fallback non-proxy HTTPS traffic to Caddy, so that the Master control panel remains accessible via HTTPS.

#### Acceptance Criteria

1. WHEN Sing-box receives an HTTPS connection that does not match proxy protocols THEN Sing-box SHALL forward the connection to the Gateway container
2. WHEN Sing-box forwards traffic to Gateway THEN the connection SHALL be forwarded to Caddy on port 80
3. WHEN the Master domain is accessed via HTTPS THEN the traffic SHALL be routed through Sing-box to Caddy
4. WHEN Caddy receives forwarded traffic from Sing-box THEN Caddy SHALL process it as a normal HTTP request

### Requirement 5

**User Story:** As a system administrator, I want the Sing-box configuration to include fallback settings, so that the routing behavior is properly defined.

#### Acceptance Criteria

1. WHEN the Sing-box configuration file is generated THEN the configuration SHALL include a fallback section in the VLESS inbound
2. WHEN the fallback configuration is defined THEN it SHALL specify the Gateway container as the destination
3. WHEN the fallback configuration is defined THEN it SHALL specify port 80 as the destination port
4. WHERE the deployment uses Docker networks THEN the fallback SHALL use the Gateway container name for routing

### Requirement 6

**User Story:** As a system administrator, I want the installation script to generate the correct configurations, so that the new architecture is deployed automatically.

#### Acceptance Criteria

1. WHEN the installation script runs THEN the script SHALL generate a gateway docker-compose.yml with only port 80 exposed
2. WHEN the installation script runs THEN the script SHALL generate a Sing-box config.json with port 443 inbound and fallback configuration
3. WHEN the installation script generates configurations THEN the configurations SHALL be syntactically valid
4. WHEN both Master and Node are deployed on the same server THEN the script SHALL configure proper Docker network connectivity between containers

### Requirement 7

**User Story:** As a developer, I want the configuration templates to be updated, so that future deployments use the new architecture.

#### Acceptance Criteria

1. WHEN the singbox-config.json.template is read THEN it SHALL include fallback configuration
2. WHEN the Caddyfile.template is read THEN it SHALL be configured to handle HTTP traffic on port 80
3. WHEN templates are used to generate configurations THEN variable substitution SHALL work correctly
