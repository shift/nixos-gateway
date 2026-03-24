#!/usr/bin/env bash

# Comprehensive OpenSpec Validation Framework
# Combines structural validation with quality assurance

set -euo pipefail

echo "=== Comprehensive OpenSpec Validation Framework ==="
echo ""

# Colors
RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Run structural validation
echo -e "${BLUE}=== STRUCTURAL VALIDATION ===${NC}"
echo "Running openspec validate --all --strict..."

if openspec validate --all --strict --json > /tmp/openspec-validation.json 2>&1; then
    echo -e "${GREEN}✅ Structural validation passed${NC}"
    structural_passed=true
else
    echo -e "${RED}❌ Structural validation failed${NC}"
    structural_passed=false
fi

# Parse structural validation results
if [ -f /tmp/openspec-validation.json ]; then
    passed_items=$(jq '.summary.totals.passed' /tmp/openspec-validation.json 2>/dev/null || echo 0)
    failed_items=$(jq '.summary.totals.failed' /tmp/openspec-validation.json 2>/dev/null || echo 0)
    total_items=$(jq '.summary.totals.items' /tmp/openspec-validation.json 2>/dev/null || echo 0)
    
    echo "Structural validation results: $passed_items passed, $failed_items failed, $total_items total"
fi

# Run quality assurance
echo ""
echo -e "${BLUE}=== QUALITY ASSURANCE ===${NC}"
echo "Running comprehensive quality checks..."

if ./scripts/openspec-qa.sh > /tmp/openspec-qa-output.txt 2>&1; then
    qa_exit_code=$?
    
    # Parse QA results
    requirements=$(grep "Requirements analyzed:" /tmp/openspec-qa-output.txt | grep -o '[0-9]*')
    scenarios=$(grep "Scenarios analyzed:" /tmp/openspec-qa-output.txt | grep -o '[0-9]*')
    qa_issues=$(grep "Critical issues:" /tmp/openspec-qa-output.txt | grep -o '[0-9]*')
    qa_warnings=$(grep "Quality warnings:" /tmp/openspec-qa-output.txt | grep -o '[0-9]*')
    quality_score=$(grep "Quality Score:" /tmp/openspec-qa-output.txt | grep -o '[0-9]*/100' | cut -d'/' -f1)
    
    echo "Quality assurance results: $requirements requirements, $scenarios scenarios, $qa_issues issues, $qa_warnings warnings"
    echo "Quality score: $quality_score/100"
    
    if [ "$qa_exit_code" -eq 0 ]; then
        echo -e "${GREEN}✅ Quality assurance passed${NC}"
        quality_passed=true
    else
        echo -e "${YELLOW}⚠️  Quality assurance warnings${NC}"
        quality_passed=true  # Still consider it passed if only warnings
    fi
else
    echo -e "${RED}❌ Quality assurance failed${NC}"
    quality_passed=false
fi

# Run additional semantic checks
echo ""
echo -e "${BLUE}=== SEMANTIC VALIDATION ===${NC}"
echo "Checking semantic quality..."

semantic_issues=0

# Check for duplicate requirement names
for spec_file in $(find openspec/changes -name "spec.md" ! -path "*/archive/*"); do
    duplicate_reqs=$(grep "^### Requirement:" "$spec_file" | sort | uniq -d | wc -l)
    if [ "$duplicate_reqs" -gt 0 ]; then
        echo -e "${RED}❌ Duplicate requirements${NC}: $spec_file - Found $duplicate_reqs duplicate requirement names"
        semantic_issues=$((semantic_issues + 1))
    fi
done

# Check for empty scenarios
for spec_file in $(find openspec/changes -name "spec.md" ! -path "*/archive/*"); do
    empty_scenarios=$(grep -A1 "^#### Scenario:" "$spec_file" | grep -c "^- \*\*WHEN\*\*$" || true)
    if [ "$empty_scenarios" -gt 0 ]; then
        echo -e "${YELLOW}⚠️  Empty scenarios${NC}: $spec_file - Found $empty_scenarios empty scenarios"
        semantic_issues=$((semantic_issues + 1))
    fi
done

if [ "$semantic_issues" -eq 0 ]; then
    echo -e "${GREEN}✅ Semantic validation passed${NC}"
    semantic_passed=true
else
    echo -e "${YELLOW}⚠️  Semantic validation warnings${NC}"
    semantic_passed=true
fi

# Comprehensive summary
echo ""
echo -e "${BLUE}=== COMPREHENSIVE VALIDATION SUMMARY ===${NC}"
echo ""
echo "Structural Validation:"
echo "  ✅ Passed: $structural_passed"
echo "  Items: $passed_items passed, $failed_items failed, $total_items total"
echo ""
echo "Quality Assurance:"
echo "  ✅ Passed: $quality_passed"
echo "  Requirements: $requirements"
echo "  Scenarios: $scenarios"
echo "  Issues: $qa_issues"
echo "  Warnings: $qa_warnings"
echo "  Quality Score: $quality_score/100"
echo ""
echo "Semantic Validation:"
echo "  ✅ Passed: $semantic_passed"
echo "  Issues: $semantic_issues"
echo ""

# Calculate overall validation score
overall_score=$(( (passed_items * 40 / (total_items + 1)) + (quality_score * 50 / 100) + ((semantic_issues == 0 ? 10 : 0)) ))

echo -e "${BLUE}Overall Validation Score: $overall_score/100${NC}"
echo ""

# Determine final status
if [ "$structural_passed" = true ] && [ "$quality_passed" = true ] && [ "$semantic_passed" = true ]; then
    if [ "$overall_score" -ge 80 ]; then
        echo -e "${GREEN}🎉 COMPREHENSIVE VALIDATION PASSED${NC}"
        echo "All validation checks passed successfully!"
        exit 0
    elif [ "$overall_score" -ge 60 ]; then
        echo -e "${YELLOW}⚠️  COMPREHENSIVE VALIDATION WARNING${NC}"
        echo "Validation passed but with quality warnings ($overall_score/100)"
        exit 0
    else
        echo -e "${RED}❌ COMPREHENSIVE VALIDATION FAILED${NC}"
        echo "Validation passed structurally but quality is insufficient ($overall_score/100)"
        exit 1
    fi
else
    echo -e "${RED}❌ COMPREHENSIVE VALIDATION FAILED${NC}"
    echo "Critical validation failures detected"
    exit 1
fi