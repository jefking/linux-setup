#!/bin/bash

# IO Performance Test Script
# Compares performance between RAM drive and regular drive

RAM_DRIVE="/tmp/dev-workspace"
REGULAR_DRIVE="/home/jef/git/linux-setup"
TEST_FILE_SIZE="100M"
TEST_ITERATIONS=5

echo "=== IO Performance Comparison Test ==="
echo "RAM Drive: $RAM_DRIVE (tmpfs)"
echo "Regular Drive: $REGULAR_DRIVE"
echo "Test File Size: $TEST_FILE_SIZE"
echo "Iterations: $TEST_ITERATIONS"
echo ""

# Function to run dd tests
run_dd_test() {
    local path=$1
    local test_type=$2
    local label=$3
    
    echo "--- $label: $test_type Test ---"
    
    if [ "$test_type" = "write" ]; then
        # Write test
        local total_time=0
        local total_speed=0
        
        for i in $(seq 1 $TEST_ITERATIONS); do
            # Clear cache
            sync && echo 3 | sudo tee /proc/sys/vm/drop_caches > /dev/null 2>&1
            
            # Run dd write test
            result=$(dd if=/dev/zero of="$path/testfile" bs=1M count=100 conv=fdatasync 2>&1)
            
            # Extract time and speed
            time=$(echo "$result" | grep -oP '\d+\.\d+ s' | head -1 | cut -d' ' -f1)
            speed=$(echo "$result" | grep -oP '\d+\.?\d* [MG]B/s' | head -1)
            
            echo "  Iteration $i: Time=${time}s, Speed=$speed"
            
            # Clean up
            rm -f "$path/testfile"
        done
        
    elif [ "$test_type" = "read" ]; then
        # First create a test file
        dd if=/dev/zero of="$path/testfile" bs=1M count=100 conv=fdatasync 2>/dev/null
        
        # Read test
        for i in $(seq 1 $TEST_ITERATIONS); do
            # Clear cache
            sync && echo 3 | sudo tee /proc/sys/vm/drop_caches > /dev/null 2>&1
            
            # Run dd read test
            result=$(dd if="$path/testfile" of=/dev/null bs=1M 2>&1)
            
            # Extract time and speed
            time=$(echo "$result" | grep -oP '\d+\.\d+ s' | head -1 | cut -d' ' -f1)
            speed=$(echo "$result" | grep -oP '\d+\.?\d* [MG]B/s' | head -1)
            
            echo "  Iteration $i: Time=${time}s, Speed=$speed"
        done
        
        # Clean up
        rm -f "$path/testfile"
    fi
    echo ""
}

# Function to run fio tests (if available)
run_fio_test() {
    if ! command -v fio &> /dev/null; then
        echo "fio not installed. Skipping fio tests."
        return
    fi
    
    local path=$1
    local label=$2
    
    echo "--- $label: FIO Benchmark ---"
    
    # Sequential Write
    echo "Sequential Write:"
    fio --name=seq-write --ioengine=libaio --rw=write --bs=1M --size=100M \
        --numjobs=1 --runtime=10 --group_reporting --direct=1 \
        --filename="$path/fio-test" 2>/dev/null | grep -E "bw=|IOPS"
    
    # Sequential Read
    echo "Sequential Read:"
    fio --name=seq-read --ioengine=libaio --rw=read --bs=1M --size=100M \
        --numjobs=1 --runtime=10 --group_reporting --direct=1 \
        --filename="$path/fio-test" 2>/dev/null | grep -E "bw=|IOPS"
    
    # Random Write
    echo "Random Write (4K blocks):"
    fio --name=rand-write --ioengine=libaio --rw=randwrite --bs=4k --size=100M \
        --numjobs=1 --runtime=10 --group_reporting --direct=1 \
        --filename="$path/fio-test" 2>/dev/null | grep -E "bw=|IOPS"
    
    # Random Read
    echo "Random Read (4K blocks):"
    fio --name=rand-read --ioengine=libaio --rw=randread --bs=4k --size=100M \
        --numjobs=1 --runtime=10 --group_reporting --direct=1 \
        --filename="$path/fio-test" 2>/dev/null | grep -E "bw=|IOPS"
    
    rm -f "$path/fio-test"
    echo ""
}

# Check if we need sudo for cache clearing
if [ "$EUID" -ne 0 ]; then 
    echo "Note: Running without sudo. Cache clearing will be skipped."
    echo "For more accurate results, run with: sudo $0"
    echo ""
fi

# Run tests
echo "=== WRITE PERFORMANCE ==="
run_dd_test "$RAM_DRIVE" "write" "RAM Drive"
run_dd_test "$REGULAR_DRIVE" "write" "Regular Drive"

echo "=== READ PERFORMANCE ==="
run_dd_test "$RAM_DRIVE" "read" "RAM Drive"
run_dd_test "$REGULAR_DRIVE" "read" "Regular Drive"

echo "=== ADVANCED BENCHMARKS ==="
run_fio_test "$RAM_DRIVE" "RAM Drive"
run_fio_test "$REGULAR_DRIVE" "Regular Drive"

echo "=== TEST COMPLETE ==="