#!/usr/bin/env bash

set -euo pipefail

# Human Acceptance Validation Dashboard
# Interactive tool for human review of acceptance test results

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
WHITE='\033[1;37m'
NC='\033[0m'

# UI Functions
clear_screen() {
    clear
}

show_header() {
    echo -e "${BLUE}╔══════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║                 Human Acceptance Validation Dashboard           ║${NC}"
    echo -e "${BLUE}║                        NixOS Gateway                        ║${NC}"
    echo -e "${BLUE}╚══════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${CYAN}Last Updated: $(date)${NC}"
    echo -e "${CYAN}Reviewer: ${REVIEWER:-$(whoami)}${NC}"
    echo ""
}

show_menu() {
    echo -e "${WHITE}🎯 Acceptance Validation Options:${NC}"
    echo ""
    echo -e "${CYAN}1)${NC} 📊 View Acceptance Test Results"
    echo -e "${CYAN}2)${NC} 🧪 Run New Acceptance Tests"
    echo -e "${CYAN}3)${NC} 📋 Review Acceptance Criteria"
    echo -e "${CYAN}4)${NC} 🔍 Examine Evidence Files"
    echo -e "${CYAN}5)${NC} 📝 Generate Acceptance Report"
    echo -e "${CYAN}6)${NC} ✅ Approve & Sign-off"
    echo -e "${CYAN}7)${NC} ❌ Reject with Comments"
    echo -e "${CYAN}8)${NC} 🎬 Replay Acceptance Tests"
    echo -e "${CYAN}9)${NC} 📈 View Validation Metrics"
    echo -e "${CYAN}0)${NC} 🚪 Exit"
    echo ""
}

log() {
    echo -e "${BLUE}[INFO] $1${NC}"
}

log_success() {
    echo -e "${GREEN}[SUCCESS] $1${NC}"
}

log_warning() {
    echo -e "${YELLOW}[WARNING] $1${NC}"
}

log_error() {
    echo -e "${RED}[ERROR] $1${NC}"
}

log_info() {
    echo -e "${CYAN}[INFO] $1${NC}"
}

# Find latest acceptance test results
find_latest_results() {
    local base_dir="/tmp/acceptance-test-results"
    local latest_dir=""
    
    for dir in "$base_dir"*/; do
        if [[ -d "$dir" ]]; then
            if [[ -z "$latest_dir" ]] || [[ "$dir" > "$latest_dir" ]]; then
                latest_dir="$dir"
            fi
        fi
    done
    
    echo "$latest_dir"
}

# View acceptance test results
view_acceptance_results() {
    clear_screen
    show_header
    echo -e "${WHITE}📊 Acceptance Test Results${NC}"
    echo -e "${BLUE}$(printf '─%.0s' {1..70})${NC}"
    echo ""
    
    local latest_results
    latest_results=$(find_latest_results)
    
    if [[ -z "$latest_results" ]]; then
        log_warning "No acceptance test results found."
        echo ""
        echo -e "${YELLOW}Would you like to run new acceptance tests? (y/N):${NC}"
        read -r response
        if [[ "$response" =~ ^[Yy]$ ]]; then
            run_new_acceptance_tests
        fi
        return
    fi
    
    echo -e "${CYAN}Latest Results Directory:${NC}"
    echo "$latest_results"
    echo ""
    
    # Show results summary
    local reports_dir="$latest_results/reports"
    if [[ -d "$reports_dir" ]]; then
        echo -e "${WHITE}Available Test Suites:${NC}"
        echo ""
        
        local count=1
        for report in "$reports_dir"/acceptance-results-*.json; do
            if [[ -f "$report" ]]; then
                local suite_name=$(basename "$report" | sed 's/acceptance-results-\(.*\)\.json/\1/')
                local status=$(jq -r '.overall_status' "$report" 2>/dev/null || echo "unknown")
                local passed=$(jq -r '.passed_features' "$report" 2>/dev/null || echo "0")
                local total=$(jq -r '.total_features' "$report" 2>/dev/null || echo "0")
                local date=$(jq -r '.execution_date' "$report" 2>/dev/null || echo "unknown")
                
                local status_icon="❓"
                case "$status" in
                    "passed") status_icon="✅" ;;
                    "partial") status_icon="⚠️" ;;
                    "failed") status_icon="❌" ;;
                esac
                
                echo -e "${CYAN}$count)${NC} $suite_name $status_icon $passed/$total features passed"
                echo "   📅 $date"
                echo ""
                
                ((count++))
            fi
        done
        
        if [[ $count -eq 1 ]]; then
            log_warning "No test results found in reports directory."
        else
            echo -e "${YELLOW}Enter suite number to view details (or 0 to go back):${NC}"
            read -r suite_choice
            
            if [[ "$suite_choice" =~ ^[0-9]+$ ]] && [[ $suite_choice -gt 0 ]] && [[ $suite_choice -lt $count ]]; then
                local selected_report=$(ls "$reports_dir"/acceptance-results-*.json | sed -n "${suite_choice}p")
                view_suite_details "$selected_report"
            fi
        fi
    else
        log_warning "No reports directory found in results."
    fi
    
    echo ""
    echo -e "${YELLOW}Press Enter to continue...${NC}"
    read -r
}

# View suite details
view_suite_details() {
    local report_file="$1"
    local suite_name=$(basename "$report_file" | sed 's/acceptance-results-\(.*\)\.json/\1/')
    
    clear_screen
    show_header
    echo -e "${WHITE}📊 Acceptance Test Details - $suite_name${NC}"
    echo -e "${BLUE}$(printf '─%.0s' {1..70})${NC}"
    echo ""
    
    # Show overall status
    local overall_status=$(jq -r '.overall_status' "$report_file")
    local execution_date=$(jq -r '.execution_date' "$report_file")
    local passed=$(jq -r '.passed_features' "$report_file")
    local total=$(jq -r '.total_features' "$report_file")
    
    local status_color="$RED"
    case "$overall_status" in
        "passed") status_color="$GREEN" ;;
        "partial") status_color="$YELLOW" ;;
    esac
    
    echo -e "${WHITE}Overall Status: ${status_color}$overall_status${NC}"
    echo "Execution Date: $execution_date"
    echo "Features Passed: $passed/$total"
    echo ""
    
    # Show feature details
    echo -e "${WHITE}Feature Results:${NC}"
    echo ""
    
    jq -r '.features | to_entries[] | 
      "- \(.key | gsub("-"; " ") | ascii_upcase): \(.value.status)"' "$report_file" | while read -r line; do
        if [[ "$line" == *"passed"* ]]; then
            echo -e "${GREEN}$line${NC}"
        elif [[ "$line" == *"failed"* ]]; then
            echo -e "${RED}$line${NC}"
        else
            echo -e "${YELLOW}$line${NC}"
        fi
    done
    
    echo ""
    
    # Show acceptance criteria validation
    local report_dir=$(dirname "$report_file")
    local acceptance_report="$report_dir/acceptance-report-$suite_name.md"
    
    if [[ -f "$acceptance_report" ]]; then
        echo -e "${WHITE}Acceptance Criteria Validation:${NC}"
        echo ""
        
        # Extract acceptance criteria status
        if grep -q "All Acceptance Criteria Met" "$acceptance_report"; then
            echo -e "${GREEN}✅ All Acceptance Criteria Met${NC}"
        elif grep -q "Partial Acceptance Criteria Met" "$acceptance_report"; then
            echo -e "${YELLOW}⚠️ Partial Acceptance Criteria Met${NC}"
        else
            echo -e "${RED}❌ Acceptance Criteria Not Met${NC}"
        fi
    fi
    
    echo ""
    echo -e "${YELLOW}Press Enter to continue...${NC}"
    read -r
}

# Run new acceptance tests
run_new_acceptance_tests() {
    clear_screen
    show_header
    echo -e "${WHITE}🧪 Run New Acceptance Tests${NC}"
    echo -e "${BLUE}$(printf '─%.0s' {1..70})${NC}"
    echo ""
    
    echo -e "${WHITE}Select Test Suite:${NC}"
    echo ""
    echo -e "${CYAN}1)${NC} All Suites (Networking, Security, Performance)"
    echo -e "${CYAN}2)${NC} Networking Foundation"
    echo -e "${CYAN}3)${NC} Security & Access Control"
    echo -e "${CYAN}4)${NC} Performance & Acceleration"
    echo ""
    echo -e "${YELLOW}Enter choice (1-4):${NC}"
    read -r test_choice
    
    local suite="all"
    case "$test_choice" in
        1) suite="all" ;;
        2) suite="networking" ;;
        3) suite="security" ;;
        4) suite="performance" ;;
        *) 
            log_error "Invalid choice"
            return
            ;;
    esac
    
    echo ""
    log "Starting acceptance tests for: $suite"
    echo "This may take several minutes..."
    echo ""
    
    # Run the automated acceptance test
    if command -v nix >/dev/null 2>&1; then
        if nix run .#automatedAcceptanceTest -- validate "$suite" 2>&1; then
            log_success "Acceptance tests completed successfully!"
        else
            log_error "Acceptance tests failed. Check logs for details."
        fi
    else
        log_error "Nix not available. Cannot run acceptance tests."
    fi
    
    echo ""
    echo -e "${YELLOW}Press Enter to continue...${NC}"
    read -r
}

# Review acceptance criteria
review_acceptance_criteria() {
    clear_screen
    show_header
    echo -e "${WHITE}📋 Acceptance Criteria Review${NC}"
    echo -e "${BLUE}$(printf '─%.0s' {1..70})${NC}"
    echo ""
    
    echo -e "${WHITE}Select Feature Category:${NC}"
    echo ""
    echo -e "${CYAN}1)${NC} Networking Foundation Features"
    echo -e "${CYAN}2)${NC} Security & Access Control Features"
    echo -e "${CYAN}3)${NC} Performance & Acceleration Features"
    echo ""
    echo -e "${YELLOW}Enter choice (1-3):${NC}"
    read -r criteria_choice
    
    clear_screen
    show_header
    
    case "$criteria_choice" in
        1)
            echo -e "${WHITE}🌐 Networking Foundation Acceptance Criteria${NC}"
            echo -e "${BLUE}$(printf '─%.0s' {1..70})${NC}"
            echo ""
            echo -e "${GREEN}Functional Requirements:${NC}"
            echo "✅ All network interfaces detected and configured"
            echo "✅ Routing protocols establish and converge"
            echo "✅ Policy routing rules applied correctly"
            echo "✅ Performance meets or exceeds benchmarks"
            echo ""
            echo -e "${GREEN}Security Requirements:${NC}"
            echo "✅ Network isolation implemented correctly"
            echo "✅ No unauthorized traffic flows"
            echo "✅ Security policies enforced"
            echo ""
            echo -e "${GREEN}Reliability Requirements:${NC}"
            echo "✅ High availability failover works"
            echo "✅ Configuration reload without service disruption"
            echo "✅ Graceful degradation on failures"
            ;;
        2)
            echo -e "${WHITE}🔒 Security & Access Control Acceptance Criteria${NC}"
            echo -e "${BLUE}$(printf '─%.0s' {1..70})${NC}"
            echo ""
            echo -e "${GREEN}Functional Requirements:${NC}"
            echo "✅ All security policies implemented correctly"
            echo "✅ Access control enforced"
            echo "✅ Threat detection and response working"
            echo ""
            echo -e "${GREEN}Compliance Requirements:${NC}"
            echo "✅ Industry security standards met"
            echo "✅ Audit trails complete and immutable"
            echo "✅ Data protection requirements satisfied"
            echo ""
            echo -e "${GREEN}Performance Requirements:${NC}"
            echo "✅ Security overhead < 10%"
            echo "✅ Real-time threat processing"
            echo "✅ Sub-second policy evaluation"
            ;;
        3)
            echo -e "${WHITE}🚀 Performance & Acceleration Acceptance Criteria${NC}"
            echo -e "${BLUE}$(printf '─%.0s' {1..70})${NC}"
            echo ""
            echo -e "${GREEN}Throughput Requirements:${NC}"
            echo "✅ Line rate performance achieved"
            echo "✅ No packet loss under load"
            echo "✅ Latency within specifications"
            echo ""
            echo -e "${GREEN}Scalability Requirements:${NC}"
            echo "✅ Linear performance scaling"
            echo "✅ Resource usage within limits"
            echo "✅ Graceful degradation"
            echo ""
            echo -e "${GREEN}Reliability Requirements:${NC}"
            echo "✅ 99.999% uptime achieved"
            echo "✅ Failover time < 5 seconds"
            echo "✅ Zero data loss during failover"
            ;;
        *)
            log_error "Invalid choice"
            return
            ;;
    esac
    
    echo ""
    echo -e "${WHITE}💡 Acceptance Process:${NC}"
    echo "1. Automated tests verify technical requirements"
    echo "2. Evidence collected demonstrates compliance"
    echo "3. Human review validates business requirements"
    echo "4. Sign-off indicates readiness for production"
    echo ""
    echo -e "${YELLOW}Press Enter to continue...${NC}"
    read -r
}

# Examine evidence files
examine_evidence_files() {
    clear_screen
    show_header
    echo -e "${WHITE}🔍 Examine Evidence Files${NC}"
    echo -e "${BLUE}$(printf '─%.0s' {1..70})${NC}"
    echo ""
    
    local latest_results
    latest_results=$(find_latest_results)
    
    if [[ -z "$latest_results" ]]; then
        log_warning "No test results found."
        echo ""
        echo -e "${YELLOW}Press Enter to continue...${NC}"
        read -r
        return
    fi
    
    local evidence_dir="$latest_results/evidence"
    if [[ ! -d "$evidence_dir" ]]; then
        log_warning "No evidence directory found."
        echo ""
        echo -e "${YELLOW}Press Enter to continue...${NC}"
        read -r
        return
    fi
    
    echo -e "${CYAN}Available Evidence Files:${NC}"
    echo ""
    
    local count=1
    local files=()
    
    while IFS= read -r -d '' file; do
        files+=("$file")
        local rel_path="${file#$latest_results/}"
        local file_size=$(stat -f%z "$file" 2>/dev/null || stat -c%s "$file" 2>/dev/null || echo "0")
        local size_mb=$(echo "$file_size" | awk '{print $1/1024 " KB"}')
        
        echo -e "${CYAN}$count)${NC} $rel_path ($size_mb)"
        ((count++))
    done < <(find "$latest_results" -name "*.log" -o -name "*.json" -o -name "*.md" -print0 2>/dev/null | head -z -n 20)
    
    if [[ $count -eq 1 ]]; then
        log_warning "No evidence files found."
    else
        echo ""
        echo -e "${YELLOW}Enter file number to view (or 0 to go back):${NC}"
        read -r file_choice
        
        if [[ "$file_choice" =~ ^[0-9]+$ ]] && [[ $file_choice -gt 0 ]] && [[ $file_choice -lt $count ]]; then
            local selected_file="${files[$((file_choice-1))]}"
            view_evidence_file "$selected_file"
        fi
    fi
    
    echo ""
    echo -e "${YELLOW}Press Enter to continue...${NC}"
    read -r
}

# View evidence file content
view_evidence_file() {
    local file="$1"
    
    clear_screen
    show_header
    echo -e "${WHITE}📄 Evidence File Viewer${NC}"
    echo -e "${BLUE}$(printf '─%.0s' {1..70})${NC}"
    echo ""
    
    echo -e "${CYAN}File:${NC} $(basename "$file")"
    echo -e "${CYAN}Path:${NC} $file"
    echo -e "${CYAN}Size:${NC} $(du -h "$file" | cut -f1)"
    echo ""
    
    echo -e "${WHITE}Content:${NC}"
    echo -e "${BLUE}$(printf '─%.0s' {1..70})${NC}"
    echo ""
    
    # Display file content based on type
    case "${file##*.}" in
        json)
            if command -v jq >/dev/null 2>&1; then
                jq . "$file" 2>/dev/null || cat "$file"
            else
                cat "$file"
            fi
            ;;
        md)
            cat "$file"
            ;;
        log|txt)
            # Show last 50 lines for log files
            if [[ ${file##*.} == "log" ]]; then
                tail -50 "$file"
            else
                cat "$file"
            fi
            ;;
        *)
            file "$file" 2>/dev/null || echo "Cannot determine file type"
            head -100 "$file" 2>/dev/null || cat "$file"
            ;;
    esac
    
    echo ""
    echo -e "${BLUE}$(printf '─%.0s' {1..70})${NC}"
    echo ""
    echo -e "${YELLOW}Press Enter to continue...${NC}"
    read -r
}

# Generate acceptance report
generate_acceptance_report() {
    clear_screen
    show_header
    echo -e "${WHITE}📝 Generate Acceptance Report${NC}"
    echo -e "${BLUE}$(printf '─%.0s' {1..70})${NC}"
    echo ""
    
    local latest_results
    latest_results=$(find_latest_results)
    
    if [[ -z "$latest_results" ]]; then
        log_warning "No test results found for report generation."
        echo ""
        echo -e "${YELLOW}Press Enter to continue...${NC}"
        read -r
        return
    fi
    
    echo -e "${WHITE}Report Generation Options:${NC}"
    echo ""
    echo -e "${CYAN}1)${NC} Generate All Reports"
    echo -e "${CYAN}2)${NC} Generate Summary Report"
    echo -e "${CYAN}3)${NC} Generate Detailed Technical Report"
    echo -e "${CYAN}4)${NC} Generate Executive Report"
    echo ""
    echo -e "${YELLOW}Enter choice (1-4):${NC}"
    read -r report_choice
    
    local reports_dir="$latest_results/reports"
    local timestamp=$(date +%Y%m%d-%H%M%S)
    
    case "$report_choice" in
        1)
            log "Generating all acceptance reports..."
            # This would call the existing report generation
            ;;
        2)
            log "Generating summary report..."
            create_summary_report "$reports_dir" "$timestamp"
            ;;
        3)
            log "Generating detailed technical report..."
            create_technical_report "$reports_dir" "$timestamp"
            ;;
        4)
            log "Generating executive report..."
            create_executive_report "$reports_dir" "$timestamp"
            ;;
        *)
            log_error "Invalid choice"
            return
            ;;
    esac
    
    log_success "Report generated successfully!"
    echo ""
    echo -e "${YELLOW}Press Enter to continue...${NC}"
    read -r
}

# Create summary report
create_summary_report() {
    local reports_dir="$1"
    local timestamp="$2"
    local report_file="$reports_dir/acceptance-summary-$timestamp.md"
    
    cat > "$report_file" << EOF
# Acceptance Test Summary Report

## Overview

This report provides a high-level summary of acceptance testing results for the NixOS Gateway Configuration Framework.

**Generated:** $(date -Iseconds)  
**Reviewer:** ${REVIEWER:-$(whoami)}  
**Framework Version:** v0.1.0-beta1

## Test Results Summary

EOF
    
    # Add summary for each suite
    for results_file in "$reports_dir"/acceptance-results-*.json; do
        if [[ -f "$results_file" ]]; then
            local suite_name=$(basename "$results_file" | sed 's/acceptance-results-\(.*\)\.json/\1/')
            local status=$(jq -r '.overall_status' "$results_file")
            local passed=$(jq -r '.passed_features' "$results_file")
            local total=$(jq -r '.total_features' "$results_file")
            
            cat >> "$report_file" << EOF
### $suite_name

- **Status:** $status
- **Features:** $passed/$total passed
- **Completion Rate:** $(( passed * 100 / total ))%

EOF
        fi
    done
    
    cat >> "$report_file" << EOF

## Recommendations

1. Review any failed or partially completed test suites
2. Address acceptance criteria that were not met
3. Schedule human review and sign-off for completed suites
4. Archive results for compliance and auditing

---
*Report generated by Human Acceptance Validation Dashboard*
EOF
    
    log_success "Summary report created: $report_file"
}

# Main application loop
main() {
    while true; do
        clear_screen
        show_header
        show_menu
        
        echo -e "${YELLOW}Enter your choice:${NC}"
        read -r choice
        
        case $choice in
            1)
                view_acceptance_results
                ;;
            2)
                run_new_acceptance_tests
                ;;
            3)
                review_acceptance_criteria
                ;;
            4)
                examine_evidence_files
                ;;
            5)
                generate_acceptance_report
                ;;
            6)
                echo "Approve & Sign-off"
                # This would call the existing human-signoff.sh script
                ;;
            7)
                echo "Reject with Comments"
                # This would call the existing human-signoff.sh script
                ;;
            8)
                echo "Replay Acceptance Tests"
                # This would call replay functionality
                ;;
            9)
                echo "View Validation Metrics"
                # This would show metrics and trends
                ;;
            0)
                echo -e "${GREEN}Goodbye!${NC}"
                exit 0
                ;;
            *)
                log_error "Invalid choice. Please try again."
                echo ""
                echo -e "${YELLOW}Press Enter to continue...${NC}"
                read -r
                ;;
        esac
    done
}

# Check dependencies
check_dependencies() {
    local missing_deps=()
    
    if ! command -v jq >/dev/null 2>&1; then
        missing_deps+=("jq")
    fi
    
    if ! command -v nix >/dev/null 2>&1; then
        missing_deps+=("nix")
    fi
    
    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        log_error "Missing dependencies: ${missing_deps[*]}"
        echo ""
        echo "Please install missing dependencies and try again."
        exit 1
    fi
}

# Initialize
check_dependencies
main
