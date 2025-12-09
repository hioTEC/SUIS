#!/usr/bin/env bats

# Feature: singbox-443-fallback, Property 1: Port binding configuration (gateway)
# Validates: Requirements 1.3, 2.1, 2.4

setup() {
    COMPOSE_FILE="gateway/docker-compose.yml"
    
    # Check if yq is available for YAML parsing
    if ! command -v yq &> /dev/null; then
        skip "yq is not installed"
    fi
}

@test "Property 1: Gateway docker-compose binds only to port 80" {
    # Verify port 80 is configured
    port_config=$(yq eval '.services.gateway.ports[0]' "$COMPOSE_FILE")
    [ "$port_config" = "80:80" ]
    
    # Verify only one port is configured
    port_count=$(yq eval '.services.gateway.ports | length' "$COMPOSE_FILE")
    [ "$port_count" -eq 1 ]
    
    # Verify no port 443 configuration
    run yq eval '.services.gateway.ports[] | select(. == "*443*")' "$COMPOSE_FILE"
    [ "$status" -ne 0 ] || [ -z "$output" ]
}

@test "Property 1: Gateway connects to both sui-master-net and sui-node-net" {
    # Verify gateway is connected to sui-master-net
    networks=$(yq eval '.services.gateway.networks[]' "$COMPOSE_FILE")
    echo "$networks" | grep -q "sui-master-net"
    
    # Verify gateway is connected to sui-node-net
    echo "$networks" | grep -q "sui-node-net"
    
    # Verify exactly 2 networks
    network_count=$(yq eval '.services.gateway.networks | length' "$COMPOSE_FILE")
    [ "$network_count" -eq 2 ]
}

@test "Property 1: Gateway networks are marked as external" {
    # Verify sui-master-net is external
    master_net_external=$(yq eval '.networks.sui-master-net.external' "$COMPOSE_FILE")
    [ "$master_net_external" = "true" ]
    
    # Verify sui-node-net is external
    node_net_external=$(yq eval '.networks.sui-node-net.external' "$COMPOSE_FILE")
    [ "$node_net_external" = "true" ]
}

@test "Property 1: Gateway has proper volume mounts for Caddy" {
    # Get all volumes
    volumes=$(yq eval '.services.gateway.volumes[]' "$COMPOSE_FILE")
    
    # Verify Caddyfile volume mount
    echo "$volumes" | grep -q "Caddyfile"
    
    # Verify caddy_data volume
    echo "$volumes" | grep -q "caddy_data"
    
    # Verify caddy_config volume
    echo "$volumes" | grep -q "caddy_config"
}

@test "Property 1: Gateway uses Caddy image" {
    # Verify correct image
    image=$(yq eval '.services.gateway.image' "$COMPOSE_FILE")
    [[ "$image" == caddy:* ]]
}

@test "Property 1: Gateway container name is sui-gateway" {
    # Verify container name
    container_name=$(yq eval '.services.gateway.container_name' "$COMPOSE_FILE")
    [ "$container_name" = "sui-gateway" ]
}
