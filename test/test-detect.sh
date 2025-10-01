#!/bin/bash

# Test script for detect.sh

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Test result totals
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0

# Test directory path
TEST_DIR="$(cd "$(dirname "$0")" && pwd)"
SCRIPT_DIR="$(cd "$TEST_DIR/.." && pwd)"
DETECT_SCRIPT="$SCRIPT_DIR/detect.sh"

# Test execution function
run_test() {
    local test_name="$1"
    local list_file="$2"
    local lock_file="$3"
    local expected_exit_code="$4"
    local expected_pattern="$5"
    local verbose="$6"

    ((TOTAL_TESTS++))

    echo -n "Test $TOTAL_TESTS: $test_name ... "

    # Execute test
    if [ "$verbose" = "1" ]; then
        output=$(VERBOSE=1 "$DETECT_SCRIPT" "$list_file" "$lock_file" 2>&1)
    else
        output=$("$DETECT_SCRIPT" "$list_file" "$lock_file" 2>&1)
    fi
    exit_code=$?

    # Check exit code
    if [ "$exit_code" -ne "$expected_exit_code" ]; then
        printf "${RED}FAILED${NC}\n"
        echo "  Expected exit code: $expected_exit_code, Got: $exit_code"
        echo "  Output: $output"
        ((FAILED_TESTS++))
        return 1
    fi

    # Check expected pattern
    if [ -n "$expected_pattern" ]; then
        if echo "$output" | grep -q "$expected_pattern"; then
            printf "${GREEN}PASSED${NC}\n"
            ((PASSED_TESTS++))
            return 0
        else
            printf "${RED}FAILED${NC}\n"
            echo "  Expected pattern not found: $expected_pattern"
            echo "  Output: $output"
            ((FAILED_TESTS++))
            return 1
        fi
    else
        printf "${GREEN}PASSED${NC}\n"
        ((PASSED_TESTS++))
        return 0
    fi
}

echo "======================================"
echo "detect.sh Test Suite"
echo "======================================"
echo ""

# Test 1: All packages and all versions detected
run_test "All packages and versions detected" \
    "$TEST_DIR/list-all-found.txt" \
    "$TEST_DIR/simple-package-lock.json" \
    2 \
    "Detected packages: 4/4"

# Test 2: Some packages detected
run_test "Some packages detected" \
    "$TEST_DIR/list-some-found.txt" \
    "$TEST_DIR/simple-package-lock.json" \
    2 \
    "✓ express:"

# Test 3: No version specified
run_test "No version specified" \
    "$TEST_DIR/list-no-version.txt" \
    "$TEST_DIR/simple-package-lock.json" \
    0 \
    "✓ express:"

# Test 4: No packages
run_test "No packages found" \
    "$TEST_DIR/list-none-found.txt" \
    "$TEST_DIR/simple-package-lock.json" \
    0 \
    "Detected packages: 0"

# Test 5: List with empty lines
run_test "List with empty lines" \
    "$TEST_DIR/list-with-empty-lines.txt" \
    "$TEST_DIR/simple-package-lock.json" \
    2 \
    "✓ express:"

# Test 6: Complex package-lock.json
run_test "Complex package-lock.json" \
    "$TEST_DIR/list-complex.txt" \
    "$TEST_DIR/complex-package-lock.json" \
    2 \
    "✓ react: detected"

# Test 7: VERBOSE mode
run_test "VERBOSE mode" \
    "$TEST_DIR/list-some-found.txt" \
    "$TEST_DIR/simple-package-lock.json" \
    2 \
    "not detected" \
    1

# Test 8: package-lock.json does not exist
run_test "package-lock.json does not exist" \
    "$TEST_DIR/list-all-found.txt" \
    "$TEST_DIR/nonexistent.json" \
    1 \
    "package-lock.json not found"

# Test 9: List file does not exist
run_test "List file does not exist" \
    "$TEST_DIR/nonexistent.txt" \
    "$TEST_DIR/simple-package-lock.json" \
    1 \
    "List file not found"

# Test 10: Specific version detection
run_test "Specific version detection" \
    "$TEST_DIR/list-all-found.txt" \
    "$TEST_DIR/simple-package-lock.json" \
    2 \
    "Version 4.18.2: detected"

# Test 11: Scoped packages
run_test "Scoped packages" \
    "$TEST_DIR/list-complex.txt" \
    "$TEST_DIR/complex-package-lock.json" \
    2 \
    "@types/react"

# Test 12: Summary format check
run_test "Summary format check" \
    "$TEST_DIR/list-all-found.txt" \
    "$TEST_DIR/simple-package-lock.json" \
    2 \
    "Detection Summary"

# Test 13: lockfileVersion 2 (unsupported)
run_test "lockfileVersion 2 (unsupported)" \
    "$TEST_DIR/list-all-found.txt" \
    "$TEST_DIR/old-package-lock.json" \
    1 \
    "Only lockfileVersion 3 is supported"

echo ""
echo "======================================"
echo "Test Results"
echo "========================================"
printf "Total: %s tests\n" "$TOTAL_TESTS"
printf "Passed: ${GREEN}%s${NC}\n" "$PASSED_TESTS"
printf "Failed: ${RED}%s${NC}\n" "$FAILED_TESTS"

echo ""

if [ "$FAILED_TESTS" -eq 0 ]; then
    printf "${GREEN}✓ All tests passed!${NC}\n"
    exit 0
else
    printf "${RED}✗ %s tests failed${NC}\n" "$FAILED_TESTS"
    exit 1
fi