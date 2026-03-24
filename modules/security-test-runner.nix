{ scans }:

let
  inherit (import <nixpkgs> {}) stdenv lib;

in stdenv.mkDerivation {
  name = "security-test-runner";

  src = ./.;

  buildInputs = with import <nixpkgs> {}; [
    bash
    findutils
    coreutils
  ];

  installPhase = ''
    mkdir -p $out/bin
    cat > $out/bin/security-test-runner << 'EOF'
    #!/bin/bash
    set -euo pipefail

    LOG_DIR="/var/lib/task-verification/logs"

    log() {
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] SECURITY: $*" | tee -a "$LOG_DIR/security-tests.log"
    }

    run_security_scan() {
        local name="$1"
        local description="$2"
        local command="$3"

        log "Running security scan: $name - $description"

        if eval "$command"; then
            log "Security scan $name PASSED"
            echo '{"name": "'$name'", "result": "passed", "timestamp": "'$(date -Iseconds)'"}' > "/var/lib/task-verification/security-results/${name}-result.json"
            return 0
        else
            log "Security scan $name FAILED"
            echo '{"name": "'$name'", "result": "failed", "timestamp": "'$(date -Iseconds)'"}' > "/var/lib/task-verification/security-results/${name}-result.json"
            return 1
        fi
    }

    # Main execution
    log "Security Test Runner starting..."

    mkdir -p "/var/lib/task-verification/security-results"

    local passed=0
    local failed=0

    # Run security scans
    ${lib.concatStringsSep "\n    " (map (scan: ''
    if run_security_scan "${scan.name}" "${scan.description}" "${lib.strings.escapeNixString scan.command}"; then
        passed=$((passed + 1))
    else
        failed=$((failed + 1))
    fi
    '') scans)}

    log "Security tests completed: $passed passed, $failed failed"

    if [[ $failed -gt 0 ]]; then
        exit 1
    fi
    EOF

    chmod +x $out/bin/security-test-runner
  '';
}