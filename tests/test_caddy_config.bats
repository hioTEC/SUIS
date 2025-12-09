#!/usr/bin/env bats

# Feature: singbox-443-fallback, Property 8: Template configuration correctness (Caddy)
# Validates: Requirements 7.2, 7.3

setup() {
    # Load the template
    TEMPLATE_FILE="node/templates/Caddyfile.template"
    TEST_OUTPUT_DIR="$(mktemp -d)"
    TEST_CONFIG="${TEST_OUTPUT_DIR}/Caddyfile"
}

teardown() {
    rm -rf "$TEST_OUTPUT_DIR"
}

# Helper function to generate Caddyfile with random values
generate_caddyfile() {
    local master_domain="$1"
    local node_domain="$2"
    local path_prefix="$3"
    local admin_pass="$4"
    
    # Simple template substitution (Go template style)
    sed -e "s/{{\.MasterDomain}}/${master_domain}/g" \
        -e "s/{{\.NodeDomain}}/${node_domain}/g" \
        -e "s/{{\.PathPrefix}}/${path_prefix}/g" \
        -e "s/{{\.AdGuardAdminPass}}/${admin_pass}/g" \
        "$TEMPLATE_FILE" > "$TEST_CONFIG"
}

@test "Property 8: Generated Caddyfile uses HTTP-only on port 80" {
    # Test with various random inputs
    for i in {1..10}; do
        master_domain="master${i}.example.com"
        node_domain="node${i}.example.com"
        path_prefix="api${i}"
        admin_pass="pass${RANDOM}"
        
        generate_caddyfile "$master_domain" "$node_domain" "$path_prefix" "$admin_pass"
        
        # Verify HTTP protocol is explicitly specified
        run grep -q "http://${master_domain}:80" "$TEST_CONFIG"
        [ "$status" -eq 0 ]
        
        run grep -q "http://${node_domain}:80" "$TEST_CONFIG"
        [ "$status" -eq 0 ]
        
        # Verify no HTTPS configuration (no tls directive)
        run grep -i "tls" "$TEST_CONFIG"
        [ "$status" -ne 0 ]
        
        # Verify no automatic HTTPS (no https:// scheme)
        run grep "https://" "$TEST_CONFIG"
        [ "$status" -ne 0 ]
    done
}

@test "Property 8: Caddyfile contains reverse proxy configuration" {
    # Test that reverse proxy is properly configured
    for i in {1..5}; do
        master_domain="test${i}.example.com"
        node_domain="node${i}.test.com"
        path_prefix="test${i}"
        admin_pass="testpass${i}"
        
        generate_caddyfile "$master_domain" "$node_domain" "$path_prefix" "$admin_pass"
        
        # Verify reverse_proxy directives exist
        proxy_count=$(grep -c "reverse_proxy" "$TEST_CONFIG")
        [ "$proxy_count" -gt 0 ]
        
        # Verify master reverse proxy
        run grep -q "reverse_proxy sui-master:5000" "$TEST_CONFIG"
        [ "$status" -eq 0 ]
    done
}

@test "Property 8: Template variable substitution works correctly" {
    # Test that all template variables are substituted
    for i in {1..5}; do
        master_domain="master${i}.local"
        node_domain="node${i}.local"
        path_prefix="prefix${i}"
        admin_pass="admin${i}"
        
        generate_caddyfile "$master_domain" "$node_domain" "$path_prefix" "$admin_pass"
        
        # Verify no template variables remain
        run grep "{{" "$TEST_CONFIG"
        [ "$status" -ne 0 ]
        
        run grep "}}" "$TEST_CONFIG"
        [ "$status" -ne 0 ]
        
        # Verify actual values are present
        run grep -q "$master_domain" "$TEST_CONFIG"
        [ "$status" -eq 0 ]
        
        run grep -q "$node_domain" "$TEST_CONFIG"
        [ "$status" -eq 0 ]
    done
}

@test "Property 8: Port 80 is explicitly configured for both domains" {
    # Verify port 80 is used for all domain configurations
    for i in {1..10}; do
        master_domain="m${i}.test.com"
        node_domain="n${i}.test.com"
        path_prefix="p${i}"
        admin_pass="a${i}"
        
        generate_caddyfile "$master_domain" "$node_domain" "$path_prefix" "$admin_pass"
        
        # Count port 80 occurrences (should be at least 2: master + node)
        port_80_count=$(grep -c ":80" "$TEST_CONFIG")
        [ "$port_80_count" -ge 2 ]
        
        # Verify no port 443 configuration
        run grep ":443" "$TEST_CONFIG"
        [ "$status" -ne 0 ]
    done
}
