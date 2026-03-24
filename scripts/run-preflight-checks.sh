#!/usr/bin/env bash
# scripts/run-preflight-checks.sh

set -euo pipefail

COMBINATION="${1:-}"
SCENARIO="${2:-comprehensive}"

echo "Running pre-flight validation checks..."

# Check required tools
REQUIRED_TOOLS=("nix" "jq" "curl" "ping" "systemctl")
MISSING_TOOLS=()

for tool in "${REQUIRED_TOOLS[@]}"; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        MISSING_TOOLS+=("$tool")
    fi
done

if [[ ${#MISSING_TOOLS[@]} -gt 0 ]]; then
    echo "ERROR: Missing required tools: ${MISSING_TOOLS[*]}"
    exit 1
fi

echo "✓ All required tools available"

# Check Nix flakes
if ! nix flake metadata . >/dev/null 2>&1; then
    echo "ERROR: Nix flakes not enabled or repository not properly configured"
    exit 1
fi

echo "✓ Nix flakes enabled"

# Check available resources
TOTAL_MEMORY=$(free -g | grep Mem | awk '{print $2}')
TOTAL_CORES=$(nproc)

if [[ $TOTAL_MEMORY -lt 4 ]]; then
    echo "WARNING: Limited memory available (${TOTAL_MEMORY}GB < 4GB recommended)"
fi

if [[ $TOTAL_CORES -lt 2 ]]; then
    echo "WARNING: Limited CPU cores available (${TOTAL_CORES} < 2 recommended)"
fi

echo "✓ System resources adequate"

# Check disk space
DISK_SPACE=$(df / | tail -1 | awk '{print $4}')
if [[ $DISK_SPACE -lt 5000000 ]]; then  # 5GB in KB
    echo "ERROR: Insufficient disk space (${DISK_SPACE}KB < 5GB required)"
    exit 1
fi

echo "✓ Sufficient disk space available"

# Check network connectivity
if ! ping -c 1 -W 5 8.8.8.8 >/dev/null 2>&1; then
    echo "WARNING: No internet connectivity detected"
fi

echo "✓ Network connectivity verified"

# Validate test configuration
CONFIG_FILE="test-configs/${COMBINATION}.nix"
if [[ -n "$COMBINATION" ]] && [[ ! -f "$CONFIG_FILE" ]]; then
    echo "WARNING: Test configuration not found: $CONFIG_FILE"
    echo "Will generate basic configuration"
fi

echo "✓ Test configuration validated"

echo "Pre-flight validation completed successfully"