#!/bin/bash
# ============================================
# ERROR HANDLER
# ============================================

# Load logger
source "$(dirname "${BASH_SOURCE[0]}")/logger.sh"

# Error handling function
handle_error() {
    local exit_code=$1
    local command=$2
    local line=$3
    
    log_error "Command '$command' failed with exit code $exit_code at line $line"
    exit $exit_code
}

# Set error trap
trap 'handle_error $? "$BASH_COMMAND" "$LINENO"' ERR

# Check command availability
check_command() {
    local cmd=$1
    if ! command -v "$cmd" &> /dev/null; then
        log_warning "Command '$cmd' not found. Some features may be limited."
        return 1
    fi
    return 0
}

# Validate numeric value
validate_numeric() {
    local value=$1
    local min=${2:-0}
    local max=${3:-100}
    
    if ! [[ "$value" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
        log_error "Invalid numeric value: $value"
        return 1
    fi
    
    if (( $(echo "$value < $min" | bc -l) )); then
        log_error "Value $value below minimum $min"
        return 1
    fi
    
    if (( $(echo "$value > $max" | bc -l) )); then
        log_error "Value $value above maximum $max"
        return 1
    fi
    
    return 0
}

# Send alert
send_alert() {
    local message=$1
    local level=${2:-"WARNING"}
    
    log_message "$level" "ALERT: $message"
    
    # Here you could add email, Slack, or other notifications
    if [[ -n "$ALERT_EMAIL" ]] && command -v mail &> /dev/null; then
        echo "$message" | mail -s "System Alert" "$ALERT_EMAIL"
    fi
}

# Cleanup function
cleanup() {
    log_info "Cleaning up resources..."
    # Add cleanup tasks here if needed
}
