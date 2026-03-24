#!/usr/bin/env bash

# OpenSpec Quality Assurance Framework
# This script performs comprehensive quality checks beyond basic structure validation

set -euo pipefail

echo "=== OpenSpec Quality Assurance Framework ==="
echo "Performing comprehensive quality checks..."

# Configuration
MIN_SCENARIOS_PER_REQUIREMENT=2
MAX_REQUIREMENT_LENGTH=500
MIN_REQUIREMENT_LENGTH=20
MAX_LINE_LENGTH=120

# Colors for output
RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
NC='\033[0m' # No Color

# Counters
total_requirements=0
quality_issues=0
warnings=0
passed_checks=0

# Function to check requirement quality
check_requirement_quality() {
    local file=$1
    local requirement_text=$2
    local scenarios_count=$3
    
    total_requirements=$((total_requirements + 1))
    
    # Check 1: Minimum scenarios per requirement
    if [ "$scenarios_count" -lt "$MIN_SCENARIOS_PER_REQUIREMENT" ]; then
        echo -e "${YELLOW}WARNING${NC}: $file - Requirement has only $scenarios_count scenario(s), minimum is $MIN_SCENARIOS_PER_REQUIREMENT"
        warnings=$((warnings + 1))
    else
        passed_checks=$((passed_checks + 1))
    fi
    
    # Check 2: Requirement length
    local req_length=${#requirement_text}
    if [ "$req_length" -lt "$MIN_REQUIREMENT_LENGTH" ]; then
        echo -e "${RED}ERROR${NC}: $file - Requirement is too short ($req_length chars), minimum is $MIN_REQUIREMENT_LENGTH"
        quality_issues=$((quality_issues + 1))
    elif [ "$req_length" -gt "$MAX_REQUIREMENT_LENGTH" ]; then
        echo -e "${YELLOW}WARNING${NC}: $file - Requirement is very long ($req_length chars), consider breaking it down"
        warnings=$((warnings + 1))
    else
        passed_checks=$((passed_checks + 1))
    fi
    
    # Check 3: Use of normative language (SHALL/MUST)
    if [[ ! "$requirement_text" =~ (SHALL|MUST) ]]; then
        echo -e "${YELLOW}WARNING${NC}: $file - Requirement should use normative language (SHALL/MUST)"
        warnings=$((warnings + 1))
    else
        passed_checks=$((passed_checks + 1))
    fi
    
    # Check 4: Scenario completeness
    if [ "$scenarios_count" -eq 0 ]; then
        echo -e "${RED}ERROR${NC}: $file - Requirement has no scenarios"
        quality_issues=$((quality_issues + 1))
    fi
}

# Function to check line length
check_line_length() {
    local file=$1
    local line_number=$2
    local line=$3
    
    local line_length=${#line}
    if [ "$line_length" -gt "$MAX_LINE_LENGTH" ]; then
        echo -e "${YELLOW}WARNING${NC}: $file:$line_number - Line exceeds maximum length ($line_length > $MAX_LINE_LENGTH)"
        warnings=$((warnings + 1))
    fi
}

# Function to check for common quality issues
check_common_issues() {
    local file=$1
    
    # Check for vague language
    if grep -qi "etc\." "$file" || grep -qi "and so on" "$file" || grep -qi "various" "$file"; then
        echo -e "${YELLOW}WARNING${NC}: $file - Contains vague language (etc., and so on, various)"
        warnings=$((warnings + 1))
    fi
    
    # Check for passive voice
    if grep -qi "should be" "$file" || grep -qi "can be" "$file" || grep -qi "will be" "$file"; then
        echo -e "${YELLOW}WARNING${NC}: $file - Contains passive voice patterns"
        warnings=$((warnings + 1))
    fi
    
    # Check for weasel words
    if grep -qi "typically" "$file" || grep -qi "usually" "$file" || grep -qi "often" "$file"; then
        echo -e "${YELLOW}WARNING${NC}: $file - Contains weasel words (typically, usually, often)"
        warnings=$((warnings + 1))
    fi
}

# Main validation loop
echo ""
echo "=== Checking Spec Files ==="

# Find all spec files
spec_files=$(find openspec/changes -name "spec.md" ! -path "*/archive/*")

if [ -z "$spec_files" ]; then
    echo "No spec files found in active changes"
else
    for spec_file in $spec_files; do
        echo "Checking: $spec_file"
        
        # Initialize line number counter
        line_number=1
        
        # Check common issues
        check_common_issues "$spec_file"
        
        # Parse requirements and scenarios
        current_requirement=""
        scenario_count=0
        in_requirement=false
        
        while IFS= read -r line || [ -n "$line" ]; do
            # Check line length
            check_line_length "$spec_file" "$line_number" "$line"
            
            # Parse requirement sections
            if [[ "$line" =~ ^"### Requirement:" ]]; then
                # Save previous requirement if exists
                if [ -n "$current_requirement" ]; then
                    check_requirement_quality "$spec_file" "$current_requirement" "$scenario_count"
                fi
                
                # Start new requirement
                current_requirement="$line"
                scenario_count=0
                in_requirement=true
            elif [[ "$line" =~ ^"#### Scenario:" ]]; then
                scenario_count=$((scenario_count + 1))
                current_requirement+="\n$line"
            elif [ "$in_requirement" = true ]; then
                current_requirement+="\n$line"
            fi
            
            line_number=$((line_number + 1))
        done < "$spec_file"
        
        # Check last requirement
        if [ -n "$current_requirement" ]; then
            check_requirement_quality "$spec_file" "$current_requirement" "$scenario_count"
        fi
        
        line_number=1
    done
fi

echo ""
echo "=== Checking Task Files ==="

# Find all task files
task_files=$(find openspec/changes -name "tasks.md" ! -path "*/archive/*")

for task_file in $task_files; do
    echo "Checking: $task_file"
    
    # Check for incomplete tasks
    incomplete_tasks=$(grep -c "^- \[ \]" "$task_file" || echo 0)
    total_tasks=$(grep -c "^- \[" "$task_file" || echo 0)
    
    if [ "$total_tasks" -gt 0 ]; then
        completion_percentage=$((100 * (total_tasks - incomplete_tasks) / total_tasks))
        echo "Task completion: $completion_percentage% ($((total_tasks - incomplete_tasks))/$total_tasks)"
        
        if [ "$completion_percentage" -lt 30 ]; then
            echo -e "${YELLOW}WARNING${NC}: $task_file - Low completion percentage ($completion_percentage%)"
            warnings=$((warnings + 1))
        fi
    fi
    
    # Check for vague task descriptions
    if grep -qi "TBD\|TODO\|tbd\|todo" "$task_file"; then
        echo -e "${YELLOW}WARNING${NC}: $task_file - Contains placeholder tasks (TBD/TODO)"
        warnings=$((warnings + 1))
    fi
    
    # Check common issues
    check_common_issues "$task_file"
    
    # Check line length
    line_number=1
    while IFS= read -r line || [ -n "$line" ]; do
        check_line_length "$task_file" "$line_number" "$line"
        line_number=$((line_number + 1))
    done < "$task_file"
done

echo ""
echo "=== Checking Proposal Files ==="

# Find all proposal files
proposal_files=$(find openspec/changes -name "proposal.md" ! -path "*/archive/*")

for proposal_file in $proposal_files; do
    echo "Checking: $proposal_file"
    
    # Check for required sections
    if ! grep -q "## Why" "$proposal_file"; then
        echo -e "${RED}ERROR${NC}: $proposal_file - Missing 'Why' section"
        quality_issues=$((quality_issues + 1))
    fi
    
    if ! grep -q "## What Changes" "$proposal_file"; then
        echo -e "${RED}ERROR${NC}: $proposal_file - Missing 'What Changes' section"
        quality_issues=$((quality_issues + 1))
    fi
    
    if ! grep -q "## Impact" "$proposal_file"; then
        echo -e "${RED}ERROR${NC}: $proposal_file - Missing 'Impact' section"
        quality_issues=$((quality_issues + 1))
    fi
    
    # Check common issues
    check_common_issues "$proposal_file"
    
    # Check line length
    line_number=1
    while IFS= read -r line || [ -n "$line" ]; do
        check_line_length "$proposal_file" "$line_number" "$line"
        line_number=$((line_number + 1))
    done < "$proposal_file"
done

echo ""
echo "=== Quality Assurance Summary ==="
echo "Total Requirements Checked: $total_requirements"
echo "Quality Issues Found: $quality_issues"
echo "Warnings Found: $warnings"
echo "Checks Passed: $passed_checks"
echo ""

if [ "$quality_issues" -gt 0 ]; then
    echo -e "${RED}QUALITY CHECK FAILED${NC}: $quality_issues critical issues found"
    exit 1
elif [ "$warnings" -gt 5 ]; then
    echo -e "${YELLOW}QUALITY CHECK WARNING${NC}: $warnings warnings found (consider addressing)"
    exit 0
else
    echo -e "${GREEN}QUALITY CHECK PASSED${NC}: All quality checks passed successfully"
    exit 0
fi