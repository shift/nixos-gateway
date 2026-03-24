#!/usr/bin/env bash

# OpenSpec Quality Assurance Tool
# Focused quality checks for OpenSpec documents

set -euo pipefail

echo "=== OpenSpec Quality Assurance Tool ==="
echo ""

# Configuration
MIN_SCENARIOS=2
MAX_LINE_LENGTH=120
MIN_COMPLETION=30

# Colors
RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Counters
issues=0
warnings=0
requirements=0
scenarios=0

# Function to check line length
check_line_length() {
    local file=$1
    while IFS= read -r line || [ -n "$line" ]; do
        local length=${#line}
        if [ "$length" -gt "$MAX_LINE_LENGTH" ]; then
            echo -e "${YELLOW}⚠️  Line length${NC}: $file - Line exceeds $MAX_LINE_LENGTH chars ($length)"
            warnings=$((warnings + 1))
        fi
    done < "$file"
}

# Function to check requirement quality
check_requirement_quality() {
    local file=$1
    
    # Count scenarios per requirement
    local req_count=$(grep -c "^### Requirement:" "$file" || echo 0)
    local scenario_count=$(grep -c "^#### Scenario:" "$file" || echo 0)
    
    requirements=$((requirements + req_count))
    scenarios=$((scenarios + scenario_count))
    
    if [ "$req_count" -gt 0 ]; then
        local avg_scenarios=$((scenario_count / req_count))
        echo -e "${BLUE}📊 Requirements${NC}: $file - $req_count requirements, $scenario_count scenarios (avg $avg_scenarios/scenarios per requirement)"
        
        if [ "$avg_scenarios" -lt "$MIN_SCENARIOS" ]; then
            echo -e "${YELLOW}⚠️  Scenario coverage${NC}: $file - Below minimum $MIN_SCENARIOS scenarios/requirement"
            warnings=$((warnings + 1))
        fi
    fi
    
    # Check for normative language
    if [ "$req_count" -gt 0 ] && ! grep -q "SHALL\|MUST" "$file"; then
        echo -e "${YELLOW}⚠️  Normative language${NC}: $file - Missing SHALL/MUST in requirements"
        warnings=$((warnings + 1))
    fi
}

# Function to check task completion
check_task_completion() {
    local file=$1
    
    local incomplete=$(grep -c "^- \[ \]" "$file" || echo 0)
    local total=$(grep -c "^- \[" "$file" || echo 0)
    
    if [ "$total" -gt 0 ]; then
        local percentage=$((100 * (total - incomplete) / total))
        echo -e "${BLUE}📋 Tasks${NC}: $file - $percentage% complete ($((total - incomplete))/$total)"
        
        if [ "$percentage" -lt "$MIN_COMPLETION" ]; then
            echo -e "${YELLOW}⚠️  Low completion${NC}: $file - Below $MIN_COMPLETION% threshold"
            warnings=$((warnings + 1))
        fi
    fi
}

# Function to check proposal completeness
check_proposal_completeness() {
    local file=$1
    
    local missing=0
    
    if ! grep -q "## Why" "$file"; then
        echo -e "${RED}❌ Missing section${NC}: $file - Missing 'Why' section"
        issues=$((issues + 1))
        missing=$((missing + 1))
    fi
    
    if ! grep -q "## What Changes" "$file"; then
        echo -e "${RED}❌ Missing section${NC}: $file - Missing 'What Changes' section"
        issues=$((issues + 1))
        missing=$((missing + 1))
    fi
    
    if ! grep -q "## Impact" "$file"; then
        echo -e "${RED}❌ Missing section${NC}: $file - Missing 'Impact' section"
        issues=$((issues + 1))
        missing=$((missing + 1))
    fi
    
    if [ "$missing" -eq 0 ]; then
        echo -e "${GREEN}✅ Proposal complete${NC}: $file - All required sections present"
    fi
}

# Function to check for quality issues
check_quality_issues() {
    local file=$1
    
    # Check for vague language
    if grep -qi "etc\." "$file" || grep -qi "and so on" "$file"; then
        echo -e "${YELLOW}⚠️  Vague language${NC}: $file - Contains 'etc.' or 'and so on'"
        warnings=$((warnings + 1))
    fi
    
    # Check for passive voice
    if grep -qi "should be\|can be\|will be" "$file"; then
        echo -e "${YELLOW}⚠️  Passive voice${NC}: $file - Contains passive voice patterns"
        warnings=$((warnings + 1))
    fi
    
    # Check for placeholders
    if grep -qi "TBD\|TODO" "$file"; then
        echo -e "${YELLOW}⚠️  Placeholders${NC}: $file - Contains TBD/TODO placeholders"
        warnings=$((warnings + 1))
    fi
}

# Main analysis
echo -e "${BLUE}=== SPEC FILES ===${NC}"
for spec in $(find openspec/changes -name "spec.md" ! -path "*/archive/*" | sort); do
    echo ""
    check_requirement_quality "$spec"
    check_line_length "$spec"
    check_quality_issues "$spec"
done

echo ""
echo -e "${BLUE}=== TASK FILES ===${NC}"
for task in $(find openspec/changes -name "tasks.md" ! -path "*/archive/*" | sort); do
    echo ""
    check_task_completion "$task"
    check_line_length "$task"
    check_quality_issues "$task"
done

echo ""
echo -e "${BLUE}=== PROPOSAL FILES ===${NC}"
for proposal in $(find openspec/changes -name "proposal.md" ! -path "*/archive/*" | sort); do
    echo ""
    check_proposal_completeness "$proposal"
    check_line_length "$proposal"
    check_quality_issues "$proposal"
done

# Summary
echo ""
echo -e "${BLUE}=== QUALITY SUMMARY ===${NC}"
echo "Requirements analyzed: $requirements"
echo "Scenarios analyzed: $scenarios"
echo "Critical issues: $issues"
echo "Quality warnings: $warnings"
echo ""

# Calculate quality score
if [ "$requirements" -gt 0 ]; then
    quality_score=$((100 - (issues * 20) - (warnings * 2)))
    if [ "$quality_score" -lt 0 ]; then
        quality_score=0
    fi
else
    quality_score=100
fi

echo -e "${BLUE}Quality Score: $quality_score/100${NC}"

if [ "$issues" -gt 0 ]; then
    echo -e "${RED}❌ QUALITY CHECK FAILED${NC}"
    exit 1
elif [ "$warnings" -gt 10 ]; then
    echo -e "${YELLOW}⚠️  QUALITY CHECK WARNING${NC}"
    exit 0
else
    echo -e "${GREEN}✅ QUALITY CHECK PASSED${NC}"
    exit 0
fi