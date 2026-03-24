# Test Categorization and Tagging System

## Test Metadata Schema

```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "title": "NixOS Gateway Test Metadata",
  "description": "Metadata schema for categorizing and tagging tests",
  "type": "object",
  "properties": {
    "test": {
      "type": "object",
      "properties": {
        "id": {"type": "string", "description": "Unique test identifier"},
        "name": {"type": "string", "description": "Human-readable test name"},
        "description": {"type": "string", "description": "Detailed test description"},
        "file": {"type": "string", "description": "Test file path"}
      },
      "required": ["id", "name", "file"]
    },
    "categories": {
      "type": "object",
      "properties": {
        "feature": {
          "type": "string",
          "enum": ["core", "networking", "dns", "dhcp", "security", "firewall", "monitoring", "vpn", "routing", "load-balancing", "backup", "ui", "api", "advanced"],
          "description": "Primary feature being tested"
        },
        "scope": {
          "type": "string",
          "enum": ["unit", "integration", "system", "performance", "security", "reliability"],
          "description": "Test scope and type"
        },
        "complexity": {
          "type": "string",
          "enum": ["simple", "medium", "complex"],
          "description": "Test complexity level"
        }
      },
      "required": ["feature", "scope"]
    },
    "requirements": {
      "type": "object",
      "properties": {
        "resources": {
          "type": "object",
          "properties": {
            "memory_gb": {"type": "integer", "minimum": 1},
            "cpu_cores": {"type": "integer", "minimum": 1},
            "disk_gb": {"type": "integer", "minimum": 1},
            "network_bandwidth_mbps": {"type": "integer", "minimum": 1}
          }
        },
        "dependencies": {
          "type": "array",
          "items": {"type": "string"},
          "description": "Other tests that must pass first"
        },
        "environment": {
          "type": "array",
          "items": {
            "type": "string",
            "enum": ["internet", "isolated", "multi-node", "external-services"]
          },
          "description": "Required environment capabilities"
        },
        "duration_minutes": {"type": "integer", "minimum": 1}
      }
    },
    "tags": {
      "type": "array",
      "items": {"type": "string"},
      "description": "Additional categorization tags"
    },
    "evidence": {
      "type": "object",
      "properties": {
        "required_collectors": {
          "type": "array",
          "items": {"type": "string"},
          "description": "Evidence collectors that must run"
        },
        "validation_criteria": {
          "type": "object",
          "description": "Criteria for evidence validation"
        }
      }
    },
    "metadata": {
      "type": "object",
      "properties": {
        "author": {"type": "string"},
        "created": {"type": "string", "format": "date"},
        "last_modified": {"type": "string", "format": "date"},
        "version": {"type": "string"},
        "priority": {
          "type": "string",
          "enum": ["critical", "high", "medium", "low"]
        },
        "stability": {
          "type": "string",
          "enum": ["stable", "unstable", "experimental"]
        }
      }
    }
  },
  "required": ["test", "categories"]
}
```

## Test Registry System

```bash
#!/usr/bin/env bash
# scripts/manage-test-registry.sh

set -euo pipefail

REGISTRY_FILE="${TEST_REGISTRY_FILE:-test-registry.json}"
ACTION="${1:-list}"

case "$ACTION" in
    "init")
        # Initialize empty registry
        cat > "$REGISTRY_FILE" << EOF
{
  "registry_version": "1.0",
  "created": "$(date -Iseconds)",
  "last_updated": "$(date -Iseconds)",
  "tests": {}
}
EOF
        echo "Test registry initialized: $REGISTRY_FILE"
        ;;

    "register")
        TEST_FILE="$2"
        TEST_ID="$3"

        if [[ ! -f "$TEST_FILE" ]]; then
            echo "ERROR: Test file not found: $TEST_FILE"
            exit 1
        fi

        # Extract test metadata from comments
        TEST_NAME=$(grep -oP "(?<=# Feature: ).*" "$TEST_FILE" | head -1 || echo "Unknown")
        TEST_TAGS=$(grep -oP "(?<=# Tags: ).*" "$TEST_FILE" | head -1 || echo "")

        # Determine feature category from filename
        FEATURE=$(basename "$TEST_FILE" | sed 's/-test\.nix$//' | sed 's/.*-//' | sed 's/test$//')

        # Create test entry
        TEST_ENTRY=$(cat << EOF
{
  "test": {
    "id": "$TEST_ID",
    "name": "$TEST_NAME",
    "description": "Test for $TEST_NAME functionality",
    "file": "$TEST_FILE"
  },
  "categories": {
    "feature": "$FEATURE",
    "scope": "integration",
    "complexity": "medium"
  },
  "requirements": {
    "resources": {
      "memory_gb": 2,
      "cpu_cores": 2,
      "disk_gb": 10,
      "network_bandwidth_mbps": 100
    },
    "duration_minutes": 10
  },
  "tags": [$(echo "$TEST_TAGS" | sed 's/,/","/g' | sed 's/^/"/' | sed 's/$/"/' | sed 's/""/"/g')],
  "metadata": {
    "created": "$(date -I)",
    "version": "1.0",
    "priority": "medium",
    "stability": "stable"
  }
}
EOF
)

        # Add to registry
        jq --arg testId "$TEST_ID" --argjson testEntry "$TEST_ENTRY" \
           '.tests[$testId] = $testEntry | .last_updated = "'$(date -Iseconds)'"' \
           "$REGISTRY_FILE" > "${REGISTRY_FILE}.tmp"

        mv "${REGISTRY_FILE}.tmp" "$REGISTRY_FILE"
        echo "Test registered: $TEST_ID"
        ;;

    "list")
        echo "Registered tests:"
        jq -r '.tests | keys[]' "$REGISTRY_FILE" 2>/dev/null || echo "No tests registered"
        ;;

    "query")
        QUERY_TYPE="$2"
        QUERY_VALUE="$3"

        case "$QUERY_TYPE" in
            "feature")
                jq -r ".tests | to_entries[] | select(.value.categories.feature == \"$QUERY_VALUE\") | .key" "$REGISTRY_FILE"
                ;;
            "tag")
                jq -r ".tests | to_entries[] | select(.value.tags[]? == \"$QUERY_VALUE\") | .key" "$REGISTRY_FILE"
                ;;
            "priority")
                jq -r ".tests | to_entries[] | select(.value.metadata.priority == \"$QUERY_VALUE\") | .key" "$REGISTRY_FILE"
                ;;
        esac
        ;;

    "validate")
        # Validate registry against schema
        if command -v jsonschema >/dev/null 2>&1; then
            # This would validate against the schema
            echo "Registry validation not implemented yet"
        else
            echo "jsonschema not available, skipping validation"
        fi
        ;;

    *)
        echo "Usage: $0 {init|register|list|query|validate}"
        echo "  init - Initialize empty registry"
        echo "  register <test-file> <test-id> - Register a test"
        echo "  list - List all registered tests"
        echo "  query <type> <value> - Query tests by feature/tag/priority"
        echo "  validate - Validate registry"
        exit 1
        ;;
esac
```

## Test Selection and Filtering

```bash
#!/usr/bin/env bash
# scripts/select-tests.sh

set -euo pipefail

REGISTRY_FILE="${TEST_REGISTRY_FILE:-test-registry.json}"
SCOPE="${1:-core}"
FEATURE="${2:-all}"

echo "Selecting tests for scope: $SCOPE, feature: $FEATURE"

# Initialize selected tests array
SELECTED_TESTS=()

case "$SCOPE" in
    "core")
        # Core functionality tests
        SELECTED_TESTS+=($(./scripts/manage-test-registry.sh query feature core))
        SELECTED_TESTS+=($(./scripts/manage-test-registry.sh query feature networking))
        ;;

    "networking")
        # All networking-related tests
        SELECTED_TESTS+=($(./scripts/manage-test-registry.sh query feature networking))
        SELECTED_TESTS+=($(./scripts/manage-test-registry.sh query feature dns))
        SELECTED_TESTS+=($(./scripts/manage-test-registry.sh query feature dhcp))
        ;;

    "security")
        # Security-related tests
        SELECTED_TESTS+=($(./scripts/manage-test-registry.sh query feature security))
        SELECTED_TESTS+=($(./scripts/manage-test-registry.sh query feature firewall))
        ;;

    "monitoring")
        # Monitoring and observability tests
        SELECTED_TESTS+=($(./scripts/manage-test-registry.sh query feature monitoring))
        ;;

    "vpn")
        # VPN and routing tests
        SELECTED_TESTS+=($(./scripts/manage-test-registry.sh query feature vpn))
        SELECTED_TESTS+=($(./scripts/manage-test-registry.sh query feature routing))
        ;;

    "advanced")
        # Advanced features
        SELECTED_TESTS+=($(./scripts/manage-test-registry.sh query feature load-balancing))
        SELECTED_TESTS+=($(./scripts/manage-test-registry.sh query feature backup))
        SELECTED_TESTS+=($(./scripts/manage-test-registry.sh query feature api))
        SELECTED_TESTS+=($(./scripts/manage-test-registry.sh query feature advanced))
        ;;

    "full")
        # All tests
        SELECTED_TESTS+=($(./scripts/manage-test-registry.sh list))
        ;;

    "feature")
        if [[ "$FEATURE" == "all" ]]; then
            SELECTED_TESTS+=($(./scripts/manage-test-registry.sh list))
        else
            SELECTED_TESTS+=($(./scripts/manage-test-registry.sh query feature "$FEATURE"))
        fi
        ;;
esac

# Remove duplicates and sort
SELECTED_TESTS=($(echo "${SELECTED_TESTS[@]}" | tr ' ' '\n' | sort | uniq))

echo "Selected ${#SELECTED_TESTS[@]} tests:"
printf '%s\n' "${SELECTED_TESTS[@]}"

# Export for use by other scripts
export SELECTED_TESTS="${SELECTED_TESTS[*]}"

# Generate test execution plan
cat > test-execution-plan.json << EOF
{
  "scope": "$SCOPE",
  "feature": "$FEATURE",
  "selected_tests": [$(printf '"%s",' "${SELECTED_TESTS[@]}" | sed 's/,$//')],
  "total_tests": ${#SELECTED_TESTS[@]},
  "generated": "$(date -Iseconds)"
}
EOF

echo "Test execution plan saved to: test-execution-plan.json"
```

## Test Prioritization and Ordering

```bash
#!/usr/bin/env bash
# scripts/prioritize-tests.sh

set -euo pipefail

REGISTRY_FILE="${TEST_REGISTRY_FILE:-test-registry.json}"
EXECUTION_PLAN="test-execution-plan.json"

echo "Prioritizing tests based on dependencies and requirements..."

# Read selected tests
SELECTED_TESTS=($(jq -r '.selected_tests[]' "$EXECUTION_PLAN"))

# Create dependency graph
declare -A DEPENDENCIES
declare -A PRIORITIES

for test_id in "${SELECTED_TESTS[@]}"; do
    # Get test dependencies
    deps=$(jq -r ".tests[\"$test_id\"].requirements.dependencies[]?" "$REGISTRY_FILE" 2>/dev/null || echo "")
    DEPENDENCIES["$test_id"]="$deps"

    # Get test priority
    priority=$(jq -r ".tests[\"$test_id\"].metadata.priority" "$REGISTRY_FILE" 2>/dev/null || echo "medium")
    PRIORITIES["$test_id"]="$priority"
done

# Topological sort for dependencies
ORDERED_TESTS=()
VISITED=()
RECURSION_STACK=()

function visit() {
    local test_id="$1"

    # Check for cycles
    for item in "${RECURSION_STACK[@]}"; do
        if [[ "$item" == "$test_id" ]]; then
            echo "ERROR: Circular dependency detected involving $test_id"
            exit 1
        fi
    done

    RECURSION_STACK+=("$test_id")

    # Visit dependencies first
    for dep in ${DEPENDENCIES["$test_id"]}; do
        if [[ -n "$dep" ]] && [[ ! " ${VISITED[@]} " =~ " $dep " ]]; then
            visit "$dep"
        fi
    done

    # Remove from recursion stack
    RECURSION_STACK=("${RECURSION_STACK[@]/$test_id}")

    # Mark as visited and add to ordered list
    VISITED+=("$test_id")
    ORDERED_TESTS+=("$test_id")
}

# Visit all tests
for test_id in "${SELECTED_TESTS[@]}"; do
    if [[ ! " ${VISITED[@]} " =~ " $test_id " ]]; then
        visit "$test_id"
    fi
done

# Apply priority ordering within same dependency level
PRIORITY_ORDER=("critical" "high" "medium" "low")
FINAL_ORDER=()

for priority in "${PRIORITY_ORDER[@]}"; do
    for test_id in "${ORDERED_TESTS[@]}"; do
        if [[ "${PRIORITIES[$test_id]}" == "$priority" ]]; then
            FINAL_ORDER+=("$test_id")
        fi
    done
done

# Update execution plan with ordered tests
jq --argjson orderedTests "$(printf '%s\n' "${FINAL_ORDER[@]}" | jq -R . | jq -s .)" \
   '.ordered_tests = $orderedTests' \
   "$EXECUTION_PLAN" > "${EXECUTION_PLAN}.tmp"

mv "${EXECUTION_PLAN}.tmp" "$EXECUTION_PLAN"

echo "Tests prioritized and ordered:"
for i in "${!FINAL_ORDER[@]}"; do
    test_id="${FINAL_ORDER[$i]}"
    priority="${PRIORITIES[$test_id]}"
    echo "$((i+1)). $test_id (priority: $priority)"
done

echo "Updated execution plan saved to: $EXECUTION_PLAN"
```

## Test Resource Allocation

```bash
#!/usr/bin/env bash
# scripts/allocate-test-resources.sh

set -euo pipefail

EXECUTION_PLAN="test-execution-plan.json"
REGISTRY_FILE="${TEST_REGISTRY_FILE:-test-registry.json}"

echo "Allocating resources for test execution..."

# Get ordered tests
ORDERED_TESTS=($(jq -r '.ordered_tests[]' "$EXECUTION_PLAN"))

# Calculate total resource requirements
TOTAL_MEMORY=0
TOTAL_CORES=0
TOTAL_DISK=0
MAX_DURATION=0

RESOURCE_ALLOCATIONS=()

for test_id in "${ORDERED_TESTS[@]}"; do
    # Get resource requirements
    memory=$(jq -r ".tests[\"$test_id\"].requirements.resources.memory_gb" "$REGISTRY_FILE" 2>/dev/null || echo "2")
    cores=$(jq -r ".tests[\"$test_id\"].requirements.resources.cpu_cores" "$REGISTRY_FILE" 2>/dev/null || echo "1")
    disk=$(jq -r ".tests[\"$test_id\"].requirements.resources.disk_gb" "$REGISTRY_FILE" 2>/dev/null || echo "5")
    duration=$(jq -r ".tests[\"$test_id\"].requirements.duration_minutes" "$REGISTRY_FILE" 2>/dev/null || echo "5")

    # Accumulate totals
    TOTAL_MEMORY=$((TOTAL_MEMORY + memory))
    TOTAL_CORES=$((TOTAL_CORES + cores))
    TOTAL_DISK=$((TOTAL_DISK + disk))
    if [[ $duration -gt $MAX_DURATION ]]; then
        MAX_DURATION=$duration
    fi

    # Record allocation
    RESOURCE_ALLOCATIONS+=("{\"test\":\"$test_id\",\"memory_gb\":$memory,\"cpu_cores\":$cores,\"disk_gb\":$disk,\"duration_min\":$duration}")
done

# Check available system resources
AVAILABLE_MEMORY=$(free -g | grep Mem | awk '{print $2}')
AVAILABLE_CORES=$(nproc)
AVAILABLE_DISK=$(df / | tail -1 | awk '{print $4}')  # in KB
AVAILABLE_DISK_GB=$((AVAILABLE_DISK / 1024 / 1024))

echo "Resource Requirements Summary:"
echo "  Total Memory: ${TOTAL_MEMORY}GB (Available: ${AVAILABLE_MEMORY}GB)"
echo "  Total CPU Cores: ${TOTAL_CORES} (Available: ${AVAILABLE_CORES})"
echo "  Total Disk: ${TOTAL_DISK}GB (Available: ${AVAILABLE_DISK_GB}GB)"
echo "  Max Duration: ${MAX_DURATION} minutes"

# Check if requirements can be met
ISSUES=()

if [[ $TOTAL_MEMORY -gt $AVAILABLE_MEMORY ]]; then
    ISSUES+=("Insufficient memory: ${TOTAL_MEMORY}GB required, ${AVAILABLE_MEMORY}GB available")
fi

if [[ $TOTAL_CORES -gt $AVAILABLE_CORES ]]; then
    ISSUES+=("Insufficient CPU cores: ${TOTAL_CORES} required, ${AVAILABLE_CORES} available")
fi

if [[ $TOTAL_DISK -gt $AVAILABLE_DISK_GB ]]; then
    ISSUES+=("Insufficient disk space: ${TOTAL_DISK}GB required, ${AVAILABLE_DISK_GB}GB available")
fi

# Update execution plan with resource information
jq --argjson allocations "$(printf '%s,' "${RESOURCE_ALLOCATIONS[@]}" | sed 's/,$//' | jq -s .)" \
   --arg totalMemory "$TOTAL_MEMORY" \
   --arg totalCores "$TOTAL_CORES" \
   --arg totalDisk "$TOTAL_DISK" \
   --arg maxDuration "$MAX_DURATION" \
   --argjson issues "$(printf '"%s",' "${ISSUES[@]}" | sed 's/,$//' | jq -s .)" \
   '.resources = {
     "total_required": {
       "memory_gb": ($totalMemory | tonumber),
       "cpu_cores": ($totalCores | tonumber),
       "disk_gb": ($totalDisk | tonumber),
       "max_duration_minutes": ($maxDuration | tonumber)
     },
     "allocations": $allocations,
     "issues": $issues
   }' \
   "$EXECUTION_PLAN" > "${EXECUTION_PLAN}.tmp"

mv "${EXECUTION_PLAN}.tmp" "$EXECUTION_PLAN"

if [[ ${#ISSUES[@]} -gt 0 ]]; then
    echo "⚠️  Resource allocation issues detected:"
    printf '  - %s\n' "${ISSUES[@]}"
    echo "Consider running tests serially or on a more powerful system."
else
    echo "✅ All resource requirements can be met."
fi

echo "Resource allocation plan saved to: $EXECUTION_PLAN"
```

This test categorization and tagging system provides:

1. **Structured Metadata**: Comprehensive test classification and requirements
2. **Dependency Management**: Automatic test ordering based on dependencies
3. **Resource Planning**: Resource requirement calculation and availability checking
4. **Flexible Selection**: Query-based test selection by various criteria
5. **Priority Handling**: Test execution ordering by priority and dependencies