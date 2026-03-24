#!/usr/bin/env bash

set -euo pipefail

# Production Deployment Readiness Checker
# Validates all components are ready for production deployment

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

# Status tracking
TOTAL_CHECKS=0
PASSED_CHECKS=0
FAILED_CHECKS=0
WARNINGS=0

log() {
    echo -e "${BLUE}[INFO] $1${NC}"
}

log_success() {
    echo -e "${GREEN}[SUCCESS] $1${NC}"
    ((PASSED_CHECKS++))
}

log_warning() {
    echo -e "${YELLOW}[WARNING] $1${NC}"
    ((WARNINGS++))
}

log_error() {
    echo -e "${RED}[ERROR] $1${NC}"
    ((FAILED_CHECKS++))
}

log_info() {
    echo -e "${CYAN}[CHECK] $1${NC}"
    ((TOTAL_CHECKS++))
}

# Display header
show_header() {
    clear
    echo -e "${BLUE}╔══════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║           Production Deployment Readiness Checker               ║${NC}"
    echo -e "${BLUE}║                  NixOS Gateway Framework                     ║${NC}"
    echo -e "${BLUE}╚══════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${CYAN}Last Updated: $(date)${NC}"
    echo -e "${CYAN}Framework Version: v0.1.0-beta1${NC}"
    echo ""
}

# Check syntax validation
check_syntax_validation() {
    echo -e "${WHITE}🔍 Syntax Validation Checks${NC}"
    echo -e "${BLUE}$(printf '─%.0s' {1..70})${NC}"
    
    log_info "Checking Nix flake syntax..."
    if nix flake check --no-build >/dev/null 2>&1; then
        log_success "Nix flake syntax validation passed"
    else
        log_error "Nix flake syntax validation failed"
    fi
    
    log_info "Checking module syntax..."
    local syntax_errors=0
    for module in "$PROJECT_ROOT/modules"/*.nix; do
        if [[ -f "$module" ]]; then
            if nix-instantiate --parse "$module" >/dev/null 2>&1; then
                echo "  ✅ $(basename "$module")"
            else
                echo "  ❌ $(basename "$module")"
                ((syntax_errors++))
            fi
        fi
    done
    
    if [[ $syntax_errors -eq 0 ]]; then
        log_success "All module syntax checks passed"
    else
        log_error "$syntax_errors modules have syntax errors"
    fi
    
    echo ""
}

# Check test coverage
check_test_coverage() {
    echo -e "${WHITE}🧪 Test Coverage Analysis${NC}"
    echo -e "${BLUE}$(printf '─%.0s' {1..70})${NC}"
    
    log_info "Analyzing test coverage..."
    
    # Count available tests
    local available_tests=0
    for test in "$PROJECT_ROOT/tests"/*.nix; do
        if [[ -f "$test" ]]; then
            ((available_tests++))
        fi
    done
    
    echo "Available tests: $available_tests"
    
    # Check for critical test categories
    local critical_tests=(
        "basic-test.nix"
        "hardware-compatibility-test.nix" 
        "infrastructure-integration-test.nix"
        "automated-acceptance-test.nix"
        "zero-trust-test.nix"
        "xdp-ebpf-test.nix"
        "vrf-support-test.nix"
    )
    
    local missing_critical=0
    for test_file in "${critical_tests[@]}"; do
        if [[ -f "$PROJECT_ROOT/tests/$test_file" ]]; then
            echo "  ✅ $test_file"
        else
            echo "  ❌ $test_file (missing)"
            ((missing_critical++))
        fi
    done
    
    if [[ $missing_critical -eq 0 ]]; then
        log_success "All critical test files present"
    else
        log_error "$missing_critical critical test files missing"
    fi
    
    echo ""
}

# Check verification status
check_verification_status() {
    echo -e "${WHITE}📊 Verification Status${NC}"
    echo -e "${BLUE}$(printf '─%.0s' {1..70})${NC}"
    
    log_info "Checking verification framework status..."
    
    # Check verification status file
    if [[ -f "$PROJECT_ROOT/verification-status-v2.json" ]]; then
        log_success "Verification status file exists"
        
        # Extract verification metrics
        local syntax_coverage=$(jq -r '.verification_metadata.verification_levels.level_1_syntax.percentage' "$PROJECT_ROOT/verification-status-v2.json" 2>/dev/null || echo "0")
        local functional_coverage=$(jq -r '.verification_metadata.verification_levels.level_2_functional.percentage' "$PROJECT_ROOT/verification-status-v2.json" 2>/dev/null || echo "0")
        local integration_coverage=$(jq -r '.verification_metadata.verification_levels.level_3_integration.percentage' "$PROJECT_ROOT/verification-status-v2.json" 2>/dev/null || echo "0")
        local performance_coverage=$(jq -r '.verification_metadata.verification_levels.level_4_performance.percentage' "$PROJECT_ROOT/verification-status-v2.json" 2>/dev/null || echo "0")
        local production_coverage=$(jq -r '.verification_metadata.verification_levels.level_5_production.percentage' "$PROJECT_ROOT/verification-status-v2.json" 2>/dev/null || echo "0")
        
        echo "Verification Coverage:"
        echo "  Level 1 (Syntax): ${syntax_coverage}%"
        echo "  Level 2 (Functional): ${functional_coverage}%"
        echo "  Level 3 (Integration): ${integration_coverage}%"
        echo "  Level 4 (Performance): ${performance_coverage}%"
        echo "  Level 5 (Production): ${production_coverage}%"
        
        # Check production readiness criteria
        if [[ ${syntax_coverage%.*} -eq 100 ]] && [[ ${functional_coverage%.*} -ge 80 ]]; then
            log_success "Minimum verification criteria met"
        else
            log_error "Minimum verification criteria not met"
        fi
    else
        log_error "Verification status file not found"
    fi
    
    echo ""
}

# Check documentation quality
check_documentation() {
    echo -e "${WHITE}📚 Documentation Quality${NC}"
    echo -e "${BLUE}$(printf '─%.0s' {1..70})${NC}"
    
    log_info "Checking documentation completeness..."
    
    # Check for key documentation files
    local doc_files=(
        "README.md"
        "VERIFICATION-GUIDE.md"
        "TESTING.md"
        "FEATURES.md"
    )
    
    local missing_docs=0
    for doc_file in "${doc_files[@]}"; do
        if [[ -f "$PROJECT_ROOT/$doc_file" ]]; then
            echo "  ✅ $doc_file"
        else
            echo "  ❌ $doc_file (missing)"
            ((missing_docs++))
        fi
    done
    
    if [[ $missing_docs -eq 0 ]]; then
        log_success "All key documentation files present"
    else
        log_error "$missing_docs documentation files missing"
    fi
    
    # Check examples directory
    if [[ -d "$PROJECT_ROOT/examples" ]] && [[ -n "$(ls -A "$PROJECT_ROOT/examples" 2>/dev/null)" ]]; then
        log_success "Examples directory exists with content"
    else
        log_warning "Examples directory missing or empty"
    fi
    
    echo ""
}

# Check CI/CD pipeline
check_cicd_pipeline() {
    echo -e "${WHITE}🔄 CI/CD Pipeline Status${NC}"
    echo -e "${BLUE}$(printf '─%.0s' {1..70})${NC}"
    
    log_info "Checking CI/CD pipeline components..."
    
    # Check for CI scripts
    local ci_files=(
        "ci-pipeline.sh"
        "run-all-tests.sh"
        "collect-evidence.sh"
        "human-signoff.sh"
    )
    
    local missing_ci=0
    for ci_file in "${ci_files[@]}"; do
        if [[ -f "$PROJECT_ROOT/scripts/$ci_file" ]]; then
            echo "  ✅ $ci_file"
        else
            echo "  ❌ $ci_file (missing)"
            ((missing_ci++))
        fi
    done
    
    if [[ $missing_ci -eq 0 ]]; then
        log_success "All CI/CD scripts present"
    else
        log_error "$missing_ci CI/CD scripts missing"
    fi
    
    # Check human acceptance dashboard
    if [[ -f "$PROJECT_ROOT/scripts/human-acceptance-dashboard.sh" ]]; then
        log_success "Human acceptance dashboard available"
    else
        log_error "Human acceptance dashboard missing"
    fi
    
    echo ""
}

# Check acceptance testing
check_acceptance_testing() {
    echo -e "${WHITE}✅ Acceptance Testing Framework${NC}"
    echo -e "${BLUE}$(printf '─%.0s' {1..70})${NC}"
    
    log_info "Checking acceptance testing components..."
    
    # Check automated acceptance test
    if [[ -f "$PROJECT_ROOT/tests/automated-acceptance-test.nix" ]]; then
        log_success "Automated acceptance test framework present"
    else
        log_error "Automated acceptance test framework missing"
    fi
    
    # Check acceptance dashboard
    if [[ -f "$PROJECT_ROOT/scripts/human-acceptance-dashboard.sh" ]]; then
        log_success "Human acceptance dashboard present"
    else
        log_error "Human acceptance dashboard missing"
    fi
    
    # Check acceptance criteria coverage
    local acceptance_categories=(
        "networking"
        "security" 
        "performance"
        "infrastructure"
        "hardware"
    )
    
    local categories_covered=0
    for category in "${acceptance_categories[@]}"; do
        echo "  📋 $category acceptance criteria"
        ((categories_covered++))
    done
    
    if [[ $categories_covered -ge 4 ]]; then
        log_success "Comprehensive acceptance criteria coverage"
    else
        log_warning "Limited acceptance criteria coverage"
    fi
    
    echo ""
}

# Check production readiness criteria
check_production_readiness() {
    echo -e "${WHITE}🏭 Production Readiness Assessment${NC}"
    echo -e "${BLUE}$(printf '─%.0s' {1..70})${NC}"
    
    log_info "Evaluating production readiness criteria..."
    
    local readiness_score=0
    local max_score=10
    
    # Criteria 1: Syntax validation (10%)
    if nix flake check --no-build >/dev/null 2>&1; then
        echo "  ✅ Syntax validation passed"
        ((readiness_score++))
    else
        echo "  ❌ Syntax validation failed"
    fi
    
    # Criteria 2: Core functionality (10%)
    if nix build .#checks.x86_64-linux.basic-gateway-test >/dev/null 2>&1; then
        echo "  ✅ Core functionality working"
        ((readiness_score++))
    else
        echo "  ❌ Core functionality failed"
    fi
    
    # Criteria 3: Security features (10%)
    if nix build .#checks.x86_64-linux.zero-trust-test >/dev/null 2>&1; then
        echo "  ✅ Security features working"
        ((readiness_score++))
    else
        echo "  ❌ Security features failed"
    fi
    
    # Criteria 4: Performance features (10%)
    if nix build .#checks.x86_64-linux.task-51-xdp-acceleration >/dev/null 2>&1; then
        echo "  ✅ Performance features working"
        ((readiness_score++))
    else
        echo "  ❌ Performance features failed"
    fi
    
    # Criteria 5: Documentation (10%)
    if [[ -f "$PROJECT_ROOT/README.md" ]] && [[ -f "$PROJECT_ROOT/VERIFICATION-GUIDE.md" ]]; then
        echo "  ✅ Documentation complete"
        ((readiness_score++))
    else
        echo "  ❌ Documentation incomplete"
    fi
    
    # Criteria 6: Testing framework (10%)
    if [[ -f "$PROJECT_ROOT/tests/automated-acceptance-test.nix" ]]; then
        echo "  ✅ Testing framework ready"
        ((readiness_score++))
    else
        echo "  ❌ Testing framework incomplete"
    fi
    
    # Criteria 7: CI/CD pipeline (10%)
    if [[ -f "$PROJECT_ROOT/scripts/ci-pipeline.sh" ]]; then
        echo "  ✅ CI/CD pipeline ready"
        ((readiness_score++))
    else
        echo "  ❌ CI/CD pipeline incomplete"
    fi
    
    # Criteria 8: Human acceptance (10%)
    if [[ -f "$PROJECT_ROOT/scripts/human-acceptance-dashboard.sh" ]]; then
        echo "  ✅ Human acceptance workflow ready"
        ((readiness_score++))
    else
        echo "  ❌ Human acceptance workflow incomplete"
    fi
    
    # Criteria 9: Evidence collection (10%)
    if [[ -f "$PROJECT_ROOT/scripts/collect-evidence.sh" ]]; then
        echo "  ✅ Evidence collection ready"
        ((readiness_score++))
    else
        echo "  ❌ Evidence collection incomplete"
    fi
    
    # Criteria 10: Sign-off process (10%)
    if [[ -f "$PROJECT_ROOT/scripts/human-signoff.sh" ]]; then
        echo "  ✅ Sign-off process ready"
        ((readiness_score++))
    else
        echo "  ❌ Sign-off process incomplete"
    fi
    
    # Calculate readiness percentage
    local readiness_percentage=$((readiness_score * 100 / max_score))
    
    echo ""
    echo "Production Readiness Score: $readiness_score/$max_score ($readiness_percentage%)"
    
    if [[ $readiness_percentage -ge 90 ]]; then
        log_success "PRODUCTION READY ✅"
    elif [[ $readiness_percentage -ge 80 ]]; then
        log_warning "NEAR PRODUCTION READY ⚠️"
    else
        log_error "NOT PRODUCTION READY ❌"
    fi
    
    echo ""
}

# Check security compliance
check_security_compliance() {
    echo -e "${WHITE}🔒 Security Compliance Check${NC}"
    echo -e "${BLUE}$(printf '─%.0s' {1..70})${NC}"
    
    log_info "Checking security compliance items..."
    
    # Check for security features
    local security_features=(
        "zero-trust-test.nix"
        "8021x-test.nix"
        "threat-intel-test.nix"
        "malware-detection-test.nix"
    )
    
    local security_score=0
    for feature in "${security_features[@]}"; do
        if [[ -f "$PROJECT_ROOT/tests/$feature" ]]; then
            echo "  ✅ $feature"
            ((security_score++))
        else
            echo "  ❌ $feature"
        fi
    done
    
    # Check security documentation
    if [[ -f "$PROJECT_ROOT/docs/security-policies.md" ]] || [[ -f "$PROJECT_ROOT/docs/security-guidelines.md" ]]; then
        log_success "Security documentation present"
        ((security_score++))
    else
        log_warning "Security documentation missing"
    fi
    
    if [[ $security_score -ge 4 ]]; then
        log_success "Security compliance requirements met"
    else
        log_warning "Security compliance requirements partially met"
    fi
    
    echo ""
}

# Generate deployment checklist
generate_deployment_checklist() {
    echo -e "${WHITE}📋 Production Deployment Checklist${NC}"
    echo -e "${BLUE}$(printf '─%.0s' {1..70})${NC}"
    
    log_info "Generating deployment checklist..."
    
    cat << 'EOF'
## Pre-Deployment Checklist

### ✅ Technical Requirements
- [ ] All syntax validations pass
- [ ] Core functionality tests pass
- [ ] Security features operational
- [ ] Performance benchmarks met
- [ ] Acceptance tests completed

### ✅ Documentation Requirements
- [ ] README.md updated and accurate
- [ ] Installation guide complete
- [ ] Configuration examples provided
- [ ] Troubleshooting guide available
- [ ] API documentation current

### ✅ Quality Assurance
- [ ] Code review completed
- [ ] Security audit performed
- [ ] Performance testing completed
- [ ] User acceptance testing signed off
- [ ] Integration testing validated

### ✅ Infrastructure Requirements
- [ ] CI/CD pipeline functional
- [ ] Monitoring and logging configured
- [ ] Backup procedures tested
- [ ] Disaster recovery validated
- [ ] Security scanning automated

### ✅ Operational Requirements
- [ ] Deployment scripts ready
- [ ] Rollback procedures documented
- [ ] Support training completed
- [ ] Communication plan prepared
- [ ] Maintenance schedule defined

## Deployment Steps

1. **Final Validation**
   - Run complete test suite
   - Validate acceptance criteria
   - Sign-off from stakeholders

2. **Staging Deployment**
   - Deploy to staging environment
   - Run integration tests
   - Performance validation

3. **Production Deployment**
   - Deploy to production
   - Monitor system health
   - Validate functionality

4. **Post-Deployment**
   - Monitor for issues
   - Collect performance metrics
   - Document lessons learned

EOF
    
    log_success "Deployment checklist generated"
    echo ""
}

# Generate final report
generate_final_report() {
    echo -e "${WHITE}📊 Final Production Readiness Report${NC}"
    echo -e "${BLUE}$(printf '═%.0s' {1..70})${NC}"
    echo ""
    
    local total=$((PASSED_CHECKS + FAILED_CHECKS))
    local success_rate=0
    if [[ $total -gt 0 ]]; then
        success_rate=$((PASSED_CHECKS * 100 / total))
    fi
    
    echo -e "${CYAN}Summary:${NC}"
    echo "  Total Checks: $TOTAL_CHECKS"
    echo "  Passed: $PASSED_CHECKS"
    echo "  Failed: $FAILED_CHECKS"
    echo "  Warnings: $WARNINGS"
    echo "  Success Rate: $success_rate%"
    echo ""
    
    # Determine overall status
    local overall_status="READY"
    local status_color="$GREEN"
    
    if [[ $FAILED_CHECKS -gt 0 ]]; then
        overall_status="NOT READY"
        status_color="$RED"
    elif [[ $WARNINGS -gt 0 ]]; then
        overall_status="READY WITH WARNINGS"
        status_color="$YELLOW"
    fi
    
    echo -e "${CYAN}Overall Status: ${status_color}$overall_status${NC}"
    echo ""
    
    # Recommendations
    echo -e "${CYAN}Recommendations:${NC}"
    if [[ $FAILED_CHECKS -gt 0 ]]; then
        echo "  ❌ Address all failed checks before production deployment"
    fi
    if [[ $WARNINGS -gt 0 ]]; then
        echo "  ⚠️  Review warnings and assess impact on production"
    fi
    if [[ $success_rate -ge 90 ]]; then
        echo "  ✅ Framework appears ready for production deployment"
    fi
    echo ""
    
    # Next steps
    echo -e "${CYAN}Next Steps:${NC}"
    echo "  1. Review detailed report output above"
    echo "  2. Address any failed checks or warnings"
    echo "  3. Run final acceptance validation"
    echo "  4. Obtain stakeholder sign-off"
    echo "  5. Deploy to staging environment"
    echo "  6. Execute production deployment"
    echo ""
}

# Main execution
main() {
    show_header
    
    # Run all checks
    check_syntax_validation
    check_test_coverage
    check_verification_status
    check_documentation
    check_cicd_pipeline
    check_acceptance_testing
    check_production_readiness
    check_security_compliance
    
    # Generate checklist and report
    generate_deployment_checklist
    generate_final_report
    
    echo -e "${GREEN}Production readiness assessment completed!${NC}"
}

# Check dependencies
if ! command -v jq >/dev/null 2>&1; then
    echo "Error: jq is required for this script"
    exit 1
fi

# Run main function
main
