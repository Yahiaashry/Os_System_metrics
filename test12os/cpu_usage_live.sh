#!/bin/bash
# cpu_usage_live.sh - Shows live CPU usage percentage like Task Manager

echo "=== Live CPU Usage Monitor (Task Manager Style) ==="
echo "Press Ctrl+C to exit"
echo ""

# Function to calculate CPU usage
get_cpu_usage() {
    # First measurement
    cpu1=$(grep '^cpu ' /proc/stat)
    read -r cpu user1 nice1 sys1 idle1 iowait1 irq1 softirq1 steal1 guest1 guest_nice1 <<< "$cpu1"
    
    # Calculate total CPU time (excluding guest times as they're included in user/nice)
    total1=$((user1 + nice1 + sys1 + idle1 + iowait1 + irq1 + softirq1 + steal1))
    idle1_total=$((idle1 + iowait1))  # idle + iowait = total idle time
    
    # Wait for sampling interval
    sleep 1
    
    # Second measurement
    cpu2=$(grep '^cpu ' /proc/stat)
    read -r cpu user2 nice2 sys2 idle2 iowait2 irq2 softirq2 steal2 guest2 guest_nice2 <<< "$cpu2"
    
    total2=$((user2 + nice2 + sys2 + idle2 + iowait2 + irq2 + softirq2 + steal2))
    idle2_total=$((idle2 + iowait2))
    
    # Calculate differences
    total_diff=$((total2 - total1))
    idle_diff=$((idle2_total - idle1_total))
    
    # Calculate CPU usage percentage
    if [ $total_diff -gt 0 ]; then
        # Method 1: Total CPU usage (like Task Manager's main percentage)
        cpu_usage=$((100 * (total_diff - idle_diff) / total_diff))
        
        # Method 2: Breakdown (optional)
        user_diff=$((user2 - user1))
        nice_diff=$((nice2 - nice1))
        sys_diff=$((sys2 - sys1))
        iowait_diff=$((iowait2 - iowait1))
        
        user_pct=$((100 * user_diff / total_diff))
        nice_pct=$((100 * nice_diff / total_diff))
        sys_pct=$((100 * sys_diff / total_diff))
        iowait_pct=$((100 * iowait_diff / total_diff))
        
        # Get current time
        current_time=$(date '+%H:%M:%S')
        
        # Display results
        echo "[$current_time] CPU Usage: ${cpu_usage}%"
        echo "  Breakdown: User ${user_pct}% | System ${sys_pct}% | I/O Wait ${iowait_pct}%"
    else
        echo "Error: Could not calculate CPU usage"
    fi
}

# Continuous monitoring
while true; do
    get_cpu_usage
    # Optional: Add a small delay between updates
    # sleep 0.5
done
