#!/usr/bin/env bash

# Script to fix ALL test files to have correct { pkgs, lib, ... }: structure

echo "=== Fixing All Test Files ==="

# Find all test files
find tests/ -name "*.nix" | sort > /tmp/test_files_list.txt

# Counter
total=0
fixed=0

while IFS= read -r test_file; do
    if [ ! -f "$test_file" ]; then
        continue
    fi
    
    # Check structure
    first_line=$(head -1 "$test_file")
    if [[ "$first_line" =~ ^\{[[:space:]]*pkgs,[[:space:]]*lib,[[:space:]]*\.\.\.[[:space:]]*\}:[[:space:]]*$ ]]; then
        echo "✅ PASS: $test_file"
        ((fixed++))
    else
        echo "❌ FAIL: $test_file - Incorrect structure"
        echo "   First line: $first_line"
        ((failed++))
        # Try to fix it
        test_name=$(basename "$test_file" .nix)
        sed -i '1s/.*/\{ pkgs, lib, \.\.\. }:/\{ pkgs, lib, ... }:/' "$test_file"
        
        echo "   🔧 Fixed: $test_file"
        ((fixed++))
    fi
    
    ((total++))
done

echo ""
echo "=== Summary ==="
echo "Total files: $total"
echo "Fixed: $fixed"
echo "Failed: $failed"

exit $failed
