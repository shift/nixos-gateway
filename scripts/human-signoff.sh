#!/usr/bin/env bash

set -euo pipefail

# Human Review and Sign-off Tool
# Usage: ./human-signoff.sh [--evidence-dir DIR] [--test-suite SUITE] [--reviewer NAME]

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Default configuration
EVIDENCE_DIR="${EVIDENCE_DIR:-/var/lib/test-evidence/current}"
TEST_SUITE="${TEST_SUITE:-all}"
REVIEWER="${REVIEWER:-$(whoami)}"
SIGNOFF_FILE="$PROJECT_ROOT/test-signoffs.json"

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --evidence-dir)
            EVIDENCE_DIR="$2"
            shift 2
            ;;
        --test-suite)
            TEST_SUITE="$2"
            shift 2
            ;;
        --reviewer)
            REVIEWER="$2"
            shift 2
            ;;
        --help|-h)
            echo "Usage: $0 [--evidence-dir DIR] [--test-suite SUITE] [--reviewer NAME]"
            echo "  --evidence-dir: Directory containing test evidence"
            echo "  --test-suite: Test suite to review (all, networking, security, performance)"
            echo "  --reviewer: Name of the reviewer"
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
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

log_success() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] ✓ $1${NC}"
}

log_warning() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] ⚠ $1${NC}"
}

log_error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ✗ $1${NC}"
}

log_info() {
    echo -e "${CYAN}[INFO] $1${NC}"
}

# Display header
display_header() {
    echo -e "${BLUE}=================================================${NC}"
    echo -e "${BLUE}    Human Review and Sign-off Tool${NC}"
    echo -e "${BLUE}=================================================${NC}"
    echo ""
    echo "Evidence Directory: $EVIDENCE_DIR"
    echo "Test Suite: $TEST_SUITE"
    echo "Reviewer: $REVIEWER"
    echo "Date: $(date -Iseconds)"
    echo ""
}

# Check evidence directory
check_evidence_dir() {
    if [[ ! -d "$EVIDENCE_DIR" ]]; then
        log_error "Evidence directory not found: $EVIDENCE_DIR"
        exit 1
    fi
    
    if [[ ! -r "$EVIDENCE_DIR" ]]; then
        log_error "Evidence directory is not readable: $EVIDENCE_DIR"
        exit 1
    fi
    
    log_success "Evidence directory validated: $EVIDENCE_DIR"
}

# Load existing sign-offs
load_signoffs() {
    if [[ -f "$SIGNOFF_FILE" ]]; then
        jq . "$SIGNOFF_FILE" 2>/dev/null || echo '{"signoffs": []}'
    else
        echo '{"signoffs": []}'
    fi
}

# Analyze evidence for review
analyze_evidence() {
    local evidence_dir="$1"
    local test_suite="$2"
    
    log "Analyzing evidence for $test_suite test suite..."
    
    local analysis_file="/tmp/evidence-analysis-$(date +%s).json"
    
    # Initialize analysis structure
    cat > "$analysis_file" << EOF
{
    "analysis_date": "$(date -Iseconds)",
    "evidence_directory": "$evidence_dir",
    "test_suite": "$test_suite",
    "reviewer": "$REVIEWER",
    "categories": {},
    "total_files": 0,
    "total_size": "$(du -sb "$evidence_dir" 2>/dev/null | cut -f1 || echo "0")"
}
EOF
    
    # Analyze evidence by category
    local -a categories=()
    
    case "$test_suite" in
        "all")
            categories=("networking" "security" "performance" "system")
            ;;
        "networking")
            categories=("networking")
            ;;
        "security")
            categories=("security")
            ;;
        "performance")
            categories=("performance")
            ;;
        *)
            log_warning "Unknown test suite: $test_suite, using all categories"
            categories=("networking" "security" "performance" "system")
            ;;
    esac
    
    local total_files=0
    
    for category in "${categories[@]}"; do
        local category_dir="$evidence_dir/$category"
        local file_count=0
        local file_list=()
        
        if [[ -d "$category_dir" ]]; then
            while IFS= read -r -d '' file; do
                file_list+=("$(basename "$file")")
                ((file_count++))
            done < <(find "$category_dir" -type f -print0 2>/dev/null)
        fi
        
        # Add category analysis to JSON
        jq --arg category "$category" \
           --argjson file_count "$file_count" \
           --argjson files "$(printf '%s\n' "${file_list[@]}" | jq -R . | jq -s .)" \
           '.categories[$category] = {"file_count": $file_count, "files": $files}' \
           "$analysis_file" > "$analysis_file.tmp" && mv "$analysis_file.tmp" "$analysis_file"
        
        ((total_files += file_count))
        
        log_info "Category '$category': $file_count files found"
    done
    
    # Update total files count
    jq --argjson total_files "$total_files" '.total_files = $total_files' \
       "$analysis_file" > "$analysis_file.tmp" && mv "$analysis_file.tmp" "$analysis_file"
    
    log_success "Evidence analysis complete: $total_files files analyzed"
    echo "$analysis_file"
}

# Display evidence summary
display_evidence_summary() {
    local analysis_file="$1"
    
    echo -e "${CYAN}=== Evidence Summary ===${NC}"
    echo ""
    
    local total_files=$(jq -r '.total_files' "$analysis_file")
    local total_size=$(jq -r '.total_size' "$analysis_file")
    
    echo "Total Files: $total_files"
    echo "Total Size: $(echo "$total_size" | awk '{print $1/1024/1024 " MB"}')"
    echo ""
    
    echo -e "${CYAN}Evidence by Category:${NC}"
    
    # Display category breakdown
    jq -r '.categories | to_entries[] | "- \(.key): \(.value.file_count) files"' "$analysis_file" | while read -r line; do
        echo "$line"
    done
    
    echo ""
}

# Display key evidence files for review
display_key_files() {
    local evidence_dir="$1"
    local analysis_file="$2"
    
    echo -e "${CYAN}=== Key Evidence Files for Review ===${NC}"
    echo ""
    
    # Find test summaries and reports
    local -a key_files=()
    
    # Look for test summary files
    while IFS= read -r -d '' file; do
        key_files+=("$file")
    done < <(find "$evidence_dir" -name "test-summary.json" -print0 2>/dev/null)
    
    # Look for comprehensive reports
    while IFS= read -r -d '' file; do
        key_files+=("$file")
    done < <(find "$evidence_dir" -name "*report*" -print0 2>/dev/null)
    
    # Look for test results
    while IFS= read -r -d '' file; do
        key_files+=("$file")
    done < <(find "$evidence_dir" -name "*test-results*" -print0 2>/dev/null)
    
    if [[ ${#key_files[@]} -eq 0 ]]; then
        log_warning "No key evidence files found for review"
        return
    fi
    
    # Display top 10 key files
    local count=0
    for file in "${key_files[@]}"; do
        if [[ $count -ge 10 ]]; then
            break
        fi
        
        local relative_path="${file#$evidence_dir/}"
        local file_size=$(stat -f%z "$file" 2>/dev/null || stat -c%s "$file" 2>/dev/null || echo "0")
        local size_mb=$(echo "$file_size" | awk '{print $1/1024/1024 " MB"}')
        
        echo -e "${YELLOW}[$((count+1))]${NC} $relative_path ($size_mb)"
        ((count++))
    done
    
    echo ""
}

# Interactive review prompts
interactive_review() {
    local evidence_dir="$1"
    local analysis_file="$2"
    
    echo -e "${CYAN}=== Interactive Review ===${NC}"
    echo ""
    
    local test_result="pending"
    
    # Review checklist
    while true; do
        echo "Evidence Review Checklist:"
        echo ""
        echo "1. [ ] Have you reviewed the evidence summary?"
        echo "2. [ ] Have you examined the key evidence files?"
        echo "3. [ ] Are all tests passing?"
        echo "4. [ ] Is the evidence sufficient for validation?"
        echo "5. [ ] Are there any concerns or issues?"
        echo ""
        
        echo -e "${YELLOW}Review Options:${NC}"
        echo "1) View evidence summary"
        echo "2) List key evidence files"
        echo "3) Examine specific evidence file"
        echo "4) Approve and sign-off"
        echo "5) Reject with comments"
        echo "6) Defer for further review"
        echo "q) Quit"
        echo ""
        
        read -p "Choose an option (1-6, q): " choice
        
        case $choice in
            1)
                display_evidence_summary "$analysis_file"
                ;;
            2)
                display_key_files "$evidence_dir" "$analysis_file"
                ;;
            3)
                examine_evidence_file "$evidence_dir"
                ;;
            4)
                test_result="approved"
                break
                ;;
            5)
                reject_with_comments "$analysis_file"
                return 1
                ;;
            6)
                test_result="deferred"
                break
                ;;
            q|Q)
                log_info "Review cancelled by user"
                exit 0
                ;;
            *)
                log_error "Invalid option: $choice"
                ;;
        esac
    done
    
    echo "$test_result"
}

# Examine specific evidence file
examine_evidence_file() {
    local evidence_dir="$1"
    
    echo ""
    echo -e "${CYAN}Available Evidence Files:${NC}"
    echo ""
    
    local -a files=()
    local count=1
    
    while IFS= read -r -d '' file; do
        local relative_path="${file#$evidence_dir/}"
        files+=("$file")
        echo "[$count] $relative_path"
        ((count++))
    done < <(find "$evidence_dir" -type f -print0 2>/dev/null | head -z -n 50)
    
    if [[ ${#files[@]} -eq 0 ]]; then
        log_warning "No evidence files found"
        return
    fi
    
    echo ""
    read -p "Enter file number to examine (or 0 to go back): " file_num
    
    if [[ "$file_num" == "0" ]]; then
        return
    fi
    
    if [[ "$file_num" =~ ^[0-9]+$ ]] && [[ $file_num -ge 1 ]] && [[ $file_num -le ${#files[@]} ]]; then
        local selected_file="${files[$((file_num-1))]}"
        display_file_content "$selected_file"
    else
        log_error "Invalid file number: $file_num"
    fi
}

# Display file content with pagination
display_file_content() {
    local file="$1"
    
    echo ""
    echo -e "${CYAN}=== File: $(basename "$file") ===${NC}"
    echo ""
    
    # Determine file type and display accordingly
    case "${file##*.}" in
        json)
            if command -v jq &> /dev/null; then
                jq . "$file" 2>/dev/null || cat "$file"
            else
                cat "$file"
            fi
            ;;
        txt|md)
            cat "$file"
            ;;
        log)
            tail -50 "$file" 2>/dev/null || cat "$file"
            ;;
        *)
            file "$file" 2>/dev/null || echo "Cannot determine file type"
            head -100 "$file" 2>/dev/null || cat "$file"
            ;;
    esac
    
    echo ""
    echo -e "${CYAN}=== End of File ===${NC}"
    echo ""
    
    read -p "Press Enter to continue..."
}

# Reject with comments
reject_with_comments() {
    local analysis_file="$1"
    
    echo ""
    echo -e "${YELLOW}=== Rejection Comments ===${NC}"
    echo ""
    echo "Please provide reasons for rejection:"
    echo ""
    
    local comments
    read -r comments
    
    # Record rejection
    local rejection_file="/tmp/rejection-$(date +%s).json"
    cat > "$rejection_file" << EOF
{
    "date": "$(date -Iseconds)",
    "reviewer": "$REVIEWER",
    "test_suite": "$TEST_SUITE",
    "evidence_dir": "$EVIDENCE_DIR",
    "status": "rejected",
    "comments": "$comments",
    "analysis": $(cat "$analysis_file")
}
EOF
    
    # Update sign-offs with rejection
    update_signoffs "$rejection_file"
    
    log_error "Test suite rejected with comments"
    echo "Comments: $comments"
    
    exit 1
}

# Update sign-offs file
update_signoffs() {
    local result_file="$1"
    
    # Load existing sign-offs
    local existing_signoffs
    existing_signoffs=$(load_signoffs)
    
    # Add new sign-off
    local updated_signoffs
    updated_signoffs=$(jq --slurpfile result "$result_file" \
       '.signoffs += [$result[0]]' \
       <<< "$existing_signoffs")
    
    # Save updated sign-offs
    echo "$updated_signoffs" > "$SIGNOFF_FILE"
    
    log_success "Sign-off record updated: $SIGNOFF_FILE"
}

# Create sign-off record
create_signoff_record() {
    local analysis_file="$1"
    local status="$2"
    local comments="${3:-}"
    
    local signoff_file="/tmp/signoff-$(date +%s).json"
    
    cat > "$signoff_file" << EOF
{
    "date": "$(date -Iseconds)",
    "reviewer": "$REVIEWER",
    "test_suite": "$TEST_SUITE",
    "evidence_dir": "$EVIDENCE_DIR",
    "status": "$status",
    "comments": "$comments",
    "analysis": $(cat "$analysis_file"),
    "signature": "$(date +%s)-$(echo "$REVIEWER-$status" | sha256sum | cut -d' ' -f1)"
}
EOF
    
    update_signoffs "$signoff_file"
    
    log_success "Sign-off record created for $TEST_SUITE: $status"
}

# Display sign-off status
display_signoff_status() {
    local test_suite="$1"
    
    echo -e "${CYAN}=== Sign-off Status ===${NC}"
    echo ""
    
    if [[ ! -f "$SIGNOFF_FILE" ]]; then
        log_info "No sign-offs recorded yet"
        return
    fi
    
    # Display recent sign-offs for this test suite
    jq --arg suite "$test_suite" \
       '.signoffs | map(select(.test_suite == $suite)) | sort_by(.date) | reverse | .[0:5]' \
       "$SIGNOFF_FILE" | \
       jq -r '.[] | "Date: \(.date) | Reviewer: \(.reviewer) | Status: \(.status) | Comments: \(.comments // "None")"' | \
       while read -r line; do
           echo "$line"
           echo ""
       done
}

# Main execution
main() {
    display_header
    
    # Check prerequisites
    check_evidence_dir
    
    # Show current sign-off status
    display_signoff_status "$TEST_SUITE"
    
    # Analyze evidence
    local analysis_file
    analysis_file=$(analyze_evidence "$EVIDENCE_DIR" "$TEST_SUITE")
    
    # Display summary
    display_evidence_summary "$analysis_file"
    
    # Display key files
    display_key_files "$EVIDENCE_DIR" "$analysis_file"
    
    # Interactive review
    echo ""
    log_info "Starting interactive review process..."
    
    local result
    result=$(interactive_review "$EVIDENCE_DIR" "$analysis_file")
    
    # Record sign-off
    case "$result" in
        "approved")
            create_signoff_record "$analysis_file" "approved" "Tests reviewed and approved by human reviewer"
            log_success "Test suite approved and signed off!"
            ;;
        "deferred")
            create_signoff_record "$analysis_file" "deferred" "Review deferred for further analysis"
            log_warning "Test suite review deferred"
            ;;
    esac
    
    # Cleanup
    rm -f "$analysis_file"
    
    # Display final status
    echo ""
    display_signoff_status "$TEST_SUITE"
}

# Run main function
main "$@"
