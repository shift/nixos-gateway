# Automated Test Execution Pipeline

## CI/CD Pipeline Architecture

```yaml
# .github/workflows/comprehensive-testing.yml
name: Comprehensive Feature Testing

on:
  push:
    branches: [ main, develop ]
    paths:
      - 'modules/**'
      - 'tests/**'
      - 'lib/**'
  pull_request:
    branches: [ main ]
    paths:
      - 'modules/**'
      - 'tests/**'
      - 'lib/**'
  schedule:
    # Run comprehensive tests weekly
    - cron: '0 2 * * 1'
  workflow_dispatch:
    inputs:
      test_scope:
        description: 'Test scope (full, core, feature)'
        required: true
        default: 'core'
        type: choice
        options:
          - full
          - core
          - feature

env:
  TEST_RESULTS_DB: test-results.db
  EVIDENCE_BASE_DIR: test-evidence

jobs:
  analyze-changes:
    name: Analyze Changes
    runs-on: ubuntu-latest
    outputs:
      features_changed: ${{ steps.analyze.outputs.features }}
      test_scope: ${{ steps.analyze.outputs.scope }}
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0

      - name: Analyze changed features
        id: analyze
        run: |
          # Determine which features were changed
          CHANGED_FILES=$(git diff --name-only HEAD~1)

          # Extract affected features
          FEATURES_CHANGED=""
          for file in $CHANGED_FILES; do
            if [[ $file =~ ^modules/ ]]; then
              FEATURE=$(basename "$file" .nix)
              FEATURES_CHANGED="$FEATURES_CHANGED $FEATURE"
            fi
          done

          # Determine test scope
          if [[ "${{ github.event.inputs.test_scope }}" == "full" ]] || [[ "$GITHUB_EVENT_NAME" == "schedule" ]]; then
            TEST_SCOPE="full"
          elif [[ -n "$FEATURES_CHANGED" ]]; then
            TEST_SCOPE="feature"
          else
            TEST_SCOPE="core"
          fi

          echo "features=$FEATURES_CHANGED" >> $GITHUB_OUTPUT
          echo "scope=$TEST_SCOPE" >> $GITHUB_OUTPUT

  test-execution:
    name: Execute Tests
    runs-on: ubuntu-latest
    needs: analyze-changes
    strategy:
      matrix:
        test_group: [core, networking, security, monitoring, vpn, advanced]
        exclude:
          - test_group: ${{ needs.analyze-changes.outputs.test_scope == 'core' && 'networking' || '' }}
          - test_group: ${{ needs.analyze-changes.outputs.test_scope == 'core' && 'security' || '' }}
          - test_group: ${{ needs.analyze-changes.outputs.test_scope == 'core' && 'monitoring' || '' }}
          - test_group: ${{ needs.analyze-changes.outputs.test_scope == 'core' && 'vpn' || '' }}
          - test_group: ${{ needs.analyze-changes.outputs.test_scope == 'core' && 'advanced' || '' }}
    steps:
      - uses: actions/checkout@v4

      - name: Setup Nix
        uses: cachix/install-nix-action@v25
        with:
          nix_path: nixpkgs=channel:nixos-unstable

      - name: Setup test environment
        run: |
          mkdir -p ${{ env.EVIDENCE_BASE_DIR }}
          nix flake update

      - name: Execute ${{ matrix.test_group }} tests
        run: |
          ./scripts/run-test-group.sh ${{ matrix.test_group }} ${{ env.EVIDENCE_BASE_DIR }}

      - name: Upload test evidence
        uses: actions/upload-artifact@v4
        with:
          name: test-evidence-${{ matrix.test_group }}
          path: ${{ env.EVIDENCE_BASE_DIR }}/
          retention-days: 30

  evidence-collection:
    name: Collect and Validate Evidence
    runs-on: ubuntu-latest
    needs: test-execution
    steps:
      - uses: actions/checkout@v4

      - name: Download all evidence
        uses: actions/download-artifact@v4
        with:
          path: collected-evidence

      - name: Validate evidence quality
        run: |
          find collected-evidence -name "*.tar.gz" -exec ./scripts/validate-evidence-quality.sh {} \;

      - name: Analyze evidence
        run: |
          ./scripts/batch-analyze-evidence.sh collected-evidence

      - name: Store test results
        run: |
          ./scripts/store-batch-results.sh collected-evidence ${{ env.TEST_RESULTS_DB }}

      - name: Upload evidence analysis
        uses: actions/upload-artifact@v4
        with:
          name: evidence-analysis
          path: evidence-analysis/
          retention-days: 90

  generate-reports:
    name: Generate Test Reports
    runs-on: ubuntu-latest
    needs: evidence-collection
    steps:
      - uses: actions/checkout@v4

      - name: Download evidence analysis
        uses: actions/download-artifact@v4
        with:
          name: evidence-analysis
          path: evidence-analysis

      - name: Generate comprehensive report
        run: |
          ./scripts/generate-comprehensive-report.sh evidence-analysis

      - name: Generate support matrix update
        run: |
          ./scripts/update-support-matrix.sh evidence-analysis

      - name: Upload reports
        uses: actions/upload-artifact@v4
        with:
          name: test-reports
          path: |
            comprehensive-report.pdf
            support-matrix-update.json
            test-summary.html
          retention-days: 90

  human-review-gate:
    name: Human Review Gate
    runs-on: ubuntu-latest
    needs: generate-reports
    if: github.event_name == 'pull_request' || github.event_name == 'schedule'
    steps:
      - name: Download reports
        uses: actions/download-artifact@v4
        with:
          name: test-reports
          path: reports

      - name: Request human review
        run: |
          echo "🔔 Human review required for comprehensive test results"
          echo "📊 Test reports available for review"
          echo "📁 Evidence analysis: evidence-analysis/"
          echo "📄 Reports: reports/"

          # Create review request
          cat > review-request.md << EOF
          # Comprehensive Testing Review Required

          Automated testing has completed. Human review is required for:

          ## Test Results Summary
          - See: reports/test-summary.html

          ## Evidence Analysis
          - Location: evidence-analysis/
          - Quality validation results included

          ## Support Matrix Updates
          - Proposed changes: reports/support-matrix-update.json

          ## Review Checklist
          - [ ] Test results accurately reflect feature functionality
          - [ ] Evidence collection is comprehensive and valid
          - [ ] Support matrix changes are appropriate
          - [ ] No critical issues missed by automated testing
          - [ ] Documentation updates are complete

          ## Approval
          Reviewed by: ________
          Date: ________
          Approved: [ ] Yes [ ] No [ ] Conditional
          Comments: __________________________
          EOF

      - name: Comment on PR
        if: github.event_name == 'pull_request'
        uses: actions/github-script@v7
        with:
          script: |
            github.rest.issues.createComment({
              issue_number: context.issue.number,
              owner: context.repo.owner,
              repo: context.repo.repo,
              body: '## 🔔 Human Review Required\n\nComprehensive feature testing has completed. Please review the test results and evidence before merging.\n\n📊 [View Test Reports](https://github.com/${context.repo.owner}/${context.repo.repo}/actions/runs/${context.runId})\n\n📋 [Review Checklist](review-request.md)'
            })

  cleanup:
    name: Cleanup
    runs-on: ubuntu-latest
    needs: [test-execution, evidence-collection, generate-reports]
    if: always()
    steps:
      - name: Clean up old artifacts
        run: |
          # Keep only last 10 runs of each artifact type
          gh api repos/${{ github.repository }}/actions/artifacts \
            --jq '.artifacts[] | select(.name | startswith("test-evidence-")) | .id' \
            | tail -n +11 \
            | xargs -I {} gh api repos/${{ github.repository }}/actions/artifacts/{} -X DELETE || true
```

## Test Group Execution Script

```bash
#!/usr/bin/env bash
# scripts/run-test-group.sh

set -euo pipefail

TEST_GROUP="$1"
EVIDENCE_DIR="$2"

echo "Running test group: $TEST_GROUP"

# Define test groups and their associated tests
declare -A TEST_GROUPS=(
    ["core"]="basic-gateway-test.nix dns-dhcp-test.nix"
    ["networking"]="network-comprehensive-test.nix ipv6-transition-test.nix"
    ["security"]="security-features-test.nix security-networking-integration-test.nix"
    ["monitoring"]="health-checks-test.nix monitoring-blackbox-test.nix"
    ["vpn"]="wireguard-vpn-test.nix tailscale-site-to-site-test.nix"
    ["advanced"]="xdp-ebpf-test.nix service-mesh-test.nix"
)

# Get tests for this group
TESTS="${TEST_GROUPS[$TEST_GROUP]}"

if [ -z "$TESTS" ]; then
  echo "Unknown test group: $TEST_GROUP"
  exit 1
fi

# Create group evidence directory
GROUP_EVIDENCE_DIR="$EVIDENCE_DIR/$TEST_GROUP"
mkdir -p "$GROUP_EVIDENCE_DIR"

# Initialize group results
cat > "$GROUP_EVIDENCE_DIR/group-summary.json" << EOF
{
  "test_group": "$TEST_GROUP",
  "execution_start": "$(date -Iseconds)",
  "tests_planned": $(echo "$TESTS" | wc -w),
  "tests_completed": 0,
  "tests_passed": 0,
  "tests_failed": 0
}
EOF

# Execute each test in the group
for test_file in $TESTS; do
  echo "Executing test: $test_file"

  # Update progress
  jq ".tests_completed += 1" "$GROUP_EVIDENCE_DIR/group-summary.json" > tmp.json && mv tmp.json "$GROUP_EVIDENCE_DIR/group-summary.json"

  # Run the test
  if ./scripts/run-standardized-test.sh "tests/$test_file" "$GROUP_EVIDENCE_DIR/$(basename "$test_file" .nix)"; then
    echo "✅ Test passed: $test_file"
    jq ".tests_passed += 1" "$GROUP_EVIDENCE_DIR/group-summary.json" > tmp.json && mv tmp.json "$GROUP_EVIDENCE_DIR/group-summary.json"
  else
    echo "❌ Test failed: $test_file"
    jq ".tests_failed += 1" "$GROUP_EVIDENCE_DIR/group-summary.json" > tmp.json && mv tmp.json "$GROUP_EVIDENCE_DIR/group-summary.json"
  fi
done

# Finalize group results
jq ".execution_end = \"$(date -Iseconds)\"" "$GROUP_EVIDENCE_DIR/group-summary.json" > tmp.json && mv tmp.json "$GROUP_EVIDENCE_DIR/group-summary.json"

# Calculate success rate
TOTAL_TESTS=$(jq '.tests_completed' "$GROUP_EVIDENCE_DIR/group-summary.json")
PASSED_TESTS=$(jq '.tests_passed' "$GROUP_EVIDENCE_DIR/group-summary.json")
SUCCESS_RATE=$((PASSED_TESTS * 100 / TOTAL_TESTS))

jq ".success_rate_percent = $SUCCESS_RATE" "$GROUP_EVIDENCE_DIR/group-summary.json" > tmp.json && mv tmp.json "$GROUP_EVIDENCE_DIR/group-summary.json"

echo "Test group $TEST_GROUP completed: $PASSED_TESTS/$TOTAL_TESTS tests passed ($SUCCESS_RATE%)"

# Exit with failure if success rate is too low
if [ $SUCCESS_RATE -lt 80 ]; then
  echo "❌ Test group failed: Success rate below 80%"
  exit 1
fi
```

## Batch Evidence Analysis

```bash
#!/usr/bin/env bash
# scripts/batch-analyze-evidence.sh

set -euo pipefail

EVIDENCE_DIR="$1"
ANALYSIS_DIR="${2:-evidence-analysis}"

echo "Batch analyzing evidence from: $EVIDENCE_DIR"

# Create analysis directory
mkdir -p "$ANALYSIS_DIR"

# Find all evidence files
find "$EVIDENCE_DIR" -name "*.tar.gz" | while read -r evidence_file; do
  test_name=$(basename "$evidence_file" .tar.gz)
  echo "Analyzing evidence for: $test_name"

  # Analyze individual evidence
  ./scripts/analyze-evidence.sh "$test_name" "$evidence_file" "$ANALYSIS_DIR"
done

# Generate batch summary
cat > "$ANALYSIS_DIR/batch-summary.json" << EOF
{
  "batch_analysis_date": "$(date -Iseconds)",
  "total_tests_analyzed": $(find "$ANALYSIS_DIR" -name "*-summary.json" | wc -l),
  "evidence_files_processed": $(find "$EVIDENCE_DIR" -name "*.tar.gz" | wc -l),
  "analysis_reports_generated": $(find "$ANALYSIS_DIR" -name "analysis.txt" | wc -l),
  "total_evidence_size": "$(du -sh "$EVIDENCE_DIR" | cut -f1)"
}
EOF

echo "Batch evidence analysis completed: $(find "$ANALYSIS_DIR" -name "*-summary.json" | wc -l) tests analyzed"
```

## Comprehensive Report Generation

```bash
#!/usr/bin/env bash
# scripts/generate-comprehensive-report.sh

set -euo pipefail

ANALYSIS_DIR="$1"
REPORT_FILE="${2:-comprehensive-report.pdf}"

echo "Generating comprehensive test report from: $ANALYSIS_DIR"

# Collect all analysis data
ALL_SUMMARIES=$(find "$ANALYSIS_DIR" -name "*-summary.json" -exec cat {} \; | jq -s '.')

# Generate JSON report
cat > comprehensive-report.json << EOF
{
  "report_title": "NixOS Gateway Comprehensive Feature Testing Report",
  "generation_date": "$(date -Iseconds)",
  "analysis_source": "$ANALYSIS_DIR",
  "summary": {
    "total_tests": $(echo "$ALL_SUMMARIES" | jq 'length'),
    "tests_passed": $(echo "$ALL_SUMMARIES" | jq '[.[] | select(.result == "passed")] | length'),
    "tests_failed": $(echo "$ALL_SUMMARIES" | jq '[.[] | select(.result == "failed")] | length'),
    "average_evidence_files": $(echo "$ALL_SUMMARIES" | jq '[.[].evidence_count] | add / length'),
    "total_evidence_size": $(find "$ANALYSIS_DIR" -name "*.json" -exec du -b {} \; | awk '{sum+=$1} END {print sum}')
  },
  "test_results": $ALL_SUMMARIES,
  "recommendations": $(echo "$ALL_SUMMARIES" | jq '[
    .[] | select(.result == "failed") | {
      test: .test_name,
      issue: "Test failed - requires investigation",
      priority: "high"
    }
  ] + [
    .[] | select(.evidence_count < 5) | {
      test: .test_name,
      issue: "Insufficient evidence collected",
      priority: "medium"
    }
  ]')
}
EOF

# Generate HTML report
cat > test-summary.html << EOF
<!DOCTYPE html>
<html>
<head>
    <title>NixOS Gateway Comprehensive Test Report</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 40px; }
        .summary { background: #f0f0f0; padding: 20px; border-radius: 5px; margin-bottom: 20px; }
        .test-result { margin: 10px 0; padding: 10px; border-left: 4px solid; }
        .passed { border-color: #28a745; background: #d4edda; }
        .failed { border-color: #dc3545; background: #f8d7da; }
        .stats { display: flex; gap: 20px; margin: 20px 0; }
        .stat { text-align: center; padding: 10px; background: #e9ecef; border-radius: 5px; }
    </style>
</head>
<body>
    <h1>NixOS Gateway Comprehensive Test Report</h1>
    <p><strong>Generated:</strong> $(date)</p>

    <div class="summary">
        <h2>Executive Summary</h2>
        <div class="stats">
            <div class="stat">
                <div style="font-size: 2em; font-weight: bold;">$(jq '.summary.total_tests' comprehensive-report.json)</div>
                <div>Total Tests</div>
            </div>
            <div class="stat">
                <div style="font-size: 2em; font-weight: bold; color: #28a745;">$(jq '.summary.tests_passed' comprehensive-report.json)</div>
                <div>Tests Passed</div>
            </div>
            <div class="stat">
                <div style="font-size: 2em; font-weight: bold; color: #dc3545;">$(jq '.summary.tests_failed' comprehensive-report.json)</div>
                <div>Tests Failed</div>
            </div>
        </div>
    </div>

    <h2>Detailed Test Results</h2>
    $(jq -r '.test_results[] | "<div class=\"test-result \(.result)\"><h3>\(.test_name)</h3><p>Result: \(.result)</p><p>Evidence files: \(.evidence_count)</p></div>"' comprehensive-report.json)

    <h2>Recommendations</h2>
    <ul>
    $(jq -r '.recommendations[] | "<li><strong>\(.test)</strong>: \(.issue) (Priority: \(.priority))</li>"' comprehensive-report.json)
    </ul>
</body>
</html>
EOF

# Convert to PDF if pandoc is available
if command -v pandoc &> /dev/null; then
  pandoc test-summary.html -o "$REPORT_FILE"
  echo "PDF report generated: $REPORT_FILE"
else
  echo "HTML report generated: test-summary.html (pandoc not available for PDF)"
fi

echo "Comprehensive report generation completed"
```

This automated test execution pipeline provides:

1. **Change Detection**: Automatically determines which tests to run based on code changes
2. **Parallel Execution**: Runs test groups in parallel for efficiency
3. **Evidence Management**: Comprehensive collection, validation, and analysis of test evidence
4. **Reporting**: Automated generation of detailed reports and support matrix updates
5. **Human Integration**: Clear gates for human review and certification
6. **CI/CD Integration**: Full GitHub Actions workflow for automated testing