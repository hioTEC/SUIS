#!/usr/bin/env bats

# Feature: singbox-443-fallback, Property 1: Port binding configuration (node)
# Validates: Requirements 1.1, 1.4

setup() {
    COMPOSE_FILE="node/docker-compose.yml"
    
    # Check if yq is available for YAML parsing
    if ! command -v yq &> /dev/null; then
        skip "yq is not installed"
    fi
}

@test "Property 1: Sing-box binds to port 443 TCP" {
    # Get all ports for singbox service
    ports=$(yq eval '.services.singbox.ports[]' "$COMPOSE_FILE")
    
    # Verify port 443 TCP is configured
    echo "$ports" | grep -q "443:443/tcp"
}

@test "Property 1: Sing-box binds to UDP port range 50200-50300" {
    # Get all ports for singbox service
    ports=$(yq eval '.services.singbox.ports[]' "$COMPOSE_FILE")
    
    # Verify UDP port range is configured
    echo "$ports" | grep -q "50200-50300:50200-50300/udp"
}

@test "Property 1: Sing-box has exactly 2 port bindings" {
    # Count port bindings
    port_count=$(yq eval '.services.singbox.ports | length' "$COMPOSE_FILE")
    [ "$port_count" -eq 2 ]
}

@test "Property 1: Sing-box connects to both networks" {
    # Get networks for singbox service
    networks=$(yq eval '.services.singbox.networks[]' "$COMPOSE_FILE")
    
    # Verify sui-node-net
    echo "$networks" | grep -q "sui-node-net"
    
    # Verify sui-master-net
    echo "$networks" | grep -q "sui-master-net"
    
    # Verify exactly 2 networks
    network_count=$(yq eval '.services.singbox.networks | length' "$COMPOSE_FILE")
    [ "$network_count" -eq 2 ]
}

@test "Property 1: Sing-box depends on gateway" {
    # Verify depends_on includes gateway
    depends_on=$(yq eval '.services.singbox.depends_on[]' "$COMPOSE_FILE")
    echo "$depends_on" | grep -q "gateway"
}

@test "Property 1: Sing-box uses correct image" {
    # Verify image
    image=$(yq eval '.services.singbox.image' "$COMPOSE_FILE")
    [[ "$image" == *"sing-box"* ]]
}

@test "Property 1: Gateway in node compose exposes port 80 internally only" {
    # Verify gateway service exists
    run yq eval '.services.gateway' "$COMPOSE_FILE"
    [ "$status" -eq 0 ]
    
    # Verify gateway uses expose (not ports)
    expose=$(yq eval '.services.gateway.expose[]' "$COMPOSE_FILE")
    echo "$expose" | grep -q "80"
    
    # Verify gateway does NOT have ports section (should be null or empty)
    ports=$(yq eval '.services.gateway.ports' "$COMPOSE_FILE")
    [ "$ports" = "null" ] || [ -z "$ports" ]
}

@test "Property 1: No port 443 binding for gateway" {
    # Get all gateway configuration
    gateway_config=$(yq eval '.services.gateway' "$COMPOSE_FILE")
    
    # Verify no 443 in gateway configuration
    echo "$gateway_config" | grep -v "443"
}
