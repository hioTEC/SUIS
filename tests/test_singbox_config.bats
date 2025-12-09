#!/usr/bin/env bats

# Feature: singbox-443-fallback, Property 5: Fallback configuration completeness
# Validates: Requirements 5.1, 5.2, 5.3, 5.4

setup() {
    # Load the template
    TEMPLATE_FILE="node/templates/singbox-config.json.template"
    TEST_OUTPUT_DIR="$(mktemp -d)"
    TEST_CONFIG="${TEST_OUTPUT_DIR}/config.json"
}

teardown() {
    rm -rf "$TEST_OUTPUT_DIR"
}

# Helper function to generate config with random values
generate_config() {
    local uuid="$1"
    local domain="$2"
    local email="$3"
    local gateway="$4"
    local hy2_pass="$5"
    
    sed -e "s/\${VLESS_UUID}/${uuid}/g" \
        -e "s/\${NODE_DOMAIN}/${domain}/g" \
        -e "s/\${ACME_EMAIL}/${email}/g" \
        -e "s/\${GATEWAY_CONTAINER}/${gateway}/g" \
        -e "s/\${HY2_PASSWORD}/${hy2_pass}/g" \
        "$TEMPLATE_FILE" > "$TEST_CONFIG"
}

@test "Property 5: Generated Sing-box config contains fallback section" {
    # Test with various random inputs
    for i in {1..10}; do
        uuid=$(uuidgen | tr '[:upper:]' '[:lower:]')
        domain="node${i}.example.com"
        email="admin${i}@example.com"
        gateway="gateway-${i}"
        hy2_pass="pass${RANDOM}"
        
        generate_config "$uuid" "$domain" "$email" "$gateway" "$hy2_pass"
        
        # Verify JSON is valid
        run jq empty "$TEST_CONFIG"
        [ "$status" -eq 0 ]
        
        # Verify fallback section exists in VLESS inbound
        run jq -e '.inbounds[] | select(.type == "vless") | .fallback' "$TEST_CONFIG"
        [ "$status" -eq 0 ]
        
        # Verify fallback server is set to gateway container
        fallback_server=$(jq -r '.inbounds[] | select(.type == "vless") | .fallback.server' "$TEST_CONFIG")
        [ "$fallback_server" = "$gateway" ]
        
        # Verify fallback port is 80
        fallback_port=$(jq -r '.inbounds[] | select(.type == "vless") | .fallback.server_port' "$TEST_CONFIG")
        [ "$fallback_port" = "80" ]
    done
}

@test "Property 5: Fallback configuration is complete with all required fields" {
    # Test that fallback has both server and server_port
    for i in {1..5}; do
        uuid=$(uuidgen | tr '[:upper:]' '[:lower:]')
        domain="test${i}.example.com"
        email="test${i}@example.com"
        gateway="gateway"
        hy2_pass="testpass${i}"
        
        generate_config "$uuid" "$domain" "$email" "$gateway" "$hy2_pass"
        
        # Check fallback object has exactly the required fields
        run jq -e '.inbounds[] | select(.type == "vless") | .fallback | has("server") and has("server_port")' "$TEST_CONFIG"
        [ "$status" -eq 0 ]
        
        # Verify output is "true"
        result=$(jq -r '.inbounds[] | select(.type == "vless") | .fallback | has("server") and has("server_port")' "$TEST_CONFIG")
        [ "$result" = "true" ]
    done
}

@test "Property 5: VLESS inbound on port 443 with fallback" {
    # Verify VLESS is on port 443 and has fallback
    for i in {1..5}; do
        uuid=$(uuidgen | tr '[:upper:]' '[:lower:]')
        domain="node${i}.test.com"
        email="admin${i}@test.com"
        gateway="gateway"
        hy2_pass="pass${i}"
        
        generate_config "$uuid" "$domain" "$email" "$gateway" "$hy2_pass"
        
        # Verify VLESS inbound is on port 443
        vless_port=$(jq -r '.inbounds[] | select(.type == "vless") | .listen_port' "$TEST_CONFIG")
        [ "$vless_port" = "443" ]
        
        # Verify it has fallback configured
        run jq -e '.inbounds[] | select(.type == "vless" and .listen_port == 443) | .fallback' "$TEST_CONFIG"
        [ "$status" -eq 0 ]
    done
}
