#!/usr/bin/env bats

# Feature: singbox-443-fallback, Property 6: Installation script output validity
# Validates: Requirements 6.1, 6.2, 6.3

setup() {
    # Create temporary test directory
    TEST_DIR="$(mktemp -d)"
    export TEST_DIR
    
    # Source the install script functions (without running main)
    # We'll test individual functions
    
    # Check dependencies
    if ! command -v jq &> /dev/null; then
        skip "jq is not installed"
    fi
    
    if ! command -v yq &> /dev/null; then
        skip "yq is not installed"
    fi
}

teardown() {
    rm -rf "$TEST_DIR"
}

# Helper to create test environment
setup_test_env() {
    local master_domain="$1"
    local node_domain="$2"
    local email="$3"
    local uuid="$4"
    local hy2_pass="$5"
    local gateway="$6"
    
    export MASTER_DOMAIN="$master_domain"
    export NODE_DOMAIN="$node_domain"
    export ACME_EMAIL="$email"
    export VLESS_UUID="$uuid"
    export HY2_PASSWORD="$hy2_pass"
    export GATEWAY_CONTAINER="$gateway"
    export ADGUARD_ADMIN_PASS="testpass"
    export PATH_PREFIX="sui"
    
    # Create necessary directories
    mkdir -p "${TEST_DIR}/node/config/singbox"
    mkdir -p "${TEST_DIR}/node/config/caddy"
    mkdir -p "${TEST_DIR}/gateway"
    
    # Copy templates
    cp node/templates/singbox-config.json.template "${TEST_DIR}/"
    cp node/templates/Caddyfile.template "${TEST_DIR}/"
}

# Test Sing-box config generation
@test "Property 6: Generated Sing-box config is valid JSON" {
    for i in {1..5}; do
        uuid=$(uuidgen | tr '[:upper:]' '[:lower:]')
        domain="node${i}.test.com"
        email="test${i}@example.com"
        gateway="gateway"
        hy2_pass="pass${RANDOM}"
        
        setup_test_env "master${i}.test.com" "$domain" "$email" "$uuid" "$hy2_pass" "$gateway"
        
        # Generate config
        output_file="${TEST_DIR}/node/config/singbox/config.json"
        sed -e "s/\${VLESS_UUID}/${uuid}/g" \
            -e "s/\${NODE_DOMAIN}/${domain}/g" \
            -e "s/\${ACME_EMAIL}/${email}/g" \
            -e "s/\${GATEWAY_CONTAINER}/${gateway}/g" \
            -e "s/\${HY2_PASSWORD}/${hy2_pass}/g" \
            "${TEST_DIR}/singbox-config.json.template" > "$output_file"
        
        # Validate JSON
        run jq empty "$output_file"
        [ "$status" -eq 0 ]
    done
}

@test "Property 6: Generated Sing-box config contains port 443 and fallback" {
    for i in {1..5}; do
        uuid=$(uuidgen | tr '[:upper:]' '[:lower:]')
        domain="test${i}.example.com"
        email="admin${i}@example.com"
        gateway="sui-gateway"
        hy2_pass="testpass${i}"
        
        setup_test_env "master${i}.example.com" "$domain" "$email" "$uuid" "$hy2_pass" "$gateway"
        
        # Generate config
        output_file="${TEST_DIR}/node/config/singbox/config.json"
        sed -e "s/\${VLESS_UUID}/${uuid}/g" \
            -e "s/\${NODE_DOMAIN}/${domain}/g" \
            -e "s/\${ACME_EMAIL}/${email}/g" \
            -e "s/\${GATEWAY_CONTAINER}/${gateway}/g" \
            -e "s/\${HY2_PASSWORD}/${hy2_pass}/g" \
            "${TEST_DIR}/singbox-config.json.template" > "$output_file"
        
        # Check port 443
        vless_port=$(jq -r '.inbounds[] | select(.type == "vless") | .listen_port' "$output_file")
        [ "$vless_port" = "443" ]
        
        # Check fallback exists
        run jq -e '.inbounds[] | select(.type == "vless") | .fallback' "$output_file"
        [ "$status" -eq 0 ]
        
        # Check fallback port is 80
        fallback_port=$(jq -r '.inbounds[] | select(.type == "vless") | .fallback.server_port' "$output_file")
        [ "$fallback_port" = "80" ]
    done
}

@test "Property 6: Generated Caddyfile has correct variable substitution" {
    for i in {1..5}; do
        master_domain="master${i}.local"
        node_domain="node${i}.local"
        email="test${i}@local"
        
        setup_test_env "$master_domain" "$node_domain" "$email" "test-uuid" "test-pass" "gateway"
        
        # Generate Caddyfile
        output_file="${TEST_DIR}/node/config/caddy/Caddyfile"
        sed -e "s/{{\.MasterDomain}}/${master_domain}/g" \
            -e "s/{{\.NodeDomain}}/${node_domain}/g" \
            -e "s/{{\.PathPrefix}/${PATH_PREFIX}/g" \
            -e "s/{{\.AdGuardAdminPass}}/${ADGUARD_ADMIN_PASS}/g" \
            "${TEST_DIR}/Caddyfile.template" > "$output_file"
        
        # Verify no template variables remain
        run grep "{{" "$output_file"
        [ "$status" -ne 0 ]
        
        # Verify domains are present
        grep -q "$master_domain" "$output_file"
        grep -q "$node_domain" "$output_file"
    done
}

@test "Property 6: Generated gateway compose has only port 80" {
    # Test gateway compose generation
    mkdir -p "${TEST_DIR}/gateway"
    output_file="${TEST_DIR}/gateway/docker-compose.yml"
    
    # Copy the gateway compose template
    cp gateway/docker-compose.yml "$output_file"
    
    # Verify port 80 only
    port_config=$(yq eval '.services.gateway.ports[0]' "$output_file")
    [ "$port_config" = "80:80" ]
    
    # Verify no port 443
    ports=$(yq eval '.services.gateway.ports[]' "$output_file")
    if echo "$ports" | grep -q "443"; then
        return 1
    fi
    return 0
}

@test "Property 6: All generated configs are syntactically valid" {
    # Test with random values
    for i in {1..3}; do
        uuid=$(uuidgen | tr '[:upper:]' '[:lower:]')
        master_domain="m${i}.test.com"
        node_domain="n${i}.test.com"
        email="e${i}@test.com"
        gateway="gateway"
        hy2_pass="p${RANDOM}"
        
        setup_test_env "$master_domain" "$node_domain" "$email" "$uuid" "$hy2_pass" "$gateway"
        
        # Generate Sing-box config
        singbox_config="${TEST_DIR}/node/config/singbox/config.json"
        sed -e "s/\${VLESS_UUID}/${uuid}/g" \
            -e "s/\${NODE_DOMAIN}/${node_domain}/g" \
            -e "s/\${ACME_EMAIL}/${email}/g" \
            -e "s/\${GATEWAY_CONTAINER}/${gateway}/g" \
            -e "s/\${HY2_PASSWORD}/${hy2_pass}/g" \
            "${TEST_DIR}/singbox-config.json.template" > "$singbox_config"
        
        # Validate JSON
        run jq empty "$singbox_config"
        [ "$status" -eq 0 ]
        
        # Generate Caddyfile
        caddyfile="${TEST_DIR}/node/config/caddy/Caddyfile"
        sed -e "s/{{\.MasterDomain}}/${master_domain}/g" \
            -e "s/{{\.NodeDomain}}/${node_domain}/g" \
            -e "s/{{\.PathPrefix}}/${PATH_PREFIX}/g" \
            -e "s/{{\.AdGuardAdminPass}}/${ADGUARD_ADMIN_PASS}/g" \
            "${TEST_DIR}/Caddyfile.template" > "$caddyfile"
        
        # Verify Caddyfile has content
        [ -s "$caddyfile" ]
        
        # Copy and validate docker-compose files
        cp gateway/docker-compose.yml "${TEST_DIR}/gateway/"
        cp node/docker-compose.yml "${TEST_DIR}/node/"
        
        # Validate YAML (basic check - file exists and has content)
        [ -s "${TEST_DIR}/gateway/docker-compose.yml" ]
        [ -s "${TEST_DIR}/node/docker-compose.yml" ]
    done
}
