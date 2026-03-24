# Support Matrix Data Structure

## JSON Schema Definition

```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "title": "NixOS Gateway Support Matrix",
  "description": "Official support matrix for NixOS Gateway Framework feature combinations",
  "type": "object",
  "properties": {
    "metadata": {
      "type": "object",
      "properties": {
        "version": {"type": "string", "description": "Matrix version"},
        "lastUpdated": {"type": "string", "format": "date-time"},
        "frameworkVersion": {"type": "string", "description": "NixOS Gateway Framework version"},
        "totalCombinations": {"type": "integer"},
        "supportedCombinations": {"type": "integer"},
        "conditionallySupported": {"type": "integer"},
        "notSupported": {"type": "integer"}
      },
      "required": ["version", "lastUpdated", "frameworkVersion"]
    },
    "capabilities": {
      "type": "array",
      "description": "List of all available capabilities",
      "items": {
        "type": "object",
        "properties": {
          "id": {"type": "string", "description": "Unique capability identifier"},
          "name": {"type": "string", "description": "Human-readable name"},
          "category": {
            "type": "string",
            "enum": ["core", "networking", "security", "monitoring", "services", "infrastructure"]
          },
          "version": {"type": "string", "description": "Capability version"},
          "services": {
            "type": "array",
            "items": {"type": "string"},
            "description": "Systemd services associated with this capability"
          },
          "ports": {
            "type": "array",
            "items": {"type": "integer"},
            "description": "Network ports used by this capability"
          },
          "dependencies": {
            "type": "array",
            "items": {"type": "string"},
            "description": "Other capabilities this depends on"
          },
          "conflicts": {
            "type": "array",
            "items": {"type": "string"},
            "description": "Capabilities that conflict with this one"
          }
        },
        "required": ["id", "name", "category"]
      }
    },
    "combinations": {
      "type": "array",
      "description": "Tested feature combinations and their support status",
      "items": {
        "type": "object",
        "properties": {
          "id": {"type": "string", "description": "Unique combination identifier"},
          "name": {"type": "string", "description": "Human-readable combination name"},
          "capabilities": {
            "type": "array",
            "items": {"type": "string"},
            "description": "List of capability IDs in this combination"
          },
          "supportLevel": {
            "type": "string",
            "enum": ["fully_supported", "conditionally_supported", "not_supported"],
            "description": "Official support level"
          },
          "supportStatus": {
            "type": "object",
            "properties": {
              "productionReady": {"type": "boolean"},
              "customerSupported": {"type": "boolean"},
              "documentationComplete": {"type": "boolean"},
              "automatedTesting": {"type": "boolean"}
            }
          },
          "conditions": {
            "type": "array",
            "items": {"type": "string"},
            "description": "Conditions for conditional support"
          },
          "limitations": {
            "type": "array",
            "items": {"type": "string"},
            "description": "Known limitations"
          },
          "testResults": {
            "type": "object",
            "properties": {
              "lastTested": {"type": "string", "format": "date"},
              "testSuite": {"type": "string"},
              "functional": {
                "type": "object",
                "properties": {
                  "passed": {"type": "boolean"},
                  "checks": {"type": "integer"},
                  "failures": {"type": "integer"},
                  "notes": {"type": "string"}
                }
              },
              "performance": {
                "type": "object",
                "properties": {
                  "passed": {"type": "boolean"},
                  "cpuMax": {"type": "number"},
                  "memoryMax": {"type": "number"},
                  "throughputMbps": {"type": "number"},
                  "latencyMs": {"type": "number"},
                  "notes": {"type": "string"}
                }
              },
              "security": {
                "type": "object",
                "properties": {
                  "passed": {"type": "boolean"},
                  "vulnerabilities": {"type": "integer"},
                  "encryptionVerified": {"type": "boolean"},
                  "accessControlVerified": {"type": "boolean"},
                  "notes": {"type": "string"}
                }
              },
              "errorHandling": {
                "type": "object",
                "properties": {
                  "passed": {"type": "boolean"},
                  "recoveryTimeSeconds": {"type": "number"},
                  "errorLogs": {"type": "integer"},
                  "serviceRestarts": {"type": "integer"},
                  "notes": {"type": "string"}
                }
              },
              "integration": {
                "type": "object",
                "properties": {
                  "passed": {"type": "boolean"},
                  "crossServiceCalls": {"type": "integer"},
                  "sharedResources": {"type": "boolean"},
                  "configurationMerging": {"type": "boolean"},
                  "notes": {"type": "string"}
                }
              },
              "documentation": {
                "type": "object",
                "properties": {
                  "passed": {"type": "boolean"},
                  "examplesProvided": {"type": "boolean"},
                  "troubleshootingGuide": {"type": "boolean"},
                  "configurationGuide": {"type": "boolean"},
                  "notes": {"type": "string"}
                }
              }
            }
          },
          "configuration": {
            "type": "object",
            "properties": {
              "exampleFile": {"type": "string"},
              "requiredModules": {"type": "array", "items": {"type": "string"}},
              "optionalModules": {"type": "array", "items": {"type": "string"}},
              "minimumResources": {
                "type": "object",
                "properties": {
                  "cpuCores": {"type": "integer"},
                  "memoryGB": {"type": "integer"},
                  "diskGB": {"type": "integer"}
                }
              }
            }
          },
          "compatibility": {
            "type": "object",
            "properties": {
              "frameworkVersions": {"type": "array", "items": {"type": "string"}},
              "nixosVersions": {"type": "array", "items": {"type": "string"}},
              "hardwareRequirements": {"type": "array", "items": {"type": "string"}},
              "networkRequirements": {"type": "array", "items": {"type": "string"}}
            }
          },
          "notes": {"type": "string", "description": "Additional notes and observations"},
          "tags": {"type": "array", "items": {"type": "string"}, "description": "Categorization tags"}
        },
        "required": ["id", "capabilities", "supportLevel"]
      }
    },
    "compatibilityMatrix": {
      "type": "object",
      "description": "Pairwise compatibility between capabilities",
      "patternProperties": {
        ".*": {
          "type": "object",
          "patternProperties": {
            ".*": {
              "type": "string",
              "enum": ["compatible", "conditional", "incompatible", "untested"]
            }
          }
        }
      }
    }
  },
  "required": ["metadata", "capabilities", "combinations"]
}
```

## Sample Support Matrix Entry

```json
{
  "metadata": {
    "version": "1.0.0",
    "lastUpdated": "2024-01-01T00:00:00Z",
    "frameworkVersion": "0.1.0",
    "totalCombinations": 150,
    "supportedCombinations": 89,
    "conditionallySupported": 34,
    "notSupported": 27
  },
  "capabilities": [
    {
      "id": "core-networking",
      "name": "Core Networking",
      "category": "core",
      "version": "1.0.0",
      "services": ["systemd-networkd", "firewalld"],
      "ports": [53, 67, 68],
      "dependencies": [],
      "conflicts": []
    },
    {
      "id": "dns-management",
      "name": "DNS Management",
      "category": "networking",
      "version": "1.0.0",
      "services": ["knot", "kresd"],
      "ports": [53],
      "dependencies": ["core-networking"],
      "conflicts": []
    }
  ],
  "combinations": [
    {
      "id": "networking-dns-basic",
      "name": "Basic Networking + DNS",
      "capabilities": ["core-networking", "dns-management"],
      "supportLevel": "fully_supported",
      "supportStatus": {
        "productionReady": true,
        "customerSupported": true,
        "documentationComplete": true,
        "automatedTesting": true
      },
      "testResults": {
        "lastTested": "2024-01-01",
        "testSuite": "networking-dns-validation",
        "functional": {
          "passed": true,
          "checks": 12,
          "failures": 0,
          "notes": "All services start correctly, DNS resolution works"
        },
        "performance": {
          "passed": true,
          "cpuMax": 45.2,
          "memoryMax": 234,
          "throughputMbps": 950,
          "latencyMs": 12,
          "notes": "Performance within acceptable limits"
        },
        "security": {
          "passed": true,
          "vulnerabilities": 0,
          "encryptionVerified": true,
          "accessControlVerified": true,
          "notes": "No security issues found"
        },
        "errorHandling": {
          "passed": true,
          "recoveryTimeSeconds": 15,
          "errorLogs": 0,
          "serviceRestarts": 0,
          "notes": "Clean error logs, fast recovery"
        },
        "integration": {
          "passed": true,
          "crossServiceCalls": 8,
          "sharedResources": true,
          "configurationMerging": true,
          "notes": "Services integrate well"
        },
        "documentation": {
          "passed": true,
          "examplesProvided": true,
          "troubleshootingGuide": true,
          "configurationGuide": true,
          "notes": "Complete documentation available"
        }
      },
      "configuration": {
        "exampleFile": "examples/networking-dns-basic.nix",
        "requiredModules": ["network", "dns"],
        "optionalModules": [],
        "minimumResources": {
          "cpuCores": 2,
          "memoryGB": 2,
          "diskGB": 10
        }
      },
      "compatibility": {
        "frameworkVersions": ["0.1.0"],
        "nixosVersions": ["23.11", "24.05"],
        "hardwareRequirements": ["x86_64-linux", "aarch64-linux"],
        "networkRequirements": ["1Gbps uplink"]
      },
      "notes": "Recommended starting configuration for most deployments",
      "tags": ["recommended", "basic", "networking"]
    }
  ],
  "compatibilityMatrix": {
    "core-networking": {
      "dns-management": "compatible",
      "dhcp-management": "compatible",
      "security": "compatible"
    },
    "dns-management": {
      "dhcp-management": "compatible",
      "security": "compatible"
    }
  }
}
```

## Data Structure Benefits

### Query Capabilities
- **Support Level Filtering**: Find all fully supported combinations
- **Capability Dependencies**: Identify required capabilities
- **Resource Requirements**: Check minimum hardware needs
- **Version Compatibility**: Ensure framework version support

### Analysis Features
- **Performance Metrics**: Compare resource usage across combinations
- **Failure Patterns**: Identify common error scenarios
- **Integration Complexity**: Assess cross-service interaction complexity
- **Documentation Completeness**: Track documentation coverage

### Maintenance Features
- **Automated Updates**: Update test results programmatically
- **Regression Detection**: Identify when combinations break
- **Version Tracking**: Track compatibility across framework versions
- **Audit Trail**: Maintain history of support level changes

## Implementation Files

### Matrix Generation Script
```bash
#!/usr/bin/env bash
# scripts/generate-support-matrix.sh

set -euo pipefail

MATRIX_FILE="support-matrix.json"
TEMP_DIR=$(mktemp -d)

echo "Generating support matrix..."

# Collect all test results
find tests -name "*-validation.json" -exec cat {} \; > "$TEMP_DIR/test-results.json"

# Generate capability definitions
./scripts/generate-capabilities.sh > "$TEMP_DIR/capabilities.json"

# Build combinations
./scripts/build-combinations.sh "$TEMP_DIR/test-results.json" > "$TEMP_DIR/combinations.json"

# Create final matrix
jq -s '{
  metadata: {
    version: "1.0.0",
    lastUpdated: now | todate,
    frameworkVersion: "0.1.0"
  },
  capabilities: .[0],
  combinations: .[1]
}' "$TEMP_DIR/capabilities.json" "$TEMP_DIR/combinations.json" > "$MATRIX_FILE"

echo "Support matrix generated: $MATRIX_FILE"
```

### Validation Script
```bash
#!/usr/bin/env bash
# scripts/validate-matrix.sh

MATRIX_FILE="support-matrix.json"

echo "Validating support matrix..."

# Check JSON schema
jsonschema -i "$MATRIX_FILE" support-matrix.schema.json

# Validate capability references
jq -r '.combinations[].capabilities[]' "$MATRIX_FILE" | sort | uniq > "$TEMP_DIR/used-capabilities"
jq -r '.capabilities[].id' "$MATRIX_FILE" | sort | uniq > "$TEMP_DIR/defined-capabilities"

if ! diff "$TEMP_DIR/used-capabilities" "$TEMP_DIR/defined-capabilities" > /dev/null; then
  echo "ERROR: Capability reference mismatch"
  diff "$TEMP_DIR/used-capabilities" "$TEMP_DIR/defined-capabilities"
  exit 1
fi

# Validate test result completeness
jq '.combinations[] | select(.supportLevel == "fully_supported") | .testResults | all(.functional.passed; .performance.passed; .security.passed; .errorHandling.passed; .integration.passed; .documentation.passed)' "$MATRIX_FILE" | grep -q "true" || {
  echo "ERROR: Fully supported combinations missing required test results"
  exit 1
}

echo "Support matrix validation passed"
```

This data structure provides a comprehensive, machine-readable format for the official support matrix with rich metadata for analysis and maintenance.