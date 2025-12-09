# Implementation Plan

- [x] 1. Update Sing-box configuration template with fallback
  - Modify `node/templates/singbox-config.json.template` to include fallback configuration in VLESS inbound
  - Add fallback section pointing to gateway container on port 80
  - Ensure template variables are properly defined for substitution
  - _Requirements: 5.1, 5.2, 5.3, 5.4, 7.1, 7.3_

- [x] 1.1 Write property test for Sing-box configuration template
  - **Property 5: Fallback configuration completeness**
  - **Validates: Requirements 5.1, 5.2, 5.3, 5.4**

- [x] 2. Update Caddy configuration template for HTTP-only
  - Modify `node/templates/Caddyfile.template` to handle HTTP traffic on port 80
  - Remove any HTTPS/TLS configuration from template
  - Ensure reverse proxy configuration works with HTTP
  - _Requirements: 7.2, 7.3_

- [x] 2.1 Write property test for Caddy template configuration
  - **Property 8: Template configuration correctness (Caddy)**
  - **Validates: Requirements 7.2, 7.3**

- [x] 3. Create gateway docker-compose configuration
  - Create or modify `gateway/docker-compose.yml` to expose only port 80
  - Configure gateway container to connect to both sui-master-net and sui-node-net
  - Set up proper volume mounts for Caddy data and configuration
  - _Requirements: 1.3, 2.1, 2.4_

- [x] 3.1 Write property test for gateway port configuration
  - **Property 1: Port binding configuration (gateway)**
  - **Validates: Requirements 1.3, 2.1, 2.4**

- [x] 4. Create node docker-compose configuration
  - Create or modify `node/docker-compose.yml` for Sing-box to bind port 443
  - Configure Sing-box container to connect to both sui-master-net and sui-node-net
  - Add Hysteria2 UDP port range (50200-50300)
  - Set up proper volume mounts for Sing-box configuration
  - Add depends_on to ensure gateway starts first
  - _Requirements: 1.1, 1.4, 6.4_

- [x] 4.1 Write property test for node port configuration
  - **Property 1: Port binding configuration (node)**
  - **Validates: Requirements 1.1, 1.4**

- [x] 4.2 Write property test for Docker network connectivity
  - **Property 7: Docker network connectivity**
  - **Validates: Requirements 6.4**

- [x] 5. Implement configuration generation in installation script
  - Create or modify `install.sh` to generate gateway docker-compose.yml with port 80 only
  - Implement function to generate Sing-box config.json with fallback configuration
  - Add template variable substitution for domain, email, UUID, passwords
  - Ensure generated files are syntactically valid JSON and YAML
  - _Requirements: 6.1, 6.2, 6.3_

- [x] 5.1 Write property test for installation script output
  - **Property 6: Installation script output validity**
  - **Validates: Requirements 6.1, 6.2, 6.3**

- [x] 6. Add Docker network setup to installation script
  - Create Docker networks (sui-master-net, sui-node-net) if they don't exist
  - Add network creation to installation script
  - Handle cases where networks already exist
  - _Requirements: 6.4_

- [x] 7. Add port availability checks to installation script
  - Implement pre-flight check for port 80 and 443 availability
  - Display helpful error messages if ports are in use
  - Show which process is using the port
  - _Requirements: 1.1, 2.1_

- [x] 8. Add configuration validation to installation script
  - Implement JSON validation for Sing-box config using jq
  - Implement YAML validation for docker-compose files
  - Add validation step after configuration generation
  - _Requirements: 6.3_

- [x] 9. Checkpoint - Ensure all tests pass
  - Ensure all tests pass, ask the user if questions arise.

- [ ] 10. Create integration test for proxy traffic flow
  - Write test script to deploy complete system
  - Test VLESS client connection to port 443
  - Verify proxy traffic is routed correctly
  - Verify no traffic reaches gateway container for proxy connections
  - _Requirements: 3.1, 3.2, 3.3_

- [ ] 10.1 Write property test for proxy traffic routing
  - **Property 3: Proxy traffic routing**
  - **Validates: Requirements 3.1, 3.2, 3.3**

- [ ] 11. Create integration test for web traffic fallback
  - Write test script to make HTTPS request to Master domain on port 443
  - Verify traffic is forwarded to Caddy on port 80
  - Verify Master application responds correctly
  - Test that Caddy processes forwarded traffic as HTTP
  - _Requirements: 4.1, 4.2, 4.3, 4.4_

- [ ] 11.1 Write property test for fallback routing
  - **Property 4: Fallback routing for non-proxy traffic**
  - **Validates: Requirements 4.1, 4.2, 4.4**

- [ ] 12. Create integration test for TLS termination
  - Write test to connect to port 443 with TLS client
  - Verify TLS handshake completes successfully
  - Test with various TLS versions and cipher suites
  - _Requirements: 1.2_

- [ ] 12.1 Write property test for TLS termination
  - **Property 2: TLS termination on port 443**
  - **Validates: Requirements 1.2**

- [ ] 13. Create integration test for HTTP traffic on port 80
  - Write test to send HTTP request to Caddy on port 80
  - Verify Caddy processes the request normally
  - Test various HTTP methods and paths
  - _Requirements: 2.2_

- [ ] 14. Update documentation
  - Update README.md with new architecture diagram
  - Document the port configuration (80 for Caddy, 443 for Sing-box)
  - Add troubleshooting section for common issues
  - Document the fallback mechanism
  - _Requirements: All_

- [ ] 15. Final Checkpoint - Verify complete system
  - Deploy complete system using installation script
  - Run all integration tests
  - Verify port bindings with ss/netstat
  - Test both proxy and web traffic flows
  - Check all container logs for errors
  - Ensure all tests pass, ask the user if questions arise.
