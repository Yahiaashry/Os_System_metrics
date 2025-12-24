#!/bin/bash
# ============================================
# SYSTEM MONITORING SCRIPT - MAIN CONTROLLER
# Project 12th - Arab Academy
# Member 1: Yahia Ashry - 231027201
# ============================================


# Mointor Windows 

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "$SCRIPT_DIR/utils/config.sh"
source "$SCRIPT_DIR/utils/logger.sh"
source "$SCRIPT_DIR/utils/error_handler.sh"

# Load history tracker if available
if [ -f "$SCRIPT_DIR/utils/history_tracker.sh" ]; then
    source "$SCRIPT_DIR/utils/history_tracker.sh"
    HISTORY_DIR="$SCRIPT_DIR/data/history"
    init_history
fi

source "$SCRIPT_DIR/modules/cpu_monitor.sh"
source "$SCRIPT_DIR/modules/memory_monitor.sh"
source "$SCRIPT_DIR/modules/disk_monitor.sh"
source "$SCRIPT_DIR/modules/network_monitor.sh"
source "$SCRIPT_DIR/modules/gpu_monitor.sh"
source "$SCRIPT_DIR/modules/system_monitor.sh"

mkdir -p "$SCRIPT_DIR/logs"
mkdir -p "$SCRIPT_DIR/output"
mkdir -p "$SCRIPT_DIR/data/history"

LOG_FILE="$SCRIPT_DIR/logs/system_monitor.log"

init_logging
log_message "INFO" "System monitoring started"

display_summary() {
    local timestamp=$(date)
    local hostname=$(hostname)
    
    # Collect all metrics
    local cpu_model=$(get_cpu_model)
    local cpu_usage=$(get_cpu_usage)
    local cpu_temp=$(get_cpu_temp)
    local cpu_cores=$(get_cpu_cores)
    local cpu_freq=$(get_cpu_freq)
    local load_avg=$(get_load_average)
    
    local gpu_model=$(get_gpu_model)
    local gpu_type=$(get_gpu_type)
    local gpu_usage=$(get_gpu_usage)
    local gpu_temp=$(get_gpu_temp)
    local gpu_memory=$(get_gpu_memory)
    local gpu_total=$(get_gpu_total_memory)
    
    local mem_usage=$(get_memory_usage)
    local mem_total=$(get_total_memory)
    local mem_used=$(get_used_memory)
    local mem_free=$(get_free_memory)
    
    local disk_usage=$(get_disk_usage)
    local disk_total=$(get_disk_total)
    local disk_used=$(get_disk_used)
    local disk_free=$(get_disk_free)
    local smart_status=$(get_smart_status)
    
    local interface=$(get_network_interface)
    local network_status=$(get_network_status)
    local rx_bytes=$(get_rx_bytes)
    local tx_bytes=$(get_tx_bytes)
    
    local uptime=$(get_uptime)
    local process_count=$(get_process_count)
    local user_count=$(get_user_count)
    local os_info=$(get_os_info)
    
    # Convert bytes to MB for display
    local rx_mb=$(echo "scale=2; $rx_bytes / 1048576" | bc 2>/dev/null || echo "0")
    local tx_mb=$(echo "scale=2; $tx_bytes / 1048576" | bc 2>/dev/null || echo "0")
    
    # Convert MB to GB for memory display
    local mem_total_gb=$(echo "scale=2; $mem_total / 1024" | bc 2>/dev/null || echo "0")
    local mem_used_gb=$(echo "scale=2; $mem_used / 1024" | bc 2>/dev/null || echo "0")
    local mem_free_gb=$(echo "scale=2; $mem_free / 1024" | bc 2>/dev/null || echo "0")
    
    echo ""
    echo "╔══════════════════════════════════════════════════════════════════╗"
    echo "║              🖥️  SYSTEM MONITORING DASHBOARD                     ║"
    echo "╚══════════════════════════════════════════════════════════════════╝"
    echo "📅 Timestamp: $timestamp"
    echo "🖥️  Hostname: $hostname"
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo " CPU PERFORMANCE: ${cpu_model}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "   Usage:       ${cpu_usage}%"
    if [[ "$cpu_temp" != "N/A" ]]; then
        echo "   Temperature: ${cpu_temp}°C"
    else
        echo "   Temperature: N/A"
    fi
    echo "   Cores:       ${cpu_cores}"
    if [[ -n "$cpu_freq" && "$cpu_freq" != "N/A" ]]; then
        echo "   Frequency:   ${cpu_freq} MHz"
    else
        echo "   Frequency:   N/A"
    fi
    echo "   Load Avg:    ${load_avg}"
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo " GPU UTILIZATION: ${gpu_model}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "   Type:        ${gpu_type}"
    echo "   Usage:       ${gpu_usage}%"
    if [[ "$gpu_temp" != "N/A" ]]; then
        echo "   Temperature: ${gpu_temp}°C"
    else
        echo "   Temperature: N/A"
    fi
    echo "   Memory:      ${gpu_memory} MB / ${gpu_total} MB"
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo " MEMORY CONSUMPTION"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "   Usage:       ${mem_usage}%"
    echo "   Total:       ${mem_total_gb} GB"
    echo "   Used:        ${mem_used_gb} GB"
    echo "   Free:        ${mem_free_gb} GB"
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo " DISK USAGE"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "   Root Usage:  ${disk_usage}%"
    echo "   Total (GB):  ${disk_total}"
    echo "   Used (GB):   ${disk_used}"
    echo "   Free (GB):   ${disk_free}"
    if [[ -n "$smart_status" ]]; then
        echo "   SMART:       ${smart_status}"
    else
        echo "   SMART:       N/A"
    fi
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo " NETWORK INTERFACE"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "   Interface:   ${interface}"
    echo "   Status:      ${network_status}"
    echo "   RX:          ${rx_mb} MB"
    echo "   TX:          ${tx_mb} MB"
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "⚡ SYSTEM LOAD"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "   Uptime:      ${uptime}"
    echo "   Processes:   ${process_count}"
    echo "   Users:       ${user_count}"
    echo "   OS:          ${os_info}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
}

collect_all_metrics() {
    log_message "INFO" "Collecting all system metrics..."
    
    local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    local hostname=$(hostname)
    
    # Collect metrics
    local cpu_usage=$(get_cpu_usage)
    local mem_usage=$(get_memory_usage)
    local disk_usage=$(get_disk_usage)
    local gpu_usage=$(get_gpu_usage)
    
    # Store in history if tracking is enabled
    if command -v store_sample &>/dev/null; then
        store_sample "cpu_usage" "$cpu_usage"
        store_sample "memory_usage" "$mem_usage"
        store_sample "disk_usage" "$disk_usage"
        store_sample "gpu_usage" "$gpu_usage"
    fi
    
    local json_output="{
  \"timestamp\": \"$timestamp\",
  \"hostname\": \"$hostname\",
  \"metrics\": {"
    
    json_output+="\"cpu\": {
      \"usage_percent\": $cpu_usage,
      \"temperature_c\": \"$(get_cpu_temp | sed 's/°C//')\",
      \"cores\": $(get_cpu_cores),
      \"frequency_mhz\": \"$(get_cpu_freq)\"
    },"
    
    json_output+="\"memory\": {
      \"usage_percent\": $mem_usage,
      \"total_mb\": $(get_total_memory),
      \"used_mb\": $(get_used_memory),
      \"free_mb\": $(get_free_memory)
    },"
    
    json_output+="\"disk\": {
      \"usage_percent\": $(get_disk_usage),
      \"total_gb\": \"$(get_disk_total)\",
      \"used_gb\": \"$(get_disk_used)\",
      \"free_gb\": \"$(get_disk_free)\",
      \"smart_status\": \"$(get_smart_status)\"
    },"
    
    json_output+="\"network\": {
      \"status\": \"$(get_network_status)\",
      \"interface\": \"$(get_network_interface)\",
      \"rx_bytes\": $(get_rx_bytes),
      \"tx_bytes\": $(get_tx_bytes)
    },"
    
    json_output+="\"gpu\": {
      \"type\": \"$(get_gpu_type)\",
      \"usage_percent\": $(get_gpu_usage),
      \"temperature_c\": \"$(get_gpu_temp)\",
      \"memory_mb\": $(get_gpu_memory)
    },"
    
    json_output+="\"system\": {
      \"load_average\": \"$(get_load_average)\",
      \"uptime\": \"$(get_uptime)\",
      \"processes\": $(get_process_count),
      \"users\": $(get_user_count),
      \"os\": \"$(get_os_info)\",
      \"kernel\": \"$(get_kernel_version)\"
    }"
    
    json_output+="}}"
    
    echo "$json_output" > "$SCRIPT_DIR/output/metrics.json"
    
    echo "timestamp,hostname,metric,value,unit" > "$SCRIPT_DIR/output/metrics.csv"
    echo "$timestamp,$hostname,cpu_usage,$(get_cpu_usage),percent" >> "$SCRIPT_DIR/output/metrics.csv"
    echo "$timestamp,$hostname,cpu_temp,$(get_cpu_temp | sed 's/°C//'),celsius" >> "$SCRIPT_DIR/output/metrics.csv"
    echo "$timestamp,$hostname,memory_usage,$(get_memory_usage),percent" >> "$SCRIPT_DIR/output/metrics.csv"
    echo "$timestamp,$hostname,disk_usage,$(get_disk_usage),percent" >> "$SCRIPT_DIR/output/metrics.csv"
    echo "$timestamp,$hostname,load_average,\"$(get_load_average)\",load" >> "$SCRIPT_DIR/output/metrics.csv"
    echo "$timestamp,$hostname,gpu_type,\"$(get_gpu_type)\",type" >> "$SCRIPT_DIR/output/metrics.csv"
    echo "$timestamp,$hostname,gpu_usage,$(get_gpu_usage),percent" >> "$SCRIPT_DIR/output/metrics.csv"
    echo "$timestamp,$hostname,smart_status,\"$(get_smart_status)\",status" >> "$SCRIPT_DIR/output/metrics.csv"
    echo "$timestamp,$hostname,network_status,\"$(get_network_status)\",status" >> "$SCRIPT_DIR/output/metrics.csv"
    
    log_message "INFO" "Metrics saved to output directory"
}

main() {
    case "${1:-}" in
        "collect")
            collect_all_metrics
            ;;
        "continuous")
            while true; do
                collect_all_metrics
                display_summary
                sleep ${2:-5}
            done
            ;;
        "json")
            collect_all_metrics
            cat "$SCRIPT_DIR/output/metrics.json"
            ;;
        "csv")
            collect_all_metrics
            cat "$SCRIPT_DIR/output/metrics.csv"
            ;;
        "help"|"-h"|"--help")
            echo "Usage: $0 [command]"
            echo "Commands:"
            echo "  collect     - Collect metrics once"
            echo "  continuous [sec] - Run continuously (default: 5s)"
            echo "  json        - Output JSON only"
            echo "  csv         - Output CSV only"
            echo "  help        - Show this help"
            ;;
        *)
            collect_all_metrics
            display_summary
            ;;
    esac
}

main "$@"

log_message "INFO" "System monitoring completed"
