#!/bin/bash
# ============================================
# SYSTEM MONITOR - BENCHMARK & TEST SCRIPT
# Tests performance and validates functionality
# ============================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCRIPT_DIR/system_monitor/utils/logger.sh"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Test results
TESTS_PASSED=0
TESTS_FAILED=0
TESTS_TOTAL=0

# Helper functions
print_test() {
    echo -e "\n${YELLOW}[TEST]${NC} $1"
    ((TESTS_TOTAL++))
}

print_pass() {
    echo -e "${GREEN}[PASS]${NC} $1"
    ((TESTS_PASSED++))
}

print_fail() {
    echo -e "${RED}[FAIL]${NC} $1"
    ((TESTS_FAILED++))
}

# Test OS detection
test_os_detection() {
    print_test "OS Detection"
    
    source "$SCRIPT_DIR/system_monitor/utils/platform_detect.sh"
    
    local os=$(detect_os)
    if [[ -n "$os" ]] && [[ "$os" != "unknown" ]]; then
        print_pass "OS detected: $os"
    else
        print_fail "OS detection failed"
    fi
}

# Test bash monitoring
test_bash_monitoring() {
    print_test "Bash Monitoring Collection"
    
    local start_time=$(date +%s%N)
    
    if bash "$SCRIPT_DIR/system_monitor/monitor.sh" json > /tmp/test_metrics.json 2>&1; then
        local end_time=$(date +%s%N)
        local duration=$(( (end_time - start_time) / 1000000 ))
        
        if [[ -s /tmp/test_metrics.json ]]; then
            print_pass "Bash metrics collected (${duration}ms)"
        else
            print_fail "Empty metrics file"
        fi
    else
        print_fail "Bash monitoring failed"
    fi
    
    rm -f /tmp/test_metrics.json
}

# Test Python monitoring
test_python_monitoring() {
    print_test "Python Monitoring Collection"
    
    # Check if Python is available
    if ! command -v python3 &>/dev/null; then
        print_fail "Python 3 not found"
        return
    fi
    
    # Check if virtual environment exists
    if [[ -d "$SCRIPT_DIR/python_monitor/venv" ]]; then
        source "$SCRIPT_DIR/python_monitor/venv/bin/activate"
    fi
    
    local start_time=$(date +%s%N)
    
    if python3 "$SCRIPT_DIR/python_monitor/cli/monitor_cli.py" collect --output json > /tmp/test_python_metrics.json 2>&1; then
        local end_time=$(date +%s%N)
        local duration=$(( (end_time - start_time) / 1000000 ))
        
        if [[ -s /tmp/test_python_metrics.json ]]; then
            print_pass "Python metrics collected (${duration}ms)"
        else
            print_fail "Empty Python metrics file"
        fi
    else
        print_fail "Python monitoring failed"
    fi
    
    rm -f /tmp/test_python_metrics.json
}

# Test caching
test_caching() {
    print_test "Metric Caching"
    
    source "$SCRIPT_DIR/system_monitor/utils/parallel_executor.sh"
    source "$SCRIPT_DIR/system_monitor/modules/cpu_monitor.sh"
    
    # First call (no cache)
    local start1=$(date +%s%N)
    local result1=$(get_cpu_usage)
    local end1=$(date +%s%N)
    local time1=$(( (end1 - start1) / 1000000 ))
    
    # Second call (should use cache)
    local start2=$(date +%s%N)
    local result2=$(get_cpu_usage)
    local end2=$(date +%s%N)
    local time2=$(( (end2 - start2) / 1000000 ))
    
    if [[ $time2 -lt $time1 ]]; then
        print_pass "Caching works (${time1}ms → ${time2}ms)"
    else
        print_fail "Caching not effective"
    fi
}

# Test database
test_database() {
    print_test "Database Operations"
    
    if ! command -v python3 &>/dev/null; then
        print_fail "Python 3 not found"
        return
    fi
    
    local test_db="/tmp/test_metrics.db"
    
    # Test database creation and insertion
    python3 << EOF
import sys
sys.path.insert(0, '$SCRIPT_DIR')
from python_monitor.database.metrics_db import MetricsDatabase
import os

db = MetricsDatabase('$test_db')
row_id = db.insert_metrics('test-host', 'cpu', {'usage': 50.0})

if row_id > 0:
    records = db.get_latest_metrics('cpu', 1)
    if len(records) > 0:
        print("PASS")
    else:
        print("FAIL: No records")
else:
    print("FAIL: Insert failed")
EOF
    
    local result=$(python3 << EOF
import sys
sys.path.insert(0, '$SCRIPT_DIR')
from python_monitor.database.metrics_db import MetricsDatabase
db = MetricsDatabase('$test_db')
print("PASS" if db.get_database_stats()['total_records'] > 0 else "FAIL")
EOF
)
    
    if [[ "$result" == "PASS" ]]; then
        print_pass "Database operations successful"
    else
        print_fail "Database operations failed"
    fi
    
    rm -f "$test_db"
}

# Test analytics
test_analytics() {
    print_test "Analytics Engine"
    
    if ! command -v python3 &>/dev/null; then
        print_fail "Python 3 not found"
        return
    fi
    
    python3 << EOF
import sys
sys.path.insert(0, '$SCRIPT_DIR')
from python_monitor.analytics.analyzer import MetricsAnalyzer

analyzer = MetricsAnalyzer()
values = [10, 20, 30, 40, 50, 60, 70]

# Test moving average
ma = analyzer.calculate_moving_average(values, 3)

# Test trend detection
trend = analyzer.detect_trend(values)

# Test percentiles
stats = analyzer.calculate_percentiles(values)

if len(ma) > 0 and trend == 'increasing' and stats['median'] == 40:
    print("PASS")
else:
    print("FAIL")
EOF
    
    local result=$(python3 << EOF
import sys
sys.path.insert(0, '$SCRIPT_DIR')
from python_monitor.analytics.analyzer import MetricsAnalyzer
analyzer = MetricsAnalyzer()
values = [10, 20, 30, 40, 50]
print("PASS" if analyzer.detect_trend(values) == 'increasing' else "FAIL")
EOF
)
    
    if [[ "$result" == "PASS" ]]; then
        print_pass "Analytics working correctly"
    else
        print_fail "Analytics test failed"
    fi
}

# Performance benchmark
benchmark_performance() {
    echo -e "\n${YELLOW}[BENCHMARK]${NC} Performance Test"
    
    source "$SCRIPT_DIR/system_monitor/monitor.sh"
    
    # CPU usage of script
    echo "Measuring script overhead..."
    
    local iterations=5
    local total_time=0
    
    for ((i=1; i<=iterations; i++)); do
        local start=$(date +%s%N)
        bash "$SCRIPT_DIR/system_monitor/monitor.sh" collect &>/dev/null
        local end=$(date +%s%N)
        local duration=$(( (end - start) / 1000000 ))
        total_time=$((total_time + duration))
        echo "  Iteration $i: ${duration}ms"
    done
    
    local avg_time=$((total_time / iterations))
    echo -e "${GREEN}Average execution time: ${avg_time}ms${NC}"
    
    if [[ $avg_time -lt 5000 ]]; then
        echo -e "${GREEN}Performance: EXCELLENT (<5s)${NC}"
    elif [[ $avg_time -lt 10000 ]]; then
        echo -e "${YELLOW}Performance: GOOD (<10s)${NC}"
    else
        echo -e "${RED}Performance: NEEDS IMPROVEMENT (>10s)${NC}"
    fi
}

# Main test runner
main() {
    echo "======================================"
    echo "  System Monitor - Test & Benchmark"
    echo "======================================"
    
    test_os_detection
    test_bash_monitoring
    test_python_monitoring
    test_caching
    test_database
    test_analytics
    
    benchmark_performance
    
    echo ""
    echo "======================================"
    echo "  Test Results"
    echo "======================================"
    echo -e "Total Tests: $TESTS_TOTAL"
    echo -e "${GREEN}Passed: $TESTS_PASSED${NC}"
    echo -e "${RED}Failed: $TESTS_FAILED${NC}"
    
    if [[ $TESTS_FAILED -eq 0 ]]; then
        echo -e "\n${GREEN}✓ All tests passed!${NC}"
        exit 0
    else
        echo -e "\n${RED}✗ Some tests failed${NC}"
        exit 1
    fi
}

main "$@"
