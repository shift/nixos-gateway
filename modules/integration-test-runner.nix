{ tests, modules, dependencies }:

let
  inherit (import <nixpkgs> {}) stdenv lib;

in stdenv.mkDerivation {
  name = "integration-test-runner";

  src = ./.;

  buildInputs = with import <nixpkgs> {}; [
    bash
    curl
    jq
    nix
    systemd
  ];

  installPhase = ''
    mkdir -p $out/bin
    cat > $out/bin/integration-test-runner << 'EOF'
    #!/bin/bash
    set -euo pipefail

    # Configuration
    MODULES="${lib.concatStringsSep " " modules}"
    LOG_DIR="/var/lib/task-verification/logs"

    log() {
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] INTEGRATION: $*" | tee -a "$LOG_DIR/integration-tests.log"
    }

    # Test module compatibility
    test_module_compatibility() {
        local module="$1"
        log "Testing module compatibility: $module"

        # Check if module can be loaded
        if nix-instantiate --eval '<nixpkgs/nixos>' -A "config.services.gateway.${module}.enable" >/dev/null 2>&1; then
            log "Module $module is compatible"
            return 0
        else
            log "Module $module has compatibility issues"
            return 1
        fi
    }

    # Test service integration
    test_service_integration() {
        local service="$1"
        log "Testing service integration: $service"

        # Check if service starts successfully
        if systemctl is-enabled "$service" >/dev/null 2>&1; then
            log "Service $service is properly configured"
            return 0
        else
            log "Service $service configuration issue"
            return 1
        fi
    }

    # Test API integration
    test_api_integration() {
        local endpoint="$1"
        log "Testing API integration: $endpoint"

        if curl -s -f "$endpoint" >/dev/null 2>&1; then
            log "API endpoint $endpoint is accessible"
            return 0
        else
            log "API endpoint $endpoint is not accessible"
            return 1
        fi
    }

    # Test module dependencies
    test_module_dependencies() {
        local module="$1"
        local deps="${dependencies[$module]}"

        if [[ -n "$deps" ]]; then
            log "Testing dependencies for $module: $deps"
            for dep in $deps; do
                if ! test_module_compatibility "$dep"; then
                    log "Dependency $dep for $module failed"
                    return 1
                fi
            done
        fi

        log "All dependencies for $module satisfied"
        return 0
    }

    # Main execution
    log "Integration Test Runner starting..."
    log "Modules to test: $MODULES"

    local passed=0
    local failed=0

    # Test each module
    for module in $MODULES; do
        log "Running integration tests for module: $module"

        if test_module_compatibility "$module" && \
           test_module_dependencies "$module" && \
           test_service_integration "gateway-${module}"; then
            log "Module $module integration tests PASSED"
            passed=$((passed + 1))
        else
            log "Module $module integration tests FAILED"
            failed=$((failed + 1))
        fi
    done

    # Test API integration
    if test_api_integration "http://127.0.0.1:8080/api/health"; then
        log "API integration tests PASSED"
        passed=$((passed + 1))
    else
        log "API integration tests FAILED"
        failed=$((failed + 1))
    fi

    log "Integration tests completed: $passed passed, $failed failed"

    if [[ $failed -gt 0 ]]; then
        exit 1
    fi
    EOF

    chmod +x $out/bin/integration-test-runner
  '';
}