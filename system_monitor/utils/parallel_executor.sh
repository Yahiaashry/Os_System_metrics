#!/bin/bash
# ============================================
# PARALLEL EXECUTION UTILITY
# Enables concurrent metric collection
# ============================================

# Global associative array for caching
declare -gA METRIC_CACHE
declare -gA CACHE_TIMESTAMP

# Cache TTL in seconds
CACHE_TTL=2

# Get cached metric or execute function
get_cached_metric() {
    local key="$1"
    local func="$2"
    shift 2
    local args="$@"
    
    local current_time=$(date +%s)
    local cache_key="${key}_${args}"
    
    # Check if cache exists and is valid
    if [[ -n "${METRIC_CACHE[$cache_key]}" ]]; then
        local cache_time="${CACHE_TIMESTAMP[$cache_key]:-0}"
        local age=$((current_time - cache_time))
        
        if [[ $age -lt $CACHE_TTL ]]; then
            echo "${METRIC_CACHE[$cache_key]}"
            return 0
        fi
    fi
    
    # Execute function and cache result
    local result=$($func $args)
    METRIC_CACHE[$cache_key]="$result"
    CACHE_TIMESTAMP[$cache_key]="$current_time"
    
    echo "$result"
}

# Clear cache
clear_cache() {
    METRIC_CACHE=()
    CACHE_TIMESTAMP=()
}

# Clear expired cache entries
clear_expired_cache() {
    local current_time=$(date +%s)
    
    for key in "${!CACHE_TIMESTAMP[@]}"; do
        local cache_time="${CACHE_TIMESTAMP[$key]}"
        local age=$((current_time - cache_time))
        
        if [[ $age -ge $CACHE_TTL ]]; then
            unset METRIC_CACHE[$key]
            unset CACHE_TIMESTAMP[$key]
        fi
    done
}

# Execute functions in parallel and collect results
parallel_exec() {
    local -a pids=()
    local -a results=()
    local temp_dir=$(mktemp -d)
    
    # Trap cleanup
    trap "rm -rf '$temp_dir'" EXIT
    
    local index=0
    for func in "$@"; do
        (
            result=$($func 2>/dev/null)
            echo "$result" > "$temp_dir/result_${index}"
        ) &
        pids+=($!)
        ((index++))
    done
    
    # Wait for all background jobs
    for pid in "${pids[@]}"; do
        wait "$pid"
    done
    
    # Collect results in order
    for ((i=0; i<${#pids[@]}; i++)); do
        if [[ -f "$temp_dir/result_${i}" ]]; then
            results+=("$(cat "$temp_dir/result_${i}")")
        else
            results+=("")
        fi
    done
    
    # Return results as array (caller must handle)
    printf '%s\n' "${results[@]}"
    
    rm -rf "$temp_dir"
}

# Execute command with timeout
exec_with_timeout() {
    local timeout="$1"
    shift
    local cmd="$@"
    
    # Use timeout command if available
    if command -v timeout &>/dev/null; then
        timeout "$timeout" bash -c "$cmd"
        return $?
    fi
    
    # Fallback: manual timeout implementation
    (
        eval "$cmd" &
        local pid=$!
        
        (
            sleep "$timeout"
            kill -TERM "$pid" 2>/dev/null
        ) &
        local killer_pid=$!
        
        wait "$pid" 2>/dev/null
        local exit_code=$?
        
        kill -TERM "$killer_pid" 2>/dev/null
        wait "$killer_pid" 2>/dev/null
        
        exit $exit_code
    )
}

# Rate limiter for API calls or expensive operations
declare -gA RATE_LIMIT_TIMESTAMPS

rate_limit() {
    local key="$1"
    local min_interval="$2"  # Minimum seconds between calls
    
    local current_time=$(date +%s)
    local last_time="${RATE_LIMIT_TIMESTAMPS[$key]:-0}"
    local elapsed=$((current_time - last_time))
    
    if [[ $elapsed -lt $min_interval ]]; then
        local sleep_time=$((min_interval - elapsed))
        sleep "$sleep_time"
    fi
    
    RATE_LIMIT_TIMESTAMPS[$key]="$current_time"
}

# Batch executor - execute multiple commands and return JSON
batch_exec_json() {
    local -a commands=("$@")
    local output="{"
    local first=true
    
    for cmd_spec in "${commands[@]}"; do
        # Parse command spec: "key:command"
        local key="${cmd_spec%%:*}"
        local cmd="${cmd_spec#*:}"
        
        [[ "$first" == false ]] && output+=","
        first=false
        
        local result=$(eval "$cmd" 2>/dev/null | head -1)
        result=$(echo "$result" | sed 's/"/\\"/g')  # Escape quotes
        
        output+="\"$key\":\"$result\""
    done
    
    output+="}"
    echo "$output"
}

# Execute and retry on failure
retry_exec() {
    local max_attempts="${1:-3}"
    local delay="${2:-1}"
    shift 2
    local cmd="$@"
    
    local attempt=1
    while [[ $attempt -le $max_attempts ]]; do
        if eval "$cmd"; then
            return 0
        fi
        
        if [[ $attempt -lt $max_attempts ]]; then
            sleep "$delay"
            ((delay *= 2))  # Exponential backoff
        fi
        
        ((attempt++))
    done
    
    return 1
}

# Background job manager
declare -gA BG_JOBS

start_background_job() {
    local job_name="$1"
    shift
    local cmd="$@"
    
    # Kill existing job if running
    if [[ -n "${BG_JOBS[$job_name]}" ]]; then
        kill "${BG_JOBS[$job_name]}" 2>/dev/null
        wait "${BG_JOBS[$job_name]}" 2>/dev/null
    fi
    
    # Start new background job
    eval "$cmd" &
    BG_JOBS[$job_name]=$!
}

stop_background_job() {
    local job_name="$1"
    
    if [[ -n "${BG_JOBS[$job_name]}" ]]; then
        kill "${BG_JOBS[$job_name]}" 2>/dev/null
        wait "${BG_JOBS[$job_name]}" 2>/dev/null
        unset BG_JOBS[$job_name]
    fi
}

stop_all_background_jobs() {
    for job_name in "${!BG_JOBS[@]}"; do
        stop_background_job "$job_name"
    done
}

# Export functions
export -f get_cached_metric clear_cache clear_expired_cache
export -f parallel_exec exec_with_timeout rate_limit
export -f batch_exec_json retry_exec
export -f start_background_job stop_background_job stop_all_background_jobs
