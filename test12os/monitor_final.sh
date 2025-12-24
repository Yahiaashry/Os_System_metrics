#!/bin/bash

# Load CPU monitoring functions
cd "$(dirname "$0")/.."
source system_monitor/utils/platform_detect.sh
source system_monitor/modules/cpu_monitor.sh
source system_monitor/modules/memory_monitor.sh
source system_monitor/modules/disk_monitor.sh
source system_monitor/modules/network_monitor.sh
source system_monitor/modules/gpu_monitor.sh
source system_monitor/modules/system_monitor.sh

# Colors
BLUE='\033[0;34m'
CYAN='\033[0;36m'
PURPLE='\033[0;35m'
GREEN='\033[0;32m'
NC='\033[0m'

# Initialize first CPU reading
get_cpu_usage > /dev/null 2>&1
sleep 0.5

while true; do
    clear
    
    echo -e "${BLUE}════════════════════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}            COMPREHENSIVE SYSTEM MONITORING DASHBOARD${NC}"
    echo -e "${CYAN}                $(date '+%Y-%m-%d %H:%M:%S %Z')${NC}"
    echo -e "${BLUE}════════════════════════════════════════════════════════════════${NC}"
    echo ""
    
    echo "┌───────────── SYSTEM STATUS ─────────────┐"
    
    # CPU Performance
    echo -e "${PURPLE}═══════════════ CPU PERFORMANCE ══════════════${NC}"
    

    cpu_model=$(get_cpu_model)
    cpu_cores=$(get_cpu_cores)

    cpu_usage=$(get_cpu_usage)
    cpu_freq=$(get_cpu_freq)
    cpu_temp_raw=$(get_cpu_temp)
    cpu_temp=$(echo "scale=1; $cpu_temp_raw / 1000" | bc 2>/dev/null || echo "$cpu_temp_raw")
    load_avg=$(get_load_average)
    
    # Get uptime
    uptime_seconds=$(awk '{print int($1)}' /proc/uptime 2>/dev/null)
    uptime_days=$((uptime_seconds / 86400))
    uptime_hours=$(( (uptime_seconds % 86400) / 3600 ))
    uptime_minutes=$(( (uptime_seconds % 3600) / 60 ))
    
    printf "%-20s %s\n" "Model:" "$cpu_model"
    printf "%-20s %s cores\n" "Cores:" "$cpu_cores"
 
    echo ""
    printf "%-20s %s%%\n" "Usage:" "$cpu_usage"
    printf "%-20s %s MHz\n" "Frequency:" "$cpu_freq"
    printf "%-20s %s°C\n" "Temperature:" "$cpu_temp"
    echo ""
    printf "%-20s %s\n" "Load Avg:" "$load_avg"
    printf "%-20s %sd %sh %sm\n" "Uptime:" "$uptime_days" "$uptime_hours" "$uptime_minutes"
    
    echo ""
    
    # Memory - Read actual WSL metrics from /proc/meminfo
    echo -e "${PURPLE}══════════════ MEMORY CONSUMPTION ══════════════${NC}"
    
    # Read memory values from /proc/meminfo
    mem_total=$(grep 'MemTotal:' /proc/meminfo | awk '{print int($2/1024)}')
    mem_free=$(grep 'MemFree:' /proc/meminfo | awk '{print int($2/1024)}')
    mem_available=$(grep 'MemAvailable:' /proc/meminfo | awk '{print int($2/1024)}')
    mem_buffers=$(grep 'Buffers:' /proc/meminfo | awk '{print int($2/1024)}')
    mem_cached=$(grep '^Cached:' /proc/meminfo | awk '{print int($2/1024)}')
    
    # Calculate used memory (total - free - buffers - cached)
    mem_used=$((mem_total - mem_free - mem_buffers - mem_cached))
    mem_usage=$((mem_used * 100 / mem_total))
    
    printf "%-20s %s%%\n" "Memory Usage:" "$mem_usage"
    printf "%-20s %s MB\n" "Total:" "$mem_total"
    printf "%-20s %s MB\n" "Used:" "$mem_used"
    printf "%-20s %s MB\n" "Available:" "$mem_available"
    printf "%-20s %s MB\n" "Free:" "$mem_free"
    printf "%-20s %s MB\n" "Buffers:" "$mem_buffers"
    printf "%-20s %s MB\n" "Cached:" "$mem_cached"
    
    # Swap info
    swap_total=$(grep 'SwapTotal:' /proc/meminfo | awk '{print int($2/1024)}')
    swap_free=$(grep 'SwapFree:' /proc/meminfo | awk '{print int($2/1024)}')
    swap_used=$((swap_total - swap_free))
    if [[ $swap_total -gt 0 ]]; then
        swap_percent=$((swap_used * 100 / swap_total))
    else
        swap_percent=0
    fi
    
    echo ""
    echo "Swap Memory:"
    printf "%-20s %s%%\n" "Swap Usage:" "$swap_percent"
    printf "%-20s %s MB\n" "Total Swap:" "$swap_total"
    printf "%-20s %s MB\n" "Used Swap:" "$swap_used"
    printf "%-20s %s MB\n" "Free Swap:" "$swap_free"
    
    echo "└─────────────────────────────────────────┘"
    echo ""
    
    # Resource Usage
    echo "┌───────────── RESOURCE USAGE ─────────────┐"
    
    # Disk - Read actual WSL block devices from /sys/block
    echo -e "${PURPLE}════════════════ DISK USAGE ════════════════${NC}"
    
    # Get block devices from /sys/block (skip loop and ram devices)
    disk_info=""
    for device in /sys/block/*; do
        dev_name=$(basename "$device")
        
        # Skip loop, ram devices, and dm devices
        if [[ $dev_name == loop* ]] || [[ $dev_name == ram* ]] || [[ $dev_name == dm* ]]; then
            continue
        fi
        
        # Get device size from /sys/block
        if [[ -f "$device/size" ]]; then
            size_sectors=$(cat "$device/size" 2>/dev/null || echo "0")
            if [[ $size_sectors -gt 0 ]]; then
                size_gb=$(echo "scale=1; $size_sectors * 512 / 1024 / 1024 / 1024" | bc 2>/dev/null || echo "0.0")
                printf "%-20s %s GB\n" "/dev/${dev_name}:" "$size_gb"
            fi
        fi
    done
    
    # Also show filesystem usage for root
    echo ""
    root_usage=$(df -h / 2>/dev/null | awk 'NR==2 {print $5}' | tr -d '%')
    root_total=$(df -h / 2>/dev/null | awk 'NR==2 {print $2}')
    root_used=$(df -h / 2>/dev/null | awk 'NR==2 {print $3}')
    root_avail=$(df -h / 2>/dev/null | awk 'NR==2 {print $4}')
    
    if [[ -n "$root_usage" ]]; then
        printf "%-20s %s%%\n" "Root (/) Usage:" "$root_usage"
        printf "%-20s %s\n" "Total:" "$root_total"
        printf "%-20s %s\n" "Used:" "$root_used"
        printf "%-20s %s\n" "Available:" "$root_avail"
    fi
    
    echo ""
    
    # Network
    echo -e "${PURPLE}════════════ NETWORK INFORMATION ════════════${NC}"
    interface=$(get_network_interface)
    network_status=$(get_network_status)
    rx_bytes=$(get_rx_bytes)
    tx_bytes=$(get_tx_bytes)
    
    rx_kbps=$(echo "scale=1; $rx_bytes / 1024" | bc 2>/dev/null || echo "0.0")
    tx_kbps=$(echo "scale=1; $tx_bytes / 1024" | bc 2>/dev/null || echo "0.0")
    
    printf "%-20s %s Kbps\n" "Send:" "$tx_kbps"
    printf "%-20s %s Kbps\n" "Receive:" "$rx_kbps"
    echo ""
    printf "%-20s %s\n" "Adapter:" "$interface"
    printf "%-20s %s\n" "State:" "$network_status"
    
    # Get IP addresses if available
    if command -v ip &> /dev/null; then
        ipv4=$(ip -4 addr show "$interface" 2>/dev/null | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | head -1)
        ipv6=$(ip -6 addr show "$interface" 2>/dev/null | grep -oP '(?<=inet6\s)[0-9a-f:]+' | head -1)
        [[ -n "$ipv4" ]] && printf "%-20s %s\n" "IPv4:" "$ipv4"
        [[ -n "$ipv6" ]] && printf "%-20s %s\n" "IPv6:" "$ipv6"
    fi
    
    echo ""
    
    # GPU
    echo -e "${PURPLE}═══════════════ GPU UTILIZATION ══════════════${NC}"
    gpu_type=$(get_gpu_type)
    gpu_model=$(get_gpu_model)
    gpu_usage=$(get_gpu_usage)
    gpu_temp=$(get_gpu_temp)
    gpu_memory=$(get_gpu_memory)
    gpu_total_mem=$(get_gpu_total_memory)
    
    printf "%-20s %s\n" "Type:" "$gpu_type"
    printf "%-20s %s\n" "Model:" "$gpu_model"
    printf "%-20s %s%%\n" "Usage:" "$gpu_usage"
    printf "%-20s %s°C\n" "Temperature:" "$gpu_temp"
    printf "%-20s %s MB / %s MB\n" "Memory:" "$gpu_memory" "$gpu_total_mem"
    
    echo ""
    
    # System Load
    echo -e "${PURPLE}════════════════ SYSTEM LOAD ════════════════${NC}"
    hostname=$(hostname)
    os_info=$(get_os_info)
    kernel=$(get_kernel_version)
    process_count=$(get_process_count)
    user_count=$(get_user_count)
    
    printf "%-20s %s\n" "Hostname:" "$hostname"
    printf "%-20s %s\n" "OS:" "$os_info"
    printf "%-20s %s\n" "Kernel:" "$kernel"
    printf "%-20s %s\n" "Processes:" "$process_count"
    printf "%-20s %s\n" "Users:" "$user_count"
    
    echo "└─────────────────────────────────────────┘"
    echo ""
    
    echo -e "${BLUE}════════════════════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}Interface: $interface | Update: 2s | $(date '+%H:%M:%S')${NC}"
    echo -e "${CYAN}Press Ctrl+C to exit${NC}"
    echo -e "${BLUE}════════════════════════════════════════════════════════════════${NC}"
    echo ""
    
    sleep 2
done
