#!/bin/bash
# ============================================
# CONFIGURATION FILE
# Supports both inline config and YAML/JSON files
# ============================================

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Paths
LOG_DIR="$SCRIPT_DIR/logs"
OUTPUT_DIR="$SCRIPT_DIR/output"
CONFIG_FILE="$SCRIPT_DIR/config/monitor.yaml"
LOG_FILE="$LOG_DIR/system_monitor.log"

# Monitoring intervals (seconds)
MONITOR_INTERVAL=5
CONTINUOUS_INTERVAL=60

# Alert thresholds
CPU_ALERT_THRESHOLD=90
MEMORY_ALERT_THRESHOLD=85
DISK_ALERT_THRESHOLD=90
TEMP_ALERT_THRESHOLD=80
GPU_ALERT_THRESHOLD=90
GPU_TEMP_THRESHOLD=85
NETWORK_LATENCY_THRESHOLD=100

# Alert configuration
ENABLE_ALERTS=true
ALERT_EMAIL=""
ALERT_WEBHOOK=""
ALERT_LOG_ONLY=true

# Data retention (days)
LOG_RETENTION_DAYS=30
METRIC_RETENTION_DAYS=7

# Performance settings
ENABLE_CACHE=true
CACHE_TTL=2
PARALLEL_EXECUTION=true
MAX_PARALLEL_JOBS=10

# Output formats
DEFAULT_OUTPUT_FORMAT="json"
ENABLE_CSV=true
ENABLE_JSON=true
ENABLE_XML=false
ENABLE_PROMETHEUS=false

# Parse YAML config file (simple parser - requires yq for complex YAML)
parse_yaml_config() {
    local config_file="${1:-$CONFIG_FILE}"
    
    if [[ ! -f "$config_file" ]]; then
        return 1
    fi
    
    # Try using yq if available
    if command -v yq &>/dev/null; then
        eval "$(yq eval -o=shell "$config_file" 2>/dev/null)"
        return $?
    fi
    
    # Fallback: simple bash parser for basic YAML
    while IFS=': ' read -r key value; do
        # Skip comments and empty lines
        [[ "$key" =~ ^#.*$ ]] && continue
        [[ -z "$key" ]] && continue
        
        # Remove leading/trailing whitespace
        key=$(echo "$key" | xargs)
        value=$(echo "$value" | xargs)
        
        # Convert to uppercase and export
        key=$(echo "$key" | tr '[:lower:]' '[:upper:]' | tr '-' '_')
        
        # Remove quotes from value
        value=$(echo "$value" | sed 's/^["'"'"']//;s/["'"'"']$//')
        
        export "$key=$value" 2>/dev/null
    done < "$config_file"
}

# Parse JSON config file
parse_json_config() {
    local config_file="${1:-$CONFIG_FILE}"
    
    if [[ ! -f "$config_file" ]]; then
        return 1
    fi
    
    # Try using jq if available
    if command -v jq &>/dev/null; then
        while IFS='=' read -r key value; do
            export "$key=$value"
        done < <(jq -r 'to_entries | .[] | "\(.key | ascii_upcase)=\(.value)"' "$config_file" 2>/dev/null)
        return $?
    fi
    
    # Fallback: basic JSON parsing
    local json_content=$(cat "$config_file")
    
    # Extract key-value pairs (simple regex - not for nested JSON)
    while IFS= read -r line; do
        if [[ "$line" =~ \"([^\"]+)\"[[:space:]]*:[[:space:]]*\"?([^,\"]+)\"? ]]; then
            local key="${BASH_REMATCH[1]}"
            local value="${BASH_REMATCH[2]}"
            
            key=$(echo "$key" | tr '[:lower:]' '[:upper:]' | tr '-' '_')
            export "$key=$value"
        fi
    done <<< "$json_content"
}

# Load configuration from file
load_config() {
    local config_file="${1:-$CONFIG_FILE}"
    
    if [[ ! -f "$config_file" ]]; then
        echo "Config file not found: $config_file. Using defaults."
        return 1
    fi
    
    # Detect format by extension
    case "${config_file##*.}" in
        yaml|yml)
            parse_yaml_config "$config_file"
            ;;
        json)
            parse_json_config "$config_file"
            ;;
        *)
            echo "Unknown config format. Supported: .yaml, .yml, .json"
            return 1
            ;;
    esac
}

# Get config value with default
get_config() {
    local key="$1"
    local default="$2"
    local value="${!key}"
    
    echo "${value:-$default}"
}

# Set config value at runtime
set_config() {
    local key="$1"
    local value="$2"
    
    export "$key=$value"
}

# Validate configuration
validate_config() {
    local errors=0
    
    # Validate numeric thresholds
    for var in CPU_ALERT_THRESHOLD MEMORY_ALERT_THRESHOLD DISK_ALERT_THRESHOLD TEMP_ALERT_THRESHOLD; do
        local value="${!var}"
        if ! [[ "$value" =~ ^[0-9]+$ ]] || [[ "$value" -lt 0 ]] || [[ "$value" -gt 100 ]]; then
            echo "Error: Invalid value for $var: $value (must be 0-100)"
            ((errors++))
        fi
    done
    
    # Validate intervals
    for var in MONITOR_INTERVAL CONTINUOUS_INTERVAL CACHE_TTL; do
        local value="${!var}"
        if ! [[ "$value" =~ ^[0-9]+$ ]] || [[ "$value" -lt 1 ]]; then
            echo "Error: Invalid value for $var: $value (must be >= 1)"
            ((errors++))
        fi
    done
    
    # Validate directories exist
    for dir in LOG_DIR OUTPUT_DIR; do
        local path="${!dir}"
        if [[ ! -d "$path" ]]; then
            mkdir -p "$path" 2>/dev/null || {
                echo "Error: Cannot create directory $dir: $path"
                ((errors++))
            }
        fi
    done
    
    return $errors
}

# Export variables
export LOG_DIR OUTPUT_DIR LOG_FILE CONFIG_FILE
export MONITOR_INTERVAL CONTINUOUS_INTERVAL
export CPU_ALERT_THRESHOLD MEMORY_ALERT_THRESHOLD DISK_ALERT_THRESHOLD TEMP_ALERT_THRESHOLD
export GPU_ALERT_THRESHOLD GPU_TEMP_THRESHOLD NETWORK_LATENCY_THRESHOLD
export ENABLE_ALERTS ALERT_EMAIL ALERT_WEBHOOK ALERT_LOG_ONLY
export LOG_RETENTION_DAYS METRIC_RETENTION_DAYS
export ENABLE_CACHE CACHE_TTL PARALLEL_EXECUTION MAX_PARALLEL_JOBS
export DEFAULT_OUTPUT_FORMAT ENABLE_CSV ENABLE_JSON ENABLE_XML ENABLE_PROMETHEUS

# Export functions
export -f parse_yaml_config parse_json_config load_config get_config set_config validate_config

# Try to load config file if it exists
if [[ -f "$CONFIG_FILE" ]]; then
    load_config "$CONFIG_FILE" 2>/dev/null || true
fi
