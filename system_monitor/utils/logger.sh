#!/bin/bash
# ============================================
# LOGGER UTILITY WITH LOG ROTATION
# ============================================

# Load config
source "$(dirname "${BASH_SOURCE[0]}")/config.sh"

# Log levels
declare -gA LOG_LEVELS=(
    ["DEBUG"]=0
    ["INFO"]=1
    ["WARNING"]=2
    ["ERROR"]=3
    ["CRITICAL"]=4
)

# Current log level (default: INFO)
LOG_LEVEL="${LOG_LEVEL:-INFO}"

# Max log file size in bytes (default: 10MB)
MAX_LOG_SIZE=$((10 * 1024 * 1024))

# Number of rotated logs to keep
MAX_LOG_FILES=5

# Initialize logging
init_logging() {
    mkdir -p "$(dirname "$LOG_FILE")"
    if [[ ! -f "$LOG_FILE" ]]; then
        touch "$LOG_FILE"
    fi
    
    # Rotate if needed
    rotate_logs
}

# Check if log level should be logged
should_log() {
    local level="$1"
    local current_level="${LOG_LEVELS[$LOG_LEVEL]:-1}"
    local message_level="${LOG_LEVELS[$level]:-0}"
    
    [[ $message_level -ge $current_level ]]
}

# Rotate log files
rotate_logs() {
    if [[ ! -f "$LOG_FILE" ]]; then
        return 0
    fi
    
    local log_size=$(stat -f%z "$LOG_FILE" 2>/dev/null || stat -c%s "$LOG_FILE" 2>/dev/null || echo 0)
    
    if [[ $log_size -ge $MAX_LOG_SIZE ]]; then
        # Rotate existing logs
        for ((i=$MAX_LOG_FILES-1; i>=1; i--)); do
            local old_log="${LOG_FILE}.$i"
            local new_log="${LOG_FILE}.$((i+1))"
            
            if [[ -f "$old_log" ]]; then
                if [[ $i -eq $((MAX_LOG_FILES-1)) ]]; then
                    rm -f "$old_log"
                else
                    mv "$old_log" "$new_log"
                fi
            fi
        done
        
        # Move current log to .1
        mv "$LOG_FILE" "${LOG_FILE}.1"
        touch "$LOG_FILE"
        
        log_message "INFO" "Log rotated (size: $log_size bytes)"
    fi
}

# Clean old logs based on retention policy
clean_old_logs() {
    local retention_days="${LOG_RETENTION_DAYS:-30}"
    local log_dir="$(dirname "$LOG_FILE")"
    
    if [[ -d "$log_dir" ]]; then
        find "$log_dir" -name "*.log*" -type f -mtime "+$retention_days" -delete 2>/dev/null
        log_message "INFO" "Cleaned logs older than $retention_days days"
    fi
}

# Log message function
log_message() {
    local level="$1"
    local message="$2"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    local caller="${BASH_SOURCE[2]##*/}:${BASH_LINENO[1]}"
    
    # Check if should log this level
    if ! should_log "$level"; then
        return 0
    fi
    
    # Rotate if needed
    rotate_logs
    
    # Format: [timestamp] [level] [caller] message
    local log_entry="[$timestamp] [$level] [$caller] $message"
    
    echo "$log_entry" >> "$LOG_FILE"
    
    # Also print to console based on level
    case "$level" in
        "ERROR"|"CRITICAL")
            echo "$log_entry" >&2
            ;;
        "WARNING")
            if [[ "${VERBOSE:-false}" == "true" ]]; then
                echo "$log_entry"
            fi
            ;;
        "INFO")
            if [[ "${VERBOSE:-false}" == "true" ]]; then
                echo "$log_entry"
            fi
            ;;
        "DEBUG")
            if [[ "${DEBUG:-false}" == "true" ]]; then
                echo "$log_entry"
            fi
            ;;
    esac
}

# Structured logging (JSON format)
log_json() {
    local level="$1"
    local message="$2"
    shift 2
    local extra_fields="$@"
    
    local timestamp=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
    local hostname=$(hostname)
    
    local json_log="{\"timestamp\":\"$timestamp\",\"level\":\"$level\",\"hostname\":\"$hostname\",\"message\":\"$message\""
    
    # Add extra fields if provided
    if [[ -n "$extra_fields" ]]; then
        json_log+=",\"extra\":{$extra_fields}"
    fi
    
    json_log+="}"
    
    echo "$json_log" >> "${LOG_FILE}.json"
}

# Log with different levels
log_debug() { log_message "DEBUG" "$1"; }
log_info() { log_message "INFO" "$1"; }
log_warning() { log_message "WARNING" "$1"; }
log_error() { log_message "ERROR" "$1"; }
log_critical() { log_message "CRITICAL" "$1"; }

# Performance logging
log_performance() {
    local operation="$1"
    local duration="$2"
    local details="${3:-}"
    
    log_message "INFO" "PERF: $operation took ${duration}ms ${details}"
}

# Audit logging
log_audit() {
    local action="$1"
    local user="${2:-$(whoami)}"
    local details="${3:-}"
    
    log_message "INFO" "AUDIT: User '$user' performed '$action' $details"
}

# Export functions
export -f init_logging rotate_logs clean_old_logs should_log
export -f log_message log_json
export -f log_debug log_info log_warning log_error log_critical
export -f log_performance log_audit
