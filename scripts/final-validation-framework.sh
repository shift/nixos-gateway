#!/usr/bin/env bash

# Final Comprehensive Validation Framework
# Combines structural, quality, and project validation

set -euo pipefail

echo "=== FINAL COMPREHENSIVE VALIDATION FRAMEWORK ==="
echo ""

# Colors
RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Run all validation steps
echo -e "${BLUE}=== STEP 1: STRUCTURAL VALIDATION ===${NC}"
./scripts/comprehensive-validation.sh
structural_result=$?

echo ""
echo -e "${BLUE}=== STEP 2: PROJECT QUALITY VALIDATION ===${NC}"
./scripts/project-quality-check.sh
project_result=$?

echo ""
echo -e "${BLUE}=== STEP 3: OPENSPEC QUALITY ASSURANCE ===${NC}"
./scripts/openspec-qa.sh
qa_result=$?

# Parse results from each validation
structural_score=$(./scripts/comprehensive-validation.sh 2>&1 | grep "Overall Validation Score:" | grep -o '[0-9]*/100' | cut -d'/' -f1 || echo 0)
project_score=$(./scripts/project-quality-check.sh 2>&1 | grep "Project Quality Score:" | grep -o '[0-9]*/100' | cut -d'/' -f1 || echo 0)
qa_score=$(./scripts/openspec-qa.sh 2>&1 | grep "Quality Score:" | grep -o '[0-9]*/100' | cut -d'/' -f1 || echo 0)

# Calculate comprehensive score
comprehensive_score=$(( (structural_score * 40 / 100) + (project_score * 40 / 100) + (qa_score * 20 / 100) ))

echo ""
echo -e "${BLUE}=== COMPREHENSIVE VALIDATION RESULTS ===${NC}"
echo ""
echo "Structural Validation: $structural_score/100"
echo "Project Quality: $project_score/100"
echo "OpenSpec Quality: $qa_score/100"
echo ""
echo -e "${BLUE}COMPREHENSIVE SCORE: $comprehensive_score/100${NC}"
echo ""

# Determine final status
if [ "$comprehensive_score" -ge 80 ]; then
    echo -e "${GREEN}🎉 COMPREHENSIVE VALIDATION PASSED${NC}"
    echo "Project meets high quality standards!"
    exit 0
elif [ "$comprehensive_score" -ge 60 ]; then
    echo -e "${YELLOW}⚠️  COMPREHENSIVE VALIDATION WARNING${NC}"
    echo "Project quality is acceptable but needs improvements"
    exit 0
else
    echo -e "${RED}❌ COMPREHENSIVE VALIDATION FAILED${NC}"
    echo "Project requires significant quality improvements"
    exit 1
fi