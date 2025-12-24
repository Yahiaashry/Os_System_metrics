#!/bin/bash
# ============================================
# HISTORICAL DATA TRACKING
# Stores last N samples for trending
# ============================================

HISTORY_DIR="${HISTORY_DIR:-./data/history}"
MAX_SAMPLES=100
RETENTION_HOURS=24

# Initialize history storage
init_history() {
    mkdir -p "$HISTORY_DIR"
}

# Store metric sample
store_sample() {
    local metric_type="$1"
    local value="$2"
    local timestamp=$(date +%s)
    
    local history_file="$HISTORY_DIR/${metric_type}.history"
    
    # Append new sample
    echo "$timestamp $value" >> "$history_file"
    
    # Keep only last MAX_SAMPLES
    tail -n $MAX_SAMPLES "$history_file" > "$history_file.tmp" 2>/dev/null
    mv "$history_file.tmp" "$history_file" 2>/dev/null
}

# Get historical samples
get_history() {
    local metric_type="$1"
    local count="${2:-10}"
    
    local history_file="$HISTORY_DIR/${metric_type}.history"
    
    if [ -f "$history_file" ]; then
        tail -n "$count" "$history_file"
    else
        echo ""
    fi
}

# Calculate average from history
get_historical_average() {
    local metric_type="$1"
    local samples=$(get_history "$metric_type" 100 | awk '{print $2}')
    
    if [ -z "$samples" ]; then
        echo "0"
        return
    fi
    
    echo "$samples" | awk '{sum+=$1; count++} END {printf "%.2f", sum/count}'
}

# Calculate trend (increasing/decreasing/stable)
get_trend() {
    local metric_type="$1"
    local samples=$(get_history "$metric_type" 20 | awk '{print $2}')
    
    if [ -z "$samples" ]; then
        echo "unknown"
        return
    fi
    
    # Simple trend detection: compare first half vs second half
    local first_half=$(echo "$samples" | head -n 10 | awk '{sum+=$1; count++} END {print sum/count}')
    local second_half=$(echo "$samples" | tail -n 10 | awk '{sum+=$1; count++} END {print sum/count}')
    
    local diff=$(echo "scale=2; $second_half - $first_half" | bc 2>/dev/null || echo "0")
    
    if (( $(echo "$diff > 5" | bc -l 2>/dev/null || echo "0") )); then
        echo "increasing"
    elif (( $(echo "$diff < -5" | bc -l 2>/dev/null || echo "0") )); then
        echo "decreasing"
    else
        echo "stable"
    fi
}

# Get min value from history
get_historical_min() {
    local metric_type="$1"
    local samples=$(get_history "$metric_type" 100 | awk '{print $2}')
    
    if [ -z "$samples" ]; then
        echo "0"
        return
    fi
    
    echo "$samples" | sort -n | head -1
}

# Get max value from history
get_historical_max() {
    local metric_type="$1"
    local samples=$(get_history "$metric_type" 100 | awk '{print $2}')
    
    if [ -z "$samples" ]; then
        echo "0"
        return
    fi
    
    echo "$samples" | sort -n | tail -1
}

# Cleanup old history
cleanup_history() {
    local cutoff_time=$(($(date +%s) - (RETENTION_HOURS * 3600)))
    
    for history_file in "$HISTORY_DIR"/*.history; do
        if [ -f "$history_file" ]; then
            awk -v cutoff=$cutoff_time '$1 >= cutoff' "$history_file" > "$history_file.tmp"
            mv "$history_file.tmp" "$history_file"
        fi
    done
}

# Export history to JSON
export_history_json() {
    local metric_type="$1"
    local history_file="$HISTORY_DIR/${metric_type}.history"
    
    if [ ! -f "$history_file" ]; then
        echo "[]"
        return
    fi
    
    echo "["
    local first=true
    while read -r timestamp value; do
        if [ "$first" = true ]; then
            first=false
        else
            echo ","
        fi
        echo "  {\"timestamp\": $timestamp, \"value\": $value}"
    done < "$history_file"
    echo "]"
}

# Get statistics summary
get_history_stats() {
    local metric_type="$1"
    
    local avg=$(get_historical_average "$metric_type")
    local min=$(get_historical_min "$metric_type")
    local max=$(get_historical_max "$metric_type")
    local trend=$(get_trend "$metric_type")
    local count=$(get_history "$metric_type" 1000 | wc -l)
    
    echo "Metric: $metric_type"
    echo "Samples: $count"
    echo "Average: $avg"
    echo "Min: $min"
    echo "Max: $max"
    echo "Trend: $trend"
}

export -f init_history store_sample get_history
export -f get_historical_average get_trend cleanup_history
export -f get_historical_min get_historical_max
export -f export_history_json get_history_stats
