#!/usr/bin/env bats

# Feature: singbox-443-fallback, Property 7: Docker network connectivity
# Validates: Requirements 6.4

setup() {
    GATEWAY_COMPOSE="gateway/docker-compose.yml"
    NODE_COMPOSE="node/docker-compose.yml"
    
    # Check if yq is available for YAML parsing
    if ! command -v yq &> /dev/null; then
        skip "yq is not installed"
    fi
}

@test "Property 7: Both gateway and singbox connect to sui-master-net" {
    # Check gateway
    gateway_networks=$(yq eval '.services.gateway.networks[]' "$GATEWAY_COMPOSE")
    echo "$gateway_networks" | grep -q "sui-master-net"
    
    # Check singbox
    singbox_networks=$(yq eval '.services.singbox.networks[]' "$NODE_COMPOSE")
    echo "$singbox_networks" | grep -q "sui-master-net"
}

@test "Property 7: Both gateway and singbox connect to sui-node-net" {
    # Check gateway
    gateway_networks=$(yq eval '.services.gateway.networks[]' "$GATEWAY_COMPOSE")
    echo "$gateway_networks" | grep -q "sui-node-net"
    
    # Check singbox
    singbox_networks=$(yq eval '.services.singbox.networks[]' "$NODE_COMPOSE")
    echo "$singbox_networks" | grep -q "sui-node-net"
}

@test "Property 7: Networks are marked as external in both compose files" {
    # Check gateway compose
    gateway_master_external=$(yq eval '.networks.sui-master-net.external' "$GATEWAY_COMPOSE")
    [ "$gateway_master_external" = "true" ]
    
    gateway_node_external=$(yq eval '.networks.sui-node-net.external' "$GATEWAY_COMPOSE")
    [ "$gateway_node_external" = "true" ]
    
    # Check node compose
    node_master_external=$(yq eval '.networks.sui-master-net.external' "$NODE_COMPOSE")
    [ "$node_master_external" = "true" ]
    
    node_node_external=$(yq eval '.networks.sui-node-net.external' "$NODE_COMPOSE")
    [ "$node_node_external" = "true" ]
}

@test "Property 7: Gateway service in node compose connects to both networks" {
    # Verify gateway in node compose also connects to both networks
    gateway_networks=$(yq eval '.services.gateway.networks[]' "$NODE_COMPOSE")
    
    echo "$gateway_networks" | grep -q "sui-master-net"
    echo "$gateway_networks" | grep -q "sui-node-net"
}

@test "Property 7: Network configuration enables container-to-container communication" {
    # Verify that singbox and gateway share at least one common network
    # Get singbox networks
    singbox_networks=$(yq eval '.services.singbox.networks[]' "$NODE_COMPOSE")
    
    # Get gateway networks from node compose
    gateway_networks=$(yq eval '.services.gateway.networks[]' "$NODE_COMPOSE")
    
    # Check for common networks
    common_count=0
    for net in $singbox_networks; do
        if echo "$gateway_networks" | grep -q "$net"; then
            ((common_count++))
        fi
    done
    
    # Should have at least 1 common network (actually should be 2)
    [ "$common_count" -ge 1 ]
}

@test "Property 7: Singbox can reference gateway by container name" {
    # Verify gateway has a container_name set
    gateway_name=$(yq eval '.services.gateway.container_name' "$NODE_COMPOSE")
    [ -n "$gateway_name" ]
    [ "$gateway_name" != "null" ]
    
    # Verify it's the expected name
    [ "$gateway_name" = "sui-gateway" ]
}
