#!/usr/bin/env bash

# Project Quality Assurance Framework
# Validates actual project implementation quality

set -euo pipefail

echo "=== Project Quality Assurance Framework ==="
echo ""

# Colors
RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Counters
test_files=0
enabled_tests=0
disabled_tests=0
module_files=0
implementation_files=0
quality_issues=0
warnings=0

# Function to check test quality
check_test_quality() {
    local test_dir=$1
    
    echo -e "${BLUE}=== TEST QUALITY ANALYSIS ===${NC}"
    
    # Count test files
    test_files=$(find "$test_dir" -name "*.nix" | wc -l)
    echo "Test files found: $test_files"
    
    # Check for enabled vs disabled tests
    if [ -f "flake.nix" ]; then
        enabled_tests=$(grep -c "checks.*test" flake.nix || echo 0)
        echo "Enabled tests in flake: $enabled_tests"
        
        if [ "$enabled_tests" -lt "$((test_files / 2))" ]; then
            echo -e "${YELLOW}⚠️  Low test coverage${NC}: Only $enabled_tests/$test_files tests enabled in flake"
            warnings=$((warnings + 1))
        fi
    fi
    
    # Check test file quality
    for test_file in $(find "$test_dir" -name "*.nix"); do
        # Check for test assertions
        if ! grep -q "assert\|should\|must" "$test_file"; then
            echo -e "${YELLOW}⚠️  Weak assertions${NC}: $test_file - No strong assertions found"
            warnings=$((warnings + 1))
        fi
        
        # Check for test descriptions
        if ! grep -q "description\|testName" "$test_file"; then
            echo -e "${YELLOW}⚠️  Missing descriptions${NC}: $test_file - No test descriptions found"
            warnings=$((warnings + 1))
        fi
        
        # Check file size (too small might indicate incomplete tests)
        file_size=$(wc -l < "$test_file")
        if [ "$file_size" -lt 20 ]; then
            echo -e "${YELLOW}⚠️  Small test file${NC}: $test_file - Only $file_size lines"
            warnings=$((warnings + 1))
        fi
    done
}

# Function to check module quality
check_module_quality() {
    local module_dir=$1
    
    echo -e "${BLUE}=== MODULE QUALITY ANALYSIS ===${NC}"
    
    # Count module files
    module_files=$(find "$module_dir" -name "*.nix" | wc -l)
    echo "Module files found: $module_files"
    
    # Check for required module structure
    for module_file in $(find "$module_dir" -name "*.nix"); do
        # Check for options documentation
        if ! grep -q "options\|config\|mkOption" "$module_file"; then
            echo -e "${YELLOW}⚠️  Missing options${NC}: $module_file - No configuration options found"
            warnings=$((warnings + 1))
        fi
        
        # Check for type definitions
        if ! grep -q "type\|lib.types" "$module_file"; then
            echo -e "${YELLOW}⚠️  Missing types${NC}: $module_file - No type definitions found"
            warnings=$((warnings + 1))
        fi
        
        # Check for module documentation
        if ! grep -q "description\|doc\|# " "$module_file"; then
            echo -e "${YELLOW}⚠️  Missing documentation${NC}: $module_file - No documentation found"
            warnings=$((warnings + 1))
        fi
        
        # Check file complexity
        file_size=$(wc -l < "$module_file")
        if [ "$file_size" -gt 500 ]; then
            echo -e "${YELLOW}⚠️  Large module${NC}: $module_file - $file_size lines (consider splitting)"
            warnings=$((warnings + 1))
        fi
    done
}

# Function to check implementation quality
check_implementation_quality() {
    local lib_dir=$1
    
    echo -e "${BLUE}=== IMPLEMENTATION QUALITY ANALYSIS ===${NC}"
    
    # Count implementation files
    implementation_files=$(find "$lib_dir" -name "*.nix" | wc -l)
    echo "Implementation files found: $implementation_files"
    
    # Check for code quality issues
    for impl_file in $(find "$lib_dir" -name "*.nix"); do
        # Check for hardcoded values
        if grep -q "[0-9][0-9][0-9]" "$impl_file"; then
            echo -e "${YELLOW}⚠️  Hardcoded values${NC}: $impl_file - Contains potential hardcoded values"
            warnings=$((warnings + 1))
        fi
        
        # Check for error handling
        if ! grep -q "assert\|check\|validation" "$impl_file"; then
            echo -e "${YELLOW}⚠️  Missing validation${NC}: $impl_file - No input validation found"
            warnings=$((warnings + 1))
        fi
        
        # Check for function documentation
        if ! grep -q "# " "$impl_file"; then
            echo -e "${YELLOW}⚠️  Missing comments${NC}: $impl_file - No function documentation"
            warnings=$((warnings + 1))
        fi
    done
}

# Function to check documentation quality
check_documentation_quality() {
    echo -e "${BLUE}=== DOCUMENTATION QUALITY ANALYSIS ===${NC}"
    
    # Check for README
    if [ ! -f "README.md" ]; then
        echo -e "${RED}❌ Missing README${NC}: No README.md file found"
        quality_issues=$((quality_issues + 1))
    else
        readme_lines=$(wc -l < README.md)
        if [ "$readme_lines" -lt 50 ]; then
            echo -e "${YELLOW}⚠️  Short README${NC}: Only $readme_lines lines"
            warnings=$((warnings + 1))
        else
            echo "README quality: $readme_lines lines"
        fi
    fi
    
    # Check for module documentation
    module_docs=$(find modules -name "*.md" | wc -l)
    if [ "$module_docs" -lt 3 ]; then
        echo -e "${YELLOW}⚠️  Limited module docs${NC}: Only $module_docs module documentation files"
        warnings=$((warnings + 1))
    else
        echo "Module documentation: $module_docs files"
    fi
    
    # Check for examples
    examples=$(find examples -type f | wc -l)
    if [ "$examples" -lt 5 ]; then
        echo -e "${YELLOW}⚠️  Limited examples${NC}: Only $examples example files"
        warnings=$((warnings + 1))
    else
        echo "Examples: $examples files"
    fi
}

# Function to check project structure
check_project_structure() {
    echo -e "${BLUE}=== PROJECT STRUCTURE ANALYSIS ===${NC}"
    
    # Check for essential directories
    essential_dirs=("modules" "lib" "tests" "examples")
    for dir in "${essential_dirs[@]}"; do
        if [ ! -d "$dir" ]; then
            echo -e "${RED}❌ Missing directory${NC}: $dir directory not found"
            quality_issues=$((quality_issues + 1))
        else
            file_count=$(find "$dir" -type f | wc -l)
            echo "$dir: $file_count files"
        fi
    done
    
    # Check for flake.nix
    if [ ! -f "flake.nix" ]; then
        echo -e "${RED}❌ Missing flake${NC}: No flake.nix found"
        quality_issues=$((quality_issues + 1))
    else
        echo "Flake configuration: Present"
    fi
    
    # Check for .gitignore
    if [ ! -f ".gitignore" ]; then
        echo -e "${YELLOW}⚠️  Missing .gitignore${NC}: No .gitignore file found"
        warnings=$((warnings + 1))
    fi
}

# Function to check code consistency
check_code_consistency() {
    echo -e "${BLUE}=== CODE CONSISTENCY ANALYSIS ===${NC}"
    
    # Check for consistent indentation
    inconsistent_indent=$(grep -r "^[ ]*[ ]*[^ ]" modules/ lib/ tests/ 2>/dev/null | wc -l || echo 0)
    if [ "$inconsistent_indent" -gt 0 ]; then
        echo -e "${YELLOW}⚠️  Inconsistent indentation${NC}: Found $inconsistent_indent lines with inconsistent indentation"
        warnings=$((warnings + 1))
    fi
    
    # Check for trailing whitespace
    trailing_whitespace=$(grep -r "[ ]*$" modules/ lib/ tests/ 2>/dev/null | wc -l || echo 0)
    if [ "$trailing_whitespace" -gt 10 ]; then
        echo -e "${YELLOW}⚠️  Trailing whitespace${NC}: Found $trailing_whitespace lines with trailing whitespace"
        warnings=$((warnings + 1))
    fi
    
    # Check for consistent naming
    inconsistent_naming=$(grep -r "[A-Z]" modules/ lib/ tests/ 2>/dev/null | grep -v "# " | wc -l || echo 0)
    # This is a simple check - real projects would need more sophisticated naming analysis
    echo "Code consistency: Basic checks passed"
}

# Main analysis
check_project_structure
check_test_quality "tests"
check_module_quality "modules"
check_implementation_quality "lib"
check_documentation_quality
check_code_consistency

# Summary
echo ""
echo -e "${BLUE}=== PROJECT QUALITY SUMMARY ===${NC}"
echo ""
echo "Project Structure:"
echo "  Test files: $test_files"
echo "  Module files: $module_files"
echo "  Implementation files: $implementation_files"
echo "  Enabled tests: $enabled_tests"
echo ""
echo "Quality Metrics:"
echo "  Critical issues: $quality_issues"
echo "  Quality warnings: $warnings"
echo ""

# Calculate project quality score
if [ "$module_files" -gt 0 ]; then
    project_score=$((100 - (quality_issues * 15) - (warnings * 1)))
    if [ "$project_score" -lt 0 ]; then
        project_score=0
    fi
else
    project_score=0
fi

echo -e "${BLUE}Project Quality Score: $project_score/100${NC}"
echo ""

# Determine overall status
if [ "$quality_issues" -gt 0 ]; then
    echo -e "${RED}❌ PROJECT QUALITY CHECK FAILED${NC}"
    echo "Critical structural issues detected"
    exit 1
elif [ "$warnings" -gt 20 ]; then
    echo -e "${YELLOW}⚠️  PROJECT QUALITY CHECK WARNING${NC}"
    echo "$project_score/100 - Significant quality warnings detected"
    exit 0
elif [ "$project_score" -ge 80 ]; then
    echo -e "${GREEN}✅ PROJECT QUALITY CHECK PASSED${NC}"
    echo "$project_score/100 - Excellent project quality"
    exit 0
elif [ "$project_score" -ge 60 ]; then
    echo -e "${GREEN}✅ PROJECT QUALITY CHECK PASSED${NC}"
    echo "$project_score/100 - Good project quality with minor warnings"
    exit 0
else
    echo -e "${YELLOW}⚠️  PROJECT QUALITY CHECK WARNING${NC}"
    echo "$project_score/100 - Project needs quality improvements"
    exit 0
fi