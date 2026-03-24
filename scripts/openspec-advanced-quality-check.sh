#!/usr/bin/env bash

# Advanced OpenSpec Quality Assurance Framework
# Comprehensive quality checks with configurable rules

set -euo pipefail

# Load configuration
CONFIG_FILE="scripts/openspec-quality-config.json"
if [ ! -f "$CONFIG_FILE" ]; then
    echo "Error: Configuration file $CONFIG_FILE not found"
    exit 1
fi

# Parse JSON config (simple parsing for key values)
MIN_SCENARIOS=$(grep -o '"min_scenarios_per_requirement": *[0-9]*' "$CONFIG_FILE" | grep -o '[0-9]*')
MAX_REQ_LENGTH=$(grep -o '"max_requirement_length": *[0-9]*' "$CONFIG_FILE" | grep -o '[0-9]*')
MIN_REQ_LENGTH=$(grep -o '"min_requirement_length": *[0-9]*' "$CONFIG_FILE" | grep -o '[0-9]*')
MAX_LINE_LENGTH=$(grep -o '"max_line_length": *[0-9]*' "$CONFIG_FILE" | grep -o '[0-9]*')
MIN_COMPLETION=$(grep -o '"min_completion_percentage": *[0-9]*' "$CONFIG_FILE" | grep -o '[0-9]*')

# Colors
RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Global counters
declare -A stats=(
    ["total_requirements"]=0
    ["quality_issues"]=0
    ["warnings"]=0
    ["passed_checks"]=0
    ["total_scenarios"]=0
    ["long_requirements"]=0
    ["short_requirements"]=0
    ["incomplete_scenarios"]=0
    ["vague_language"]=0
    ["passive_voice"]=0
    ["weasel_words"]=0
)

# Quality thresholds
QUALITY_THRESHOLDS=(
    "requirements_per_file:5:15"
    "scenarios_per_requirement:2:4"
    "completion_percentage:30:100"
    "line_length:0:120"
)

echo -e "${BLUE}=== Advanced OpenSpec Quality Assurance Framework ===${NC}"
echo "Configuration loaded from: $CONFIG_FILE"
echo ""

# Function to analyze requirement quality
analyze_requirement() {
    local file=$1
    local requirement_text=$2
    local scenarios_count=$3
    
    stats["total_requirements"]=$((stats["total_requirements"] + 1))
    stats["total_scenarios"]=$((stats["total_scenarios"] + scenarios_count))
    
    local issues_found=0
    local warnings_found=0
    local checks_passed=0
    
    # Check 1: Minimum scenarios per requirement
    if [ "$scenarios_count" -lt "$MIN_SCENARIOS" ]; then
        echo -e "${RED}❌ CRITICAL${NC}: $file - Only $scenarios_count scenario(s), minimum is $MIN_SCENARIOS"
        stats["quality_issues"]=$((stats["quality_issues"] + 1))
        stats["incomplete_scenarios"]=$((stats["incomplete_scenarios"] + 1))
        issues_found=$((issues_found + 1))
    else
        checks_passed=$((checks_passed + 1))
    fi
    
    # Check 2: Requirement length analysis
    local req_length=${#requirement_text}
    if [ "$req_length" -lt "$MIN_REQ_LENGTH" ]; then
        echo -e "${RED}❌ CRITICAL${NC}: $file - Requirement too short ($req_length chars < $MIN_REQ_LENGTH)"
        stats["quality_issues"]=$((stats["quality_issues"] + 1))
        stats["short_requirements"]=$((stats["short_requirements"] + 1))
        issues_found=$((issues_found + 1))
    elif [ "$req_length" -gt "$MAX_REQ_LENGTH" ]; then
        echo -e "${YELLOW}⚠️  WARNING${NC}: $file - Requirement very long ($req_length chars > $MAX_REQ_LENGTH)"
        stats["warnings"]=$((stats["warnings"] + 1))
        stats["long_requirements"]=$((stats["long_requirements"] + 1))
        warnings_found=$((warnings_found + 1))
    else
        checks_passed=$((checks_passed + 1))
    fi
    
    # Check 3: Normative language
    if [[ ! "$requirement_text" =~ (SHALL|MUST) ]]; then
        echo -e "${YELLOW}⚠️  WARNING${NC}: $file - Missing normative language (SHALL/MUST)"
        stats["warnings"]=$((stats["warnings"] + 1))
        warnings_found=$((warnings_found + 1))
    else
        checks_passed=$((checks_passed + 1))
    fi
    
    # Check 4: Scenario quality
    if [ "$scenarios_count" -eq 0 ]; then
        echo -e "${RED}❌ CRITICAL${NC}: $file - No scenarios defined"
        stats["quality_issues"]=$((stats["quality_issues"] + 1))
        issues_found=$((issues_found + 1))
    fi
    
    return $((issues_found + warnings_found))
}

# Function to check for quality patterns
check_quality_patterns() {
    local file=$1
    local content=$2
    
    # Check for vague language
    if grep -qi "etc\." "$file" || grep -qi "and so on" "$file"; then
        echo -e "${YELLOW}⚠️  WARNING${NC}: $file - Contains vague language"
        stats["warnings"]=$((stats["warnings"] + 1))
        stats["vague_language"]=$((stats["vague_language"] + 1))
    fi
    
    # Check for passive voice
    if grep -qi "should be\|can be\|will be\|must be" "$file"; then
        echo -e "${YELLOW}⚠️  WARNING${NC}: $file - Contains passive voice patterns"
        stats["warnings"]=$((stats["warnings"] + 1))
        stats["passive_voice"]=$((stats["passive_voice"] + 1))
    fi
    
    # Check for weasel words
    if grep -qi "typically\|usually\|often\|sometimes\|may be\|could be" "$file"; then
        echo -e "${YELLOW}⚠️  WARNING${NC}: $file - Contains weasel words"
        stats["warnings"]=$((stats["warnings"] + 1))
        stats["weasel_words"]=$((stats["weasel_words"] + 1))
    fi
}

# Function to analyze task completion
task_completion_analysis() {
    local file=$1
    
    local incomplete_tasks=$(grep -c "^- \[ \]" "$file" 2>/dev/null || echo 0)
    local total_tasks=$(grep -c "^- \[" "$file" 2>/dev/null || echo 0)
    
    if [ "$total_tasks" -gt 0 ]; then
        local completion_percentage=$((100 * (total_tasks - incomplete_tasks) / total_tasks))
        
        if [ "$completion_percentage" -lt "$MIN_COMPLETION" ]; then
            echo -e "${YELLOW}⚠️  WARNING${NC}: $file - Low completion: $completion_percentage% ($((total_tasks - incomplete_tasks))/$total_tasks)"
            stats["warnings"]=$((stats["warnings"] + 1))
            return 1
        else
            echo -e "${GREEN}✅ GOOD${NC}: $file - Completion: $completion_percentage%"
            return 0
        fi
    fi
    
    return 0
}

# Function to check proposal completeness
check_proposal_completeness() {
    local file=$1
    
    local missing_sections=0
    
    # Check for required sections
    if ! grep -q "## Why" "$file"; then
        echo -e "${RED}❌ CRITICAL${NC}: $file - Missing 'Why' section"
        stats["quality_issues"]=$((stats["quality_issues"] + 1))
        missing_sections=$((missing_sections + 1))
    fi
    
    if ! grep -q "## What Changes" "$file"; then
        echo -e "${RED}❌ CRITICAL${NC}: $file - Missing 'What Changes' section"
        stats["quality_issues"]=$((stats["quality_issues"] + 1))
        missing_sections=$((missing_sections + 1))
    fi
    
    if ! grep -q "## Impact" "$file"; then
        echo -e "${RED}❌ CRITICAL${NC}: $file - Missing 'Impact' section"
        stats["quality_issues"]=$((stats["quality_issues"] + 1))
        missing_sections=$((missing_sections + 1))
    fi
    
    if [ "$missing_sections" -eq 0 ]; then
        echo -e "${GREEN}✅ GOOD${NC}: $file - All required sections present"
    fi
    
    return $missing_sections
}

# Main analysis functions
echo -e "${BLUE}=== SPEC FILE ANALYSIS ===${NC}"

spec_files=$(find openspec/changes -name "spec.md" ! -path "*/archive/*" | sort)
if [ -z "$spec_files" ]; then
    echo "No active spec files found"
else
    for spec_file in $spec_files; do
        echo ""
        echo -e "${BLUE}Analyzing: $spec_file${NC}"
        
        # Read file content
        content=$(cat "$spec_file")
        
        # Check quality patterns
        check_quality_patterns "$spec_file" "$content"
        
        # Parse and analyze requirements
        current_requirement=""
        scenario_count=0
        line_number=1
        
        while IFS= read -r line || [ -n "$line" ]; do
            # Check line length
            line_length=${#line}
            if [ "$line_length" -gt "$MAX_LINE_LENGTH" ]; then
                echo -e "${YELLOW}⚠️  WARNING${NC}: Line $line_number - Exceeds max length ($line_length > $MAX_LINE_LENGTH)"
                stats["warnings"]=$((stats["warnings"] + 1))
            fi
            
            # Parse requirement sections
            if [[ "$line" =~ ^"### Requirement:" ]]; then
                # Analyze previous requirement if exists
                if [ -n "$current_requirement" ]; then
                    analyze_requirement "$spec_file" "$current_requirement" "$scenario_count"
                fi
                
                # Start new requirement
                current_requirement="$line"
                scenario_count=0
            elif [[ "$line" =~ ^"#### Scenario:" ]]; then
                scenario_count=$((scenario_count + 1))
                current_requirement+="\n$line"
            elif [[ -n "$current_requirement" ]]; then
                current_requirement+="\n$line"
            fi
            
            line_number=$((line_number + 1))
        done < "$spec_file"
        
        # Analyze last requirement
        if [ -n "$current_requirement" ]; then
            analyze_requirement "$spec_file" "$current_requirement" "$scenario_count"
        fi
    done
fi

echo ""
echo -e "${BLUE}=== TASK FILE ANALYSIS ===${NC}"

task_files=$(find openspec/changes -name "tasks.md" ! -path "*/archive/*" | sort)
for task_file in $task_files; do
    echo ""
    echo -e "${BLUE}Analyzing: $task_file${NC}"
    
    # Check task completion
    task_completion_analysis "$task_file"
    
    # Check for vague tasks
    if grep -qi "TBD\|TODO\|tbd\|todo" "$task_file"; then
        echo -e "${YELLOW}⚠️  WARNING${NC}: $task_file - Contains placeholder tasks"
        stats["warnings"]=$((stats["warnings"] + 1))
    fi
    
    # Check quality patterns
    check_quality_patterns "$task_file" "$(cat "$task_file")"
    
    # Check line lengths
    line_number=1
    while IFS= read -r line || [ -n "$line" ]; do
        local line_length=${#line}
        if [ "$line_length" -gt "$MAX_LINE_LENGTH" ]; then
            echo -e "${YELLOW}⚠️  WARNING${NC}: Line $line_number - Exceeds max length ($line_length > $MAX_LINE_LENGTH)"
            stats["warnings"]=$((stats["warnings"] + 1))
        fi
        line_number=$((line_number + 1))
    done < "$task_file"
done

echo ""
echo -e "${BLUE}=== PROPOSAL FILE ANALYSIS ===${NC}"

proposal_files=$(find openspec/changes -name "proposal.md" ! -path "*/archive/*" | sort)
for proposal_file in $proposal_files; do
    echo ""
    echo -e "${BLUE}Analyzing: $proposal_file${NC}"
    
    # Check proposal completeness
    check_proposal_completeness "$proposal_file"
    
    # Check quality patterns
    check_quality_patterns "$proposal_file" "$(cat "$proposal_file")"
    
    # Check line lengths
    line_number=1
    while IFS= read -r line || [ -n "$line" ]; do
        line_length=${#line}
        if [ "$line_length" -gt "$MAX_LINE_LENGTH" ]; then
            echo -e "${YELLOW}⚠️  WARNING${NC}: Line $line_number - Exceeds max length ($line_length > $MAX_LINE_LENGTH)"
            stats["warnings"]=$((stats["warnings"] + 1))
        fi
        line_number=$((line_number + 1))
    done < "$task_file"
    
    line_number=1
    while IFS= read -r line || [ -n "$line" ]; do
        line_length=${#line}
        if [ "$line_length" -gt "$MAX_LINE_LENGTH" ]; then
            echo -e "${YELLOW}⚠️  WARNING${NC}: Line $line_number - Exceeds max length ($line_length > $MAX_LINE_LENGTH)"
            stats["warnings"]=$((stats["warnings"] + 1))
        fi
        line_number=$((line_number + 1))
    done < "$proposal_file"
done

# Generate comprehensive report
echo ""
echo -e "${BLUE}=== QUALITY ASSURANCE REPORT ===${NC}"
echo "Configuration: $CONFIG_FILE"
echo "Analysis Date: $(date)"
echo ""

echo -e "${BLUE}Requirements Analysis:${NC}"
echo "  Total Requirements: ${stats["total_requirements"]}"
echo "  Total Scenarios: ${stats["total_scenarios"]}"
echo "  Average Scenarios/Requirement: $((stats["total_scenarios"] / (stats["total_requirements"] + 1)))"
echo "  Long Requirements: ${stats["long_requirements"]}"
echo "  Short Requirements: ${stats["short_requirements"]}"
echo "  Incomplete Scenarios: ${stats["incomplete_scenarios"]}"
echo ""

echo -e "${BLUE}Quality Issues Breakdown:${NC}"
echo "  Vague Language: ${stats["vague_language"]}"
echo "  Passive Voice: ${stats["passive_voice"]}"
echo "  Weasel Words: ${stats["weasel_words"]}"
echo ""

echo -e "${BLUE}Summary Statistics:${NC}"
echo "  Critical Issues: ${stats["quality_issues"]}"
echo "  Warnings: ${stats["warnings"]}"
echo "  Total Checks: $((stats["quality_issues"] + stats["warnings"] + stats["passed_checks"]))"
echo ""

# Calculate quality score
if [ "${stats["total_requirements"]}" -gt 0 ]; then
    quality_score=$((100 - (stats["quality_issues"] * 10) - (stats["warnings"] * 2)))
    if [ "$quality_score" -lt 0 ]; then
        quality_score=0
    fi
else
    quality_score=100
fi

echo -e "${BLUE}Quality Score: $quality_score/100${NC}"
echo ""

# Determine overall status
if [ "${stats["quality_issues"]}" -gt 0 ]; then
    echo -e "${RED}❌ QUALITY CHECK FAILED${NC}"
    echo "Critical issues require immediate attention"
    exit 1
elif [ "${stats["warnings"]}" -gt 10 ]; then
    echo -e "${YELLOW}⚠️  QUALITY CHECK WARNING${NC}"
    echo "$quality_score/100 - Consider addressing warnings for better quality"
    exit 0
else
    echo -e "${GREEN}✅ QUALITY CHECK PASSED${NC}"
    echo "$quality_score/100 - All quality standards met"
    exit 0
fi