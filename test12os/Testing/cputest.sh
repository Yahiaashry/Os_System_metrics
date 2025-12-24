#!/bin/bash
# cpu_stress_test.sh

STRESS_TIME=${1:-30}  # default 30 seconds
NUM_CORES=$(nproc)
echo "Starting CPU stress test for $STRESS_TIME seconds on $NUM_CORES cores"

# Method 1: Mathematical calculations (pure CPU)
echo "Method 1: Prime number calculations"
for i in $(seq 1 $NUM_CORES); do
    (
        while true; do
            # Calculate primes - CPU intensive
            for n in $(seq 1 10000); do
                is_prime=1
                for ((i=2; i*i<=n; i++)); do
                    if (( n % i == 0 )); then
                        is_prime=0
                        break
                    fi
                done
            done
        done
    ) &
    PID=$!
    PIDS+=($PID)
done

# Method 2: Infinite loops with calculations
echo "Method 2: Floating point calculations"
for i in $(seq 1 $NUM_CORES); do
    (
        x=3.14159
        while true; do
            x=$(echo "$x * 1.00001" | bc -l)
            x=$(echo "sqrt($x)" | bc -l)
        done
    ) &
    PIDS+=($!)
done

sleep $STRESS_TIME

# Kill all background processes
echo "Cleaning up..."
for pid in "${PIDS[@]}"; do
    kill $pid 2>/dev/null
done
