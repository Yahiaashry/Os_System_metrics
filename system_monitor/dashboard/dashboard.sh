#!/bin/bash
# ============================================
# INTERACTIVE SYSTEM MONITORING DASHBOARD
# Using dialog/whiptail for TUI interface
# ============================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Check for dialog or whiptail
if command -v dialog &>/dev/null; then
    DIALOG="dialog"
elif command -v whiptail &>/dev/null; then
    DIALOG="whiptail"
else
    echo "Error: Neither 'dialog' nor 'whiptail' is installed"
    echo "Please install: sudo apt-get install dialog"
    exit 1
fi

# Load monitoring modules
source "$SCRIPT_DIR/utils/config.sh"
source "$SCRIPT_DIR/utils/logger.sh"
source "$SCRIPT_DIR/modules/cpu_monitor.sh"
source "$SCRIPT_DIR/modules/memory_monitor.sh"
source "$SCRIPT_DIR/modules/disk_monitor.sh"
source "$SCRIPT_DIR/modules/network_monitor.sh"
source "$SCRIPT_DIR/modules/gpu_monitor.sh"
source "$SCRIPT_DIR/modules/system_monitor.sh"

TEMP_FILE=$(mktemp)
trap "rm -f $TEMP_FILE" EXIT

# Dialog dimensions
HEIGHT=20
WIDTH=70
MENU_HEIGHT=12

# Main menu
show_main_menu() {
    $DIALOG --clear --title "System Monitoring Dashboard" \
        --menu "Choose an option:" $HEIGHT $WIDTH $MENU_HEIGHT \
        1 "📊 View Real-Time Metrics" \
        2 "💾 View Detailed CPU Info" \
        3 "🎮 View GPU Information" \
        4 "💿 View Disk Status" \
        5 "🌐 View Network Status" \
        6 "⚙️  Configure Alerts" \
        7 "📝 View System Logs" \
        8 "📈 Generate Report" \
        9 "🔄 Continuous Monitoring" \
        0 "Exit" 2>$TEMP_FILE
    
    return $?
}

# Real-time metrics view
view_realtime_metrics() {
    local cpu_usage=$(get_cpu_usage)
    local cpu_temp=$(get_cpu_temp)
    local mem_usage=$(get_memory_usage)
    local mem_total=$(get_total_memory)
    local mem_used=$(get_used_memory)
    local disk_usage=$(get_disk_usage)
    local disk_total=$(get_disk_total)
    local gpu_type=$(get_gpu_type)
    local gpu_usage=$(get_gpu_usage)
    local gpu_temp=$(get_gpu_temp)
    local network_status=$(get_network_status)
    local uptime=$(get_uptime)
    local load_avg=$(get_load_average)
    
    local message="
╔════════════════════════════════════════════════════════════╗
║              SYSTEM METRICS - $(date +%H:%M:%S)                    ║
╚════════════════════════════════════════════════════════════╝

📊 CPU Performance:
   Usage:       ${cpu_usage}%
   Temperature: ${cpu_temp}
   Load Avg:    ${load_avg}

💾 Memory Status:
   Usage:       ${mem_usage}%
   Total:       ${mem_total} MB
   Used:        ${mem_used} MB

💿 Disk Status:
   Usage:       ${disk_usage}%
   Total:       ${disk_total} GB

🎮 GPU Status:
   Type:        ${gpu_type}
   Usage:       ${gpu_usage}%
   Temperature: ${gpu_temp}

🌐 Network:
   Status:      ${network_status}

⚡ System:
   Uptime:      ${uptime}

Press OK to refresh, Cancel to return
"
    
    $DIALOG --title "Real-Time System Metrics" \
        --yesno "$message" 30 65
    
    if [ $? -eq 0 ]; then
        view_realtime_metrics  # Refresh
    fi
}

# Detailed CPU information
view_cpu_details() {
    local cpu_usage=$(get_cpu_usage)
    local cpu_temp=$(get_cpu_temp)
    local cpu_cores=$(get_cpu_cores)
    local cpu_freq=$(get_cpu_freq)
    local cpu_model=$(get_cpu_model)
    local load_avg=$(get_load_average)
    
    local message="
CPU Details
═══════════

Model:       ${cpu_model}
Cores:       ${cpu_cores}
Frequency:   ${cpu_freq} MHz
Temperature: ${cpu_temp}

Current Usage:    ${cpu_usage}%
Load Average:     ${load_avg}

Per-Core Usage:
$(get_cpu_load_per_core 2>/dev/null | head -8)
"
    
    $DIALOG --title "Detailed CPU Information" \
        --msgbox "$message" 25 70
}

# GPU information
view_gpu_info() {
    local gpu_type=$(get_gpu_type)
    local gpu_usage=$(get_gpu_usage)
    local gpu_temp=$(get_gpu_temp)
    local gpu_memory=$(get_gpu_memory)
    local gpu_total=$(get_gpu_total_memory)
    local gpu_driver=$(get_gpu_driver)
    
    local message="
GPU Information
═══════════════

Type:         ${gpu_type}
Driver:       ${gpu_driver}

Usage:        ${gpu_usage}%
Temperature:  ${gpu_temp}
Memory:       ${gpu_memory} MB / ${gpu_total} MB

Detailed Information:
$(get_all_gpus_info 2>/dev/null | head -10)
"
    
    $DIALOG --title "GPU Status" \
        --msgbox "$message" 22 70
}

# Disk status
view_disk_status() {
    local disk_usage=$(get_disk_usage)
    local disk_total=$(get_disk_total)
    local disk_used=$(get_disk_used)
    local disk_free=$(get_disk_free)
    local smart_status=$(get_smart_status)
    local inode_usage=$(get_inode_usage 2>/dev/null)
    
    local message="
Disk Status
═══════════

Root Partition:
  Usage:      ${disk_usage}%
  Total:      ${disk_total} GB
  Used:       ${disk_used} GB
  Free:       ${disk_free} GB
  SMART:      ${smart_status}
  Inodes:     ${inode_usage}%

Partition Details:
$(df -h | head -10)

I/O Statistics:
$(get_disk_io 2>/dev/null | head -5)
"
    
    $DIALOG --title "Disk Status & Health" \
        --msgbox "$message" 28 75
}

# Network status
view_network_status() {
    local network_status=$(get_network_status)
    local interface=$(get_network_interface)
    local rx_bytes=$(get_rx_bytes)
    local tx_bytes=$(get_tx_bytes)
    local rx_mb=$(echo "scale=2; $rx_bytes / 1048576" | bc 2>/dev/null || echo "0")
    local tx_mb=$(echo "scale=2; $tx_bytes / 1048576" | bc 2>/dev/null || echo "0")
    
    local message="
Network Status
══════════════

Primary Interface: ${interface}
Status:            ${network_status}

Data Transfer:
  Received:  ${rx_mb} MB
  Transmitted: ${tx_mb} MB

Network Interfaces:
$(ip -brief addr 2>/dev/null || ifconfig -a 2>/dev/null | head -20)

Active Connections:
$(ss -s 2>/dev/null || netstat -s 2>/dev/null | head -10)
"
    
    $DIALOG --title "Network Information" \
        --msgbox "$message" 28 75
}

# Configure alerts
configure_alerts() {
    $DIALOG --title "Alert Configuration" \
        --form "Configure monitoring thresholds:" 20 60 5 \
        "CPU Alert (%):"        1 1 "${CPU_ALERT_THRESHOLD:-90}"     1 20 10 0 \
        "Memory Alert (%):"     2 1 "${MEMORY_ALERT_THRESHOLD:-85}"  2 20 10 0 \
        "Disk Alert (%):"       3 1 "${DISK_ALERT_THRESHOLD:-90}"    3 20 10 0 \
        "Temp Alert (°C):"      4 1 "${TEMP_ALERT_THRESHOLD:-80}"    4 20 10 0 \
        "GPU Alert (%):"        5 1 "${GPU_ALERT_THRESHOLD:-90}"     5 20 10 0 \
        2>$TEMP_FILE
    
    if [ $? -eq 0 ]; then
        # Read values
        local values=($(cat $TEMP_FILE))
        
        # Update config file
        local config_file="$SCRIPT_DIR/utils/config.sh"
        if [ -f "$config_file" ]; then
            sed -i "s/^CPU_ALERT_THRESHOLD=.*/CPU_ALERT_THRESHOLD=${values[0]}/" "$config_file"
            sed -i "s/^MEMORY_ALERT_THRESHOLD=.*/MEMORY_ALERT_THRESHOLD=${values[1]}/" "$config_file"
            sed -i "s/^DISK_ALERT_THRESHOLD=.*/DISK_ALERT_THRESHOLD=${values[2]}/" "$config_file"
            sed -i "s/^TEMP_ALERT_THRESHOLD=.*/TEMP_ALERT_THRESHOLD=${values[3]}/" "$config_file"
            sed -i "s/^GPU_ALERT_THRESHOLD=.*/GPU_ALERT_THRESHOLD=${values[4]}/" "$config_file"
            
            $DIALOG --title "Success" --msgbox "Alert thresholds updated successfully!" 7 50
        else
            $DIALOG --title "Error" --msgbox "Configuration file not found!" 7 50
        fi
    fi
}

# View logs
view_logs() {
    local log_file="$SCRIPT_DIR/logs/system_monitor.log"
    
    if [ -f "$log_file" ]; then
        $DIALOG --title "System Monitor Logs" \
            --textbox "$log_file" 25 80
    else
        $DIALOG --title "Error" \
            --msgbox "Log file not found: $log_file" 7 50
    fi
}

# Generate report
generate_report() {
    $DIALOG --title "Generate Report" \
        --menu "Choose report format:" 15 60 4 \
        1 "JSON Report" \
        2 "CSV Report" \
        3 "Text Summary" \
        4 "HTML Report (Python)" 2>$TEMP_FILE
    
    if [ $? -eq 0 ]; then
        local choice=$(cat $TEMP_FILE)
        
        case $choice in
            1)
                bash "$SCRIPT_DIR/monitor.sh" json > "$SCRIPT_DIR/output/report.json"
                $DIALOG --title "Success" \
                    --msgbox "JSON report generated:\n$SCRIPT_DIR/output/report.json" 8 60
                ;;
            2)
                bash "$SCRIPT_DIR/monitor.sh" csv > "$SCRIPT_DIR/output/report.csv"
                $DIALOG --title "Success" \
                    --msgbox "CSV report generated:\n$SCRIPT_DIR/output/report.csv" 8 60
                ;;
            3)
                bash "$SCRIPT_DIR/monitor.sh" > "$SCRIPT_DIR/output/report.txt"
                $DIALOG --title "Success" \
                    --msgbox "Text report generated:\n$SCRIPT_DIR/output/report.txt" 8 60
                ;;
            4)
                # Call Python report generator
                if [ -f "$SCRIPT_DIR/../python_monitor/venv/bin/activate" ]; then
                    source "$SCRIPT_DIR/../python_monitor/venv/bin/activate"
                    python3 -m python_monitor.reporting.report_generator \
                        --hours 24 --output "$SCRIPT_DIR/output/report.html" 2>&1 | \
                        $DIALOG --title "Generating HTML Report" --progressbox 15 70
                    deactivate
                    $DIALOG --title "Success" \
                        --msgbox "HTML report generated:\n$SCRIPT_DIR/output/report.html" 8 60
                else
                    $DIALOG --title "Error" \
                        --msgbox "Python environment not found!" 7 50
                fi
                ;;
        esac
    fi
}

# Continuous monitoring
continuous_monitoring() {
    local interval=5
    
    $DIALOG --inputbox "Enter refresh interval (seconds):" 10 50 "$interval" 2>$TEMP_FILE
    
    if [ $? -eq 0 ]; then
        interval=$(cat $TEMP_FILE)
        
        $DIALOG --title "Starting Continuous Monitoring" \
            --infobox "Monitoring every ${interval} seconds...\nPress Ctrl+C to stop" 5 50
        
        bash "$SCRIPT_DIR/monitor.sh" continuous "$interval"
    fi
}

# Main loop
main() {
    while true; do
        show_main_menu
        
        local retval=$?
        local choice=$(cat $TEMP_FILE)
        
        if [ $retval -ne 0 ] || [ "$choice" = "0" ]; then
            clear
            echo "Exiting dashboard..."
            exit 0
        fi
        
        case $choice in
            1) view_realtime_metrics ;;
            2) view_cpu_details ;;
            3) view_gpu_info ;;
            4) view_disk_status ;;
            5) view_network_status ;;
            6) configure_alerts ;;
            7) view_logs ;;
            8) generate_report ;;
            9) continuous_monitoring ;;
        esac
    done
}

# Run dashboard
main
