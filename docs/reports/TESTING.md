# NixOS Gateway Test System

This directory contains comprehensive test automation and logging system for the NixOS Gateway Configuration Framework.

## 🚀 Quick Start

### Run All Tests
```bash
# Run all tests and collect comprehensive logs
./run-tests.sh

# Run tests with specific output directory
./run-tests.sh | tee test-run.log
```

### Check Test Status
```bash
# Check latest test run status
./test-status.sh

# Check specific test run
./test-status.sh test_run_20231215_143022
```

## 📁 Test Results Structure

```
test-results/
├── test_run_YYYYMMDD_HHMMSS/          # Individual test run
│   ├── test_summary.md                 # Human-readable summary
│   ├── test_summary.json              # Machine-readable summary
│   ├── logs/                         # Individual test logs
│   │   ├── test-name.log
│   │   └── ...
│   ├── results/                      # Test result files
│   │   ├── test-name.result
│   │   └── ...
│   ├── metadata/                     # Test metadata
│   │   ├── test-name.json
│   │   └── ...
│   └── coverage/                     # Coverage reports
│       └── coverage.txt
└── latest -> test_run_YYYYMMDD_HHMMSS  # Symlink to latest run
```

## 📊 Test Reports

### Summary Report (test_summary.md)
- **Overall Statistics**: Total tests, passed, failed, success rate
- **Detailed Results**: Individual test status with links to logs
- **Feature Results**: Status of each feature tested
- **Task Results**: Status of each task tested
- **Failure Analysis**: Detailed failure information and logs

### JSON Report (test_summary.json)
- **Machine-readable** format for CI/CD integration
- **Structured data** for automated analysis
- **API-friendly** format for dashboards

### Coverage Report (coverage.txt)
- **Module Coverage**: Which modules were tested
- **Feature Coverage**: Status of all features
- **Task Coverage**: Status of all tasks

## 🎯 Feature and Task Tracking

The test system automatically tracks which features and tasks are being tested:

### Feature Detection
Tests are automatically associated with features when:
- Feature numbers are mentioned in comments (`# Feature 01`)
- Feature-related variables or functions are used
- Test files are named with feature numbers

### Task Detection
Tests are automatically associated with tasks when:
- Task numbers are mentioned in comments (`# Task 01`)
- Task-related configurations are tested
- Test files reference specific improvement tasks

### Example Test File
```nix
# Test for Task 01 - Data Validation Enhancements
# Feature: Input validation, Type checking, Error handling

{
  # Test configuration for data validation
  services.gateway.validation = {
    enable = true;
    strict = true;
  };
  
  # Test cases
  testCases = [
    { input = "valid"; expected = "success"; }
    { input = "invalid"; expected = "failure"; }
  ];
}
```

## 🔧 Advanced Usage

### Custom Test Discovery
The test system discovers tests in multiple ways:
- Files ending in `test.nix`
- Files containing `test` in the name
- Directories with `test.nix` files
- Files matching `*test*.nix` pattern

### Test Metadata
Each test can include metadata:
```nix
# Test Description: Comprehensive validation testing
# Features: 01, 02, 03
# Tasks: 01, 02
# Tags: validation, security, performance

{
  # Test implementation
}
```

### Continuous Integration
```bash
# CI/CD Integration
./run-tests.sh
RESULT=$?

# Upload results
if [ -d "test-results/latest" ]; then
    # Upload to your CI system
    upload-test-results test-results/latest/
fi

exit $RESULT
```

## 📈 Test Metrics

### Success Rate Tracking
- **Overall Success Rate**: Percentage of passing tests
- **Feature Success Rate**: Percentage of features with passing tests
- **Task Success Rate**: Percentage of tasks with passing tests

### Trend Analysis
- **Historical Data**: All test runs are preserved
- **Trend Tracking**: Compare success rates over time
- **Regression Detection**: Identify failing tests over time

### Coverage Analysis
- **Module Coverage**: Which modules have tests
- **Feature Coverage**: Which features are tested
- **Task Coverage**: Which improvement tasks are validated

## 🛠️ Troubleshooting

### Common Issues

#### Tests Not Found
```bash
# Check if tests exist
find . -name "*test*.nix" -o -name "test.nix"

# Ensure tests are in the right location
ls -la tests/
```

#### Permission Errors
```bash
# Make scripts executable
chmod +x run-tests.sh test-status.sh

# Check log directory permissions
ls -la test-results/
```

#### Nix Not Available
```bash
# Check if nix is installed
which nix

# Install nix if needed
curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix | sh -s -- install
```

### Debug Mode
```bash
# Run with debug output
bash -x ./run-tests.sh

# Check specific test logs
cat test-results/latest/logs/test-name.log
```

## 📋 Test Categories

### Unit Tests
- Individual module testing
- Function validation
- Configuration validation

### Integration Tests
- Multi-module interaction
- End-to-end scenarios
- Real-world configurations

### Performance Tests
- Throughput testing
- Latency measurement
- Resource usage analysis

### Security Tests
- Vulnerability scanning
- Configuration validation
- Compliance checking

## 🔄 Test Lifecycle

### Before Running Tests
1. **Environment Setup**: Ensure dependencies are installed
2. **Code Checkout**: Use correct git commit/branch
3. **Build Verification**: Ensure code builds successfully

### During Test Execution
1. **Test Discovery**: Find all test files
2. **Metadata Extraction**: Parse test metadata
3. **Test Execution**: Run each test with timeout
4. **Result Collection**: Capture logs and results

### After Test Execution
1. **Report Generation**: Create comprehensive reports
2. **Coverage Analysis**: Generate coverage information
3. **Result Aggregation**: Summarize test outcomes
4. **Cleanup**: Clean up temporary files

## 📊 Integration with Development Workflow

### Pre-commit Hooks
```bash
#!/bin/sh
# .git/hooks/pre-commit

# Run quick tests
./run-tests.sh
```

### Pull Request Validation
```bash
# CI pipeline
- name: Run Tests
  run: |
    ./run-tests.sh
    ./test-status.sh
```

### Release Validation
```bash
# Before release
./run-tests.sh
./test-status.sh

# Ensure 100% pass rate before release
```

## 🎯 Best Practices

### Test Organization
- **Descriptive Names**: Use clear, descriptive test names
- **Comprehensive Coverage**: Test all features and edge cases
- **Isolation**: Tests should not depend on each other
- **Documentation**: Include clear descriptions and comments

### Test Maintenance
- **Regular Updates**: Keep tests updated with code changes
- **Performance Monitoring**: Monitor test execution time
- **Failure Analysis**: Investigate and fix failing tests promptly
- **Coverage Improvement**: Continuously improve test coverage

### Result Analysis
- **Regular Review**: Review test results regularly
- **Trend Monitoring**: Monitor success rate trends
- **Regression Detection**: Watch for new failures
- **Performance Tracking**: Monitor test performance over time

## 📞 Support

For issues with the test system:
1. Check the logs in `test-results/latest/logs/`
2. Review the troubleshooting section above
3. Check the test metadata for correct feature/task associations
4. Verify test file naming and organization

The test system is designed to be robust and continue on failure, providing comprehensive logging and reporting for all test scenarios.