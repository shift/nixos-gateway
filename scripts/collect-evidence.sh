#!/usr/bin/env bash

set -euo pipefail

# Evidence Collection and Analysis Tool
# Usage: ./collect-evidence.sh [--test-type TYPE] [--source-dir DIR] [--output-dir DIR]

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Default configuration
TEST_TYPE="${TEST_TYPE:-all}"
SOURCE_DIR="${SOURCE_DIR:-/tmp/test-results}"
OUTPUT_DIR="${OUTPUT_DIR:-/var/lib/test-evidence}"

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --test-type)
            TEST_TYPE="$2"
            shift 2
            ;;
        --source-dir)
            SOURCE_DIR="$2"
            shift 2
            ;;
        --output-dir)
            OUTPUT_DIR="$2"
            shift 2
            ;;
        --help|-h)
            echo "Usage: $0 [--test-type TYPE] [--source-dir DIR] [--output-dir DIR]"
            echo "  --test-type: Type of evidence to collect (all, networking, security, performance)"
            echo "  --source-dir: Directory containing test results"
            echo "  --output-dir: Directory to store collected evidence"
            echo "  --help: Show this help message"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

log_success() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] ✓ $1${NC}"
}

# Setup output directory
setup_output_dir() {
    local timestamp=$(date +%Y%m%d-%H%M%S)
    local evidence_dir="$OUTPUT_DIR/evidence-$timestamp"
    
    mkdir -p "$evidence_dir"/{networking,security,performance,system,reports}
    
    echo "$evidence_dir"
}

# Collect networking evidence
collect_networking_evidence() {
    local source="$1"
    local output="$2"
    
    log "Collecting networking evidence..."
    
    # NAT and Port Forwarding evidence
    if [[ -d "$source/nat-port-forwarding" ]]; then
        cp -r "$source/nat-port-forwarding" "$output/networking/"
        log_success "NAT/Port Forwarding evidence collected"
    fi
    
    # Network Isolation evidence
    if [[ -d "$source/network-isolation" ]]; then
        cp -r "$source/network-isolation" "$output/networking/"
        log_success "Network Isolation evidence collected"
    fi
    
    # Interface Management evidence
    if [[ -d "$source/networking" ]]; then
        cp -r "$source/networking" "$output/networking/"
        log_success "Interface Management evidence collected"
    fi
    
    # Performance Throughput evidence
    if [[ -d "$source/performance-throughput" ]]; then
        cp -r "$source/performance-throughput" "$output/networking/"
        log_success "Performance Throughput evidence collected"
    fi
    
    # Routing and IP Forwarding evidence
    if [[ -d "$source/routing" ]]; then
        cp -r "$source/routing" "$output/networking/"
        log_success "Routing evidence collected"
    fi
}

# Collect security evidence
collect_security_evidence() {
    local source="$1"
    local output="$2"
    
    log "Collecting security evidence..."
    
    # Security test results
    if [[ -d "$source/security" ]]; then
        cp -r "$source/security" "$output/security/"
        log_success "Security test evidence collected"
    fi
    
    # Firewall rules and logs
    if [[ -d "$source/firewall" ]]; then
        cp -r "$source/firewall" "$output/security/"
        log_success "Firewall evidence collected"
    fi
    
    # Intrusion detection evidence
    if [[ -d "$source/ids" ]]; then
        cp -r "$source/ids" "$output/security/"
        log_success "IDS evidence collected"
    fi
}

# Collect performance evidence
collect_performance_evidence() {
    local source="$1"
    local output="$2"
    
    log "Collecting performance evidence..."
    
    # Performance metrics
    if [[ -d "$source/performance" ]]; then
        cp -r "$source/performance" "$output/performance/"
        log_success "Performance metrics collected"
    fi
    
    # Benchmark results
    if [[ -d "$source/benchmarks" ]]; then
        cp -r "$source/benchmarks" "$output/performance/"
        log_success "Benchmark results collected"
    fi
    
    # Resource usage data
    if [[ -d "$source/resources" ]]; then
        cp -r "$source/resources" "$output/performance/"
        log_success "Resource usage data collected"
    fi
}

# Collect system evidence
collect_system_evidence() {
    local source="$1"
    local output="$2"
    
    log "Collecting system evidence..."
    
    # System configuration
    if [[ -d "$source/system" ]]; then
        cp -r "$source/system" "$output/system/"
        log_success "System configuration collected"
    fi
    
    # Log files
    if [[ -d "$source/logs" ]]; then
        cp -r "$source/logs" "$output/system/"
        log_success "System logs collected"
    fi
    
    # Service status
    if [[ -d "$source/services" ]]; then
        cp -r "$source/services" "$output/system/"
        log_success "Service status collected"
    fi
}

# Generate evidence analysis report
generate_analysis_report() {
    local evidence_dir="$1"
    local report_file="$2"
    
    log "Generating evidence analysis report..."
    
    # Count evidence files
    local networking_files=$(find "$evidence_dir/networking" -type f 2>/dev/null | wc -l)
    local security_files=$(find "$evidence_dir/security" -type f 2>/dev/null | wc -l)
    local performance_files=$(find "$evidence_dir/performance" -type f 2>/dev/null | wc -l)
    local system_files=$(find "$evidence_dir/system" -type f 2>/dev/null | wc -l)
    local total_files=$((networking_files + security_files + performance_files + system_files))
    
    # Calculate evidence directory size
    local evidence_size=$(du -sh "$evidence_dir" | cut -f1)
    
    # Create report
    cat > "$report_file" << EOF
# Evidence Collection Analysis Report

## Collection Summary

- **Collection Date**: $(date -Iseconds)
- **Evidence Directory**: \`$evidence_dir\`
- **Total Evidence Files**: $total_files
- **Evidence Size**: $evidence_size
- **Collection Type**: $TEST_TYPE

## Evidence Breakdown

| Category | Files | Key Evidence |
|-----------|--------|--------------|
| Networking | $networking_files | NAT rules, port forwarding, isolation, performance |
| Security | $security_files | Firewall rules, IDS alerts, access logs |
| Performance | $performance_files | Benchmarks, resource usage, metrics |
| System | $system_files | Configuration, logs, service status |

## Evidence Details

### Networking Evidence
EOF
    
    # Add networking evidence details
    if [[ $networking_files -gt 0 ]]; then
        echo "" >> "$report_file"
        echo "**Key Files Found:**" >> "$report_file"
        find "$evidence_dir/networking" -type f -name "*.txt" -o -name "*.json" -o -name "*.pcap" | \
            sed 's|.*/||' | head -20 | while read -r file; do
            echo "- \`$file\`" >> "$report_file"
        done
    fi
    
    cat >> "$report_file" << EOF

### Security Evidence
EOF
    
    # Add security evidence details
    if [[ $security_files -gt 0 ]]; then
        echo "" >> "$report_file"
        echo "**Key Files Found:**" >> "$report_file"
        find "$evidence_dir/security" -type f -name "*.txt" -o -name "*.json" -o -name "*.log" | \
            sed 's|.*/||' | head -20 | while read -r file; do
            echo "- \`$file\`" >> "$report_file"
        done
    fi
    
    cat >> "$report_file" << EOF

### Performance Evidence
EOF
    
    # Add performance evidence details
    if [[ $performance_files -gt 0 ]]; then
        echo "" >> "$report_file"
        echo "**Key Files Found:**" >> "$report_file"
        find "$evidence_dir/performance" -type f -name "*.txt" -o -name "*.json" | \
            sed 's|.*/||' | head -20 | while read -r file; do
            echo "- \`$file\`" >> "$report_file"
        done
    fi
    
    cat >> "$report_file" << EOF

### System Evidence
EOF
    
    # Add system evidence details
    if [[ $system_files -gt 0 ]]; then
        echo "" >> "$report_file"
        echo "**Key Files Found:**" >> "$report_file"
        find "$evidence_dir/system" -type f -name "*.txt" -o -name "*.json" -o -name "*.log" | \
            sed 's|.*/||' | head -20 | while read -r file; do
            echo "- \`$file\`" >> "$report_file"
        done
    fi
    
    cat >> "$report_file" << EOF

## Recommendations

1. **Review Evidence**: Analyze collected evidence for compliance and performance requirements
2. **Archive for Long-term Storage**: Store evidence archives for audit purposes
3. **Update Documentation**: Include key findings in project documentation
4. **Monitor Trends**: Compare evidence over time to identify patterns
5. **Security Review**: Ensure no security concerns in collected evidence

## Next Steps

- Evidence is ready for human review and sign-off
- Create test completion reports for stakeholders
- Archive evidence for compliance and auditing
- Update project documentation with validated capabilities

---
*Report generated by Evidence Collection Tool*
EOF
    
    log_success "Evidence analysis report generated: $report_file"
}

# Create evidence archive
create_evidence_archive() {
    local evidence_dir="$1"
    
    log "Creating evidence archive..."
    
    local archive_name="evidence-$(basename "$evidence_dir").tar.gz"
    local archive_path="$OUTPUT_DIR/archives/$archive_name"
    
    # Create archives directory
    mkdir -p "$(dirname "$archive_path")"
    
    # Create compressed archive
    tar -czf "$archive_path" -C "$(dirname "$evidence_dir")" "$(basename "$evidence_dir")"
    
    # Create checksum
    local checksum_file="$archive_path.sha256"
    sha256sum "$archive_path" > "$checksum_file"
    
    log_success "Evidence archive created: $archive_path"
    log "Checksum: $(cat "$checksum_file" | cut -d' ' -f1)"
    
    echo "$archive_path"
}

# Main execution
main() {
    log "Starting evidence collection..."
    
    # Setup output directory
    local evidence_dir
    evidence_dir=$(setup_output_dir)
    
    # Collect evidence based on type
    case "$TEST_TYPE" in
        "networking")
            collect_networking_evidence "$SOURCE_DIR" "$evidence_dir"
            ;;
        "security")
            collect_security_evidence "$SOURCE_DIR" "$evidence_dir"
            ;;
        "performance")
            collect_performance_evidence "$SOURCE_DIR" "$evidence_dir"
            ;;
        "all")
            collect_networking_evidence "$SOURCE_DIR" "$evidence_dir"
            collect_security_evidence "$SOURCE_DIR" "$evidence_dir"
            collect_performance_evidence "$SOURCE_DIR" "$evidence_dir"
            collect_system_evidence "$SOURCE_DIR" "$evidence_dir"
            ;;
        *)
            log "Unknown test type: $TEST_TYPE"
            exit 1
            ;;
    esac
    
    # Generate analysis report
    local report_file="$evidence_dir/reports/evidence-analysis.md"
    generate_analysis_report "$evidence_dir" "$report_file"
    
    # Create archive
    local archive_path
    archive_path=$(create_evidence_archive "$evidence_dir")
    
    # Summary
    log_success "Evidence collection completed!"
    log "Evidence Directory: $evidence_dir"
    log "Analysis Report: $report_file"
    log "Archive: $archive_path"
    
    # Update current evidence symlink
    ln -sf "$evidence_dir" "$OUTPUT_DIR/current"
    
    log "Current evidence symlink: $OUTPUT_DIR/current"
}

# Run main function
main "$@"
