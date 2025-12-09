# Design Document

## Overview

This design modifies the SUI Proxy network architecture to position Sing-box as the primary entry point on port 443, with intelligent traffic routing based on protocol detection. The current architecture has Caddy handling both ports 80 and 443 as a gateway. The new architecture will:

1. Sing-box listens on port 443 and performs TLS termination
2. Sing-box routes proxy protocol traffic (VLESS) to its internal handlers
3. Sing-box falls back non-proxy HTTPS traffic to Caddy gateway
4. Caddy only listens on port 80 for HTTP traffic and ACME challenges
5. Docker networking enables container-to-container communication

This approach allows proxy services to coexist with web services on the same port, using protocol detection to route traffic appropriately.

## Architecture

### Current Architecture

```
Internet → Port 443 → Caddy Gateway → Master/Node Services
Internet → Port 80  → Caddy Gateway → ACME Challenges
```

### New Architecture

```
Internet → Port 443 → Sing-box (TLS Termination)
                      ├─ VLESS Traffic → Proxy Outbound
                      └─ HTTPS Traffic → Fallback → Caddy (Port 80) → Master Services
                      
Internet → Port 80  → Caddy Gateway → ACME Challenges
```

### Network Flow

1. **Proxy Traffic Flow**:
   - Client connects to port 443 with VLESS protocol
   - Sing-box detects VLESS handshake
   - Sing-box authenticates and proxies the connection
   - Traffic routed through direct outbound

2. **Web Traffic Flow**:
   - Client connects to port 443 with HTTPS (non-proxy)
   - Sing-box detects standard TLS/HTTPS
   - Sing-box forwards connection to gateway container on port 80
   - Caddy processes as HTTP request and routes to Master app
   - Response flows back through the same path

3. **ACME Challenge Flow**:
   - ACME provider connects to port 80
   - Caddy handles HTTP-01 challenge directly
   - Certificate issued and stored

## Components and Interfaces

### 1. Sing-box Configuration

**File**: `node/config/singbox/config.json`

**Key Sections**:

- **Inbounds**: 
  - VLESS inbound on port 443 with TLS and fallback configuration
  - Hysteria2 inbound on UDP port range for alternative protocol
  
- **Outbounds**:
  - Direct outbound for proxy traffic
  - Fallback outbound pointing to gateway container

- **Routing**:
  - Default route to direct outbound
  - Implicit fallback for non-proxy traffic

**Interface**:
```json
{
  "inbounds": [
    {
      "type": "vless",
      "listen": "::",
      "listen_port": 443,
      "users": [...],
      "tls": {
        "enabled": true,
        "server_name": "node.example.com",
        "acme": {...}
      },
      "fallback": {
        "server": "gateway",
        "server_port": 80
      }
    }
  ],
  "outbounds": [
    {
      "type": "direct",
      "tag": "direct"
    }
  ]
}
```

### 2. Gateway Docker Compose

**File**: `gateway/docker-compose.yml`

**Changes**:
- Remove port 443 binding
- Keep only port 80 binding
- Maintain network connectivity to both master-net and node-net

**Interface**:
```yaml
services:
  gateway:
    image: caddy:2-alpine
    ports:
      - "80:80"  # Only HTTP
    networks:
      - sui-master-net
      - sui-node-net
```

### 3. Node Docker Compose

**File**: `node/docker-compose.yml`

**Changes**:
- Sing-box container binds to host port 443
- Sing-box connects to both node-net and master-net (for fallback routing)
- Caddy container removed from node deployment (uses shared gateway)

**Interface**:
```yaml
services:
  singbox:
    image: ghcr.io/sagernet/sing-box:latest
    ports:
      - "443:443/tcp"
      - "50200-50300:50200-50300/udp"
    networks:
      - sui-node-net
      - sui-master-net
```

### 4. Installation Script

**File**: `install.sh`

**Functions to Modify**:

- `setup_shared_gateway()`: Generate gateway docker-compose with only port 80
- `install_node()`: Generate Sing-box config with fallback settings
- `generate_singbox_config()`: Add fallback configuration to VLESS inbound

**Key Logic**:
```bash
# In setup_shared_gateway()
ports:
  - "80:80"  # Remove 443

# In generate_singbox_config()
"fallback": {
  "server": "gateway",
  "server_port": 80
}
```

### 5. Configuration Templates

**File**: `node/templates/singbox-config.json.template`

**Additions**:
- Fallback section in VLESS inbound
- Template variables for gateway container name and port

## Data Models

### Sing-box Configuration Schema

```typescript
interface SingboxConfig {
  log: LogConfig;
  inbounds: Inbound[];
  outbounds: Outbound[];
  route: RouteConfig;
}

interface VLESSInbound {
  type: "vless";
  tag: string;
  listen: string;
  listen_port: number;
  users: User[];
  tls: TLSConfig;
  fallback?: FallbackConfig;  // New field
}

interface FallbackConfig {
  server: string;      // Container name or IP
  server_port: number; // Destination port
}

interface TLSConfig {
  enabled: boolean;
  server_name: string;
  acme: ACMEConfig;
}
```

### Docker Compose Schema

```typescript
interface DockerComposeService {
  image: string;
  container_name: string;
  restart: string;
  ports?: string[];  // Modified for gateway
  expose?: string[]; // For internal services
  networks: string[];
  volumes?: string[];
}

interface GatewayService extends DockerComposeService {
  ports: ["80:80"];  // Only HTTP port
}

interface SingboxService extends DockerComposeService {
  ports: ["443:443/tcp", "50200-50300:50200-50300/udp"];
  networks: ["sui-node-net", "sui-master-net"];  // Both networks
}
```

## Correctness Properties

*A property is a characteristic or behavior that should hold true across all valid executions of a system-essentially, a formal statement about what the system should do. Properties serve as the bridge between human-readable specifications and machine-verifiable correctness guarantees.*


### Property Reflection

After reviewing all identified properties, several can be consolidated:

- Properties 1.1, 1.3, and 2.1 all test port binding configuration and can be combined into a single comprehensive port binding property
- Properties 5.1, 5.2, 5.3, and 5.4 all test fallback configuration and can be combined into one fallback configuration property
- Properties 6.1 and 6.2 test script output generation and can be combined
- Properties 7.1 and 7.2 test template content and can be combined

This reduces redundancy while maintaining comprehensive coverage.

### Correctness Properties

Property 1: Port binding configuration
*For any* deployment configuration (gateway or node), the generated docker-compose.yml should have gateway binding only to port 80 and Sing-box binding to port 443
**Validates: Requirements 1.1, 1.3, 2.1**

Property 2: TLS termination on port 443
*For any* TLS connection to port 443, Sing-box should successfully complete the TLS handshake
**Validates: Requirements 1.2**

Property 3: Proxy traffic routing
*For any* valid VLESS or Hysteria2 connection with correct credentials, Sing-box should route the traffic through its proxy outbound and not forward to the gateway container
**Validates: Requirements 3.1, 3.2, 3.3**

Property 4: Fallback routing for non-proxy traffic
*For any* HTTPS connection that is not a proxy protocol, Sing-box should forward the connection to the gateway container on port 80
**Validates: Requirements 4.1, 4.2, 4.4**

Property 5: Fallback configuration completeness
*For any* generated Sing-box configuration, the VLESS inbound should include a fallback section specifying the gateway container name and port 80
**Validates: Requirements 5.1, 5.2, 5.3, 5.4**

Property 6: Installation script output validity
*For any* execution of the installation script, the generated docker-compose.yml and config.json files should be syntactically valid and contain the required port and fallback configurations
**Validates: Requirements 6.1, 6.2, 6.3**

Property 7: Docker network connectivity
*For any* shared deployment (Master + Node on same server), both Sing-box and gateway containers should be connected to both sui-master-net and sui-node-net networks
**Validates: Requirements 6.4**

Property 8: Template configuration correctness
*For any* configuration template (Sing-box or Caddy), the template should contain the appropriate placeholders for fallback/HTTP configuration and variable substitution should produce valid output
**Validates: Requirements 7.1, 7.2, 7.3**

## Error Handling

### 1. Port Binding Conflicts

**Scenario**: Port 443 already in use when starting Sing-box

**Handling**:
- Docker will fail to start the container with a clear error message
- Installation script should check for port availability before deployment
- Provide diagnostic command: `sudo lsof -i :443` or `sudo ss -tlnp | grep :443`

**Prevention**:
```bash
# In install.sh
check_port_available() {
    local port=$1
    if ss -tlnp | grep -q ":${port} "; then
        log_error "Port ${port} is already in use"
        ss -tlnp | grep ":${port}"
        return 1
    fi
}
```

### 2. Network Connectivity Issues

**Scenario**: Sing-box cannot reach gateway container for fallback

**Handling**:
- Verify both containers are on the same Docker network
- Check Docker network configuration: `docker network inspect sui-master-net`
- Ensure gateway container is running before Sing-box attempts fallback

**Prevention**:
```yaml
# In docker-compose.yml
services:
  singbox:
    depends_on:
      - gateway  # Ensure gateway starts first
```

### 3. Invalid Configuration Generation

**Scenario**: Installation script generates invalid JSON or YAML

**Handling**:
- Validate configuration files after generation
- Use `jq` for JSON validation: `jq empty config.json`
- Use `yamllint` or Docker Compose validation: `docker compose config`

**Prevention**:
```bash
# In install.sh
validate_json() {
    local file=$1
    if ! jq empty "$file" 2>/dev/null; then
        log_error "Invalid JSON in $file"
        return 1
    fi
}
```

### 4. TLS Certificate Issues

**Scenario**: ACME challenge fails because port 80 is not accessible

**Handling**:
- Ensure Caddy is running and port 80 is open
- Check firewall rules: `sudo ufw status`
- Verify DNS records point to the correct server
- Check Caddy logs: `docker compose logs gateway`

**Prevention**:
- Pre-flight checks in installation script for DNS resolution
- Verify port 80 accessibility before starting services

### 5. Fallback Loop

**Scenario**: Sing-box forwards traffic to Caddy, which tries to forward back to Sing-box

**Handling**:
- Ensure Caddy is configured to handle HTTP (not HTTPS) on port 80
- Verify fallback configuration points to port 80, not 443
- Check Caddy configuration doesn't have redirect loops

**Prevention**:
```json
// In Sing-box config
"fallback": {
  "server": "gateway",
  "server_port": 80  // Must be 80, not 443
}
```

## Testing Strategy

### Unit Testing

Unit tests will verify individual components and configuration generation:

1. **Configuration File Parsing**:
   - Test JSON parsing of Sing-box config
   - Test YAML parsing of docker-compose files
   - Verify required fields are present

2. **Port Configuration Validation**:
   - Test that gateway docker-compose has only port 80
   - Test that Sing-box docker-compose has port 443
   - Verify no port conflicts in generated configurations

3. **Fallback Configuration Validation**:
   - Test that Sing-box config includes fallback section
   - Verify fallback points to correct container and port
   - Test template variable substitution

4. **Network Configuration**:
   - Verify containers are assigned to correct networks
   - Test network connectivity configuration

### Property-Based Testing

Property-based tests will verify universal properties across many inputs using a PBT library appropriate for the scripting language (likely Bash with BATS or Python with Hypothesis if we extract testable functions).

**Testing Framework**: Since the implementation is primarily Bash scripts and configuration files, we will use:
- **BATS (Bash Automated Testing System)** for Bash script testing
- **ShellCheck** for static analysis
- **Docker Compose validation** for configuration testing

**Test Configuration**: Each property test should run a minimum of 100 iterations to ensure comprehensive coverage.

**Property Test Tagging**: Each property-based test must include a comment tag in this format:
```bash
# Feature: singbox-443-fallback, Property 1: Port binding configuration
```

### Integration Testing

Integration tests will verify the complete system behavior:

1. **End-to-End Proxy Flow**:
   - Deploy complete system (Master + Node)
   - Connect VLESS client to port 443
   - Verify proxy traffic flows correctly
   - Verify no traffic reaches gateway container

2. **End-to-End Web Flow**:
   - Deploy complete system
   - Make HTTPS request to Master domain on port 443
   - Verify traffic is forwarded to Caddy
   - Verify Master application responds correctly

3. **ACME Challenge Flow**:
   - Deploy system with new domain
   - Trigger ACME HTTP-01 challenge
   - Verify Caddy handles challenge on port 80
   - Verify certificate is issued successfully

4. **Port Binding Verification**:
   - Start all containers
   - Verify port 443 is bound by Sing-box only
   - Verify port 80 is bound by Caddy only
   - Check with `ss -tlnp` or `netstat -tlnp`

5. **Network Connectivity**:
   - Verify Sing-box can reach gateway container
   - Test fallback by sending non-proxy HTTPS traffic
   - Verify traffic reaches Caddy and Master app

### Test Execution Strategy

1. **Pre-deployment Tests**:
   - Validate generated configuration files
   - Check port availability
   - Verify DNS resolution

2. **Post-deployment Tests**:
   - Verify container status
   - Check port bindings
   - Test proxy connectivity
   - Test web access
   - Verify logs for errors

3. **Regression Tests**:
   - Test existing functionality still works
   - Verify Master panel is accessible
   - Verify Node management works
   - Check AdGuard Home access

### Test Data and Fixtures

- Sample docker-compose.yml files with various configurations
- Sample Sing-box config.json files with different inbound/outbound setups
- Mock VLESS client connections
- Mock HTTPS requests
- Test domains and certificates

## Implementation Notes

### Sing-box Fallback Mechanism

Sing-box supports fallback through the `fallback` field in VLESS inbound configuration. When Sing-box receives a connection that doesn't match the VLESS protocol, it forwards the raw TCP connection to the specified fallback destination.

**Key Points**:
- Fallback happens at the protocol detection level
- The connection is forwarded as-is (no re-encryption)
- Caddy receives the connection as if it came directly from the client
- TLS is already terminated by Sing-box, so Caddy sees plain HTTP

### Docker Network Configuration

For fallback to work, Sing-box and gateway containers must be on the same Docker network. In shared deployment mode:

- Both containers connect to `sui-master-net` and `sui-node-net`
- Container name resolution works automatically within Docker networks
- Fallback uses container name `gateway` instead of IP address

### ACME Certificate Management

With Sing-box on port 443, ACME HTTP-01 challenges must go through port 80:

- Caddy handles ACME challenges on port 80
- Sing-box doesn't interfere with port 80 traffic
- Certificates are stored in Caddy's data volume
- Sing-box uses its own ACME client for its domain

### Configuration Generation Order

The installation script must generate configurations in the correct order:

1. Create Docker networks
2. Generate gateway docker-compose.yml (port 80 only)
3. Generate Sing-box config.json (with fallback)
4. Generate node docker-compose.yml (port 443 binding)
5. Start gateway container first
6. Start Sing-box container (depends on gateway)

### Fresh Installation Only

This is a new project implementation with the new architecture from the start:

- No backward compatibility concerns
- No migration from old architecture needed
- Clean implementation of the new design
- All configurations generated fresh

## Security Considerations

1. **TLS Termination**: Sing-box performs TLS termination, so it has access to decrypted traffic. This is necessary for protocol detection but should be documented.

2. **Fallback Security**: Fallback traffic is forwarded to Caddy on port 80 (HTTP), but this is internal Docker network traffic, not exposed to the internet.

3. **Port Exposure**: Only ports 80 and 443 are exposed to the internet. Internal container ports remain isolated.

4. **Network Isolation**: Using Docker networks ensures containers can only communicate as configured.

## Performance Considerations

1. **Latency**: Adding Sing-box as a front-end adds minimal latency for proxy traffic. Fallback traffic has one additional hop (Sing-box → Caddy) but this is within the same host.

2. **Throughput**: Sing-box is designed for high-performance proxy operations. The fallback mechanism should not significantly impact throughput.

3. **Resource Usage**: Running Sing-box adds memory and CPU overhead, but it's minimal for typical workloads.

## Deployment Considerations

### Installation Process

The installation script will:
1. Create Docker networks (sui-master-net, sui-node-net)
2. Create gateway with port 80 only
3. Create Sing-box with port 443 and fallback configuration
4. Configure proper network connectivity between containers
5. Start gateway container first
6. Start Sing-box container (with dependency on gateway)
7. Verify all services are running and ports are correctly bound

### Verification Steps

After installation:
1. Check container status: `docker compose ps`
2. Verify port bindings: `ss -tlnp | grep -E ':(80|443)'`
3. Test proxy connection with VLESS client
4. Test web access to Master domain via HTTPS
5. Check logs for any errors: `docker compose logs`
