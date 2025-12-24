#!/bin/bash

# ============================================
# WSL System Metrics Monitor
# Reads metrics from /sys, /proc, and /sys/block
# ============================================

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
PURPLE='\033[0;35m'
NC='\033[0m' # No Color

# Configuration
INTERVAL=${1:-1}  # Default 1 second interval
SAMPLES=${2:-1}   # Default 1 sample
ENABLE_LOG=false
LOG_FILE="${TMPDIR:-/tmp}/wsl_metrics_$(date +%s).log"

# ============================================
# CPU METRICS FUNCTIONS
# ============================================

get_cpu_usage() {
    # Read from /proc/stat
    local cpu_line=$(grep '^cpu ' /proc/stat)
    local user nice system idle iowait irq softirq steal guest guest_nice
    read -r cpu user nice system idle iowait irq softirq steal guest guest_nice <<< "$cpu_line"
    
    # Calculate total CPU time
    local total=$((user + nice + system + idle + iowait + irq + softirq + steal))
    local idle_total=$((idle + iowait))
    
    # Store previous values for delta calculation
    if [[ -n "$PREV_TOTAL" ]]; then
        local total_diff=$((total - PREV_TOTAL))
        local idle_diff=$((idle_total - PREV_IDLE))
        
        if [[ $total_diff -gt 0 ]]; then
            local usage=$((100 * (total_diff - idle_diff) / total_diff))
            echo "$usage"
        else
            echo "0"
        fi
    fi
    
    # Store current values for next call
    PREV_TOTAL=$total
    PREV_IDLE=$idle_total
}

get_per_cpu_usage() {
    echo -e "${CYAN}Per-CPU Usage:${NC}"
    local cpus=$(grep -c '^processor' /proc/cpuinfo)
    
    for ((i=0; i<cpus; i++)); do
        local freq_file="/sys/devices/system/cpu/cpu$i/cpufreq/scaling_cur_freq"
        local max_freq_file="/sys/devices/system/cpu/cpu$i/cpufreq/scaling_max_freq"
        local min_freq_file="/sys/devices/system/cpu/cpu$i/cpufreq/scaling_min_freq"
        
        if [[ -f "$freq_file" ]]; then
            local cur_freq=$(cat "$freq_file")
            local max_freq=$(cat "$max_freq_file" 2>/dev/null || echo "0")
            local min_freq=$(cat "$min_freq_file" 2>/dev/null || echo "0")
            
            # Convert kHz to GHz
            cur_freq=$(echo "scale=2; $cur_freq / 1000000" | bc)
            max_freq=$(echo "scale=2; $max_freq / 1000000" | bc 2>/dev/null || echo "0")
            min_freq=$(echo "scale=2; $min_freq / 1000000" | bc 2>/dev/null || echo "0")
            
            # Get CPU governor
            local governor=$(cat "/sys/devices/system/cpu/cpu$i/cpufreq/scaling_governor" 2>/dev/null || echo "unknown")
            
            echo -e "  CPU$i: ${GREEN}${cur_freq}GHz${NC} (${min_freq}-${max_freq}GHz) [${governor}]"
        else
            # Fallback to /proc/stat for usage
            local cpu_line=$(grep "^cpu$i" /proc/stat)
            if [[ -n "$cpu_line" ]]; then
                echo -e "  CPU$i: ${YELLOW}Active${NC} (No frequency info)"
            else
                echo -e "  CPU$i: ${RED}Offline${NC}"
            fi
        fi
    done
}

get_cpu_temperature() {
    echo -e "${CYAN}CPU Temperature:${NC}"
    
    # Try hwmon sensors first (most reliable)
    if [[ -d "/sys/class/hwmon" ]]; then
        local found_temp=false
        for hwmon in /sys/class/hwmon/hwmon*; do
            if [[ -f "$hwmon/name" ]]; then
                local sensor_name=$(cat "$hwmon/name")
                
                # Look for CPU-related temperature sensors
                for temp_input in "$hwmon"/temp*_input; do
                    if [[ -f "$temp_input" ]]; then
                        local temp=$(cat "$temp_input" 2>/dev/null)
                        if [[ -n "$temp" && "$temp" != "0" ]]; then
                            temp=$(echo "scale=1; $temp / 1000" | bc)
                            
                            # Get sensor label if available
                            local label_file="${temp_input%_input}_label"
                            local label=""
                            if [[ -f "$label_file" ]]; then
                                label=$(cat "$label_file")
                            else
                                label=$(basename "$temp_input" _input)
                            fi
                            
                            echo -e "  ${sensor_name} - ${label}: ${GREEN}${temp}°C${NC}"
                            found_temp=true
                            
                            # Check for critical/max thresholds
                            local crit_file="${temp_input%_input}_crit"
                            local max_file="${temp_input%_input}_max"
                            
                            if [[ -f "$crit_file" ]]; then
                                local critical=$(cat "$crit_file" 2>/dev/null)
                                if [[ -n "$critical" ]]; then
                                    critical=$(echo "scale=1; $critical / 1000" | bc)
                                    if (( $(echo "$temp >= $critical - 10" | bc -l) )); then
                                        echo -e "    ${RED}⚠ WARNING: Temperature high! (Critical: ${critical}°C)${NC}"
                                    fi
                                fi
                            fi
                            
                            if [[ -f "$max_file" ]]; then
                                local max_temp=$(cat "$max_file" 2>/dev/null)
                                if [[ -n "$max_temp" ]]; then
                                    max_temp=$(echo "scale=1; $max_temp / 1000" | bc)
                                    if (( $(echo "$temp >= $max_temp - 5" | bc -l) )); then
                                        echo -e "    ${YELLOW}⚠ Temperature approaching max: ${max_temp}°C${NC}"
                                    fi
                                fi
                            fi
                        fi
                    fi
                done
            fi
        done
        
        if [[ "$found_temp" == "false" ]]; then
            echo -e "  ${YELLOW}No temperature data in hwmon sensors${NC}"
        fi
    fi
    
    # Try thermal_zone sensors as fallback
    if [[ -d "/sys/class/thermal" ]]; then
        local zone_found=false
        for zone in /sys/class/thermal/thermal_zone*; do
            if [[ -f "$zone/temp" ]]; then
                local temp=$(cat "$zone/temp" 2>/dev/null)
                if [[ -n "$temp" && "$temp" != "0" ]]; then
                    temp=$(echo "scale=1; $temp / 1000" | bc)
                    local zone_type="unknown"
                    if [[ -f "$zone/type" ]]; then
                        zone_type=$(cat "$zone/type")
                    fi
                    
                    echo -e "  ${zone_type}: ${GREEN}${temp}°C${NC}"
                    zone_found=true
                fi
            fi
        done
        
        if [[ "$zone_found" == "false" ]]; then
            echo -e "  ${YELLOW}No thermal zone sensors available${NC}"
        fi
    else
        echo -e "  ${YELLOW}No temperature sensors found (common in WSL)${NC}"
    fi
}

# ============================================
# DISK METRICS FUNCTIONS
# ============================================

get_disk_metrics() {
    echo -e "\n${PURPLE}=== DISK METRICS ===${NC}"
    
    # Find all block devices in /sys/block
    local block_devices=$(ls -d /sys/block/* 2>/dev/null)
    
    if [[ -z "$block_devices" ]]; then
        echo "No block devices found in /sys/block"
        return
    fi
    
    for device in $block_devices; do
        local dev_name=$(basename "$device")
        
        # Skip loop devices and ramdisks unless specified
        if [[ $dev_name == loop* ]] || [[ $dev_name == ram* ]]; then
            continue
        fi
        
        echo -e "\n${CYAN}Device: /dev/${dev_name}${NC}"
        
        # Get device size
        if [[ -f "$device/size" ]]; then
            local size_sectors=$(cat "$device/size")
            local size_gb=$(echo "scale=2; $size_sectors * 512 / 1024 / 1024 / 1024" | bc)
            echo -e "  Size: ${GREEN}${size_gb} GB${NC}"
        fi
        
        # Get device model/type
        if [[ -f "$device/device/model" ]]; then
            local model=$(cat "$device/device/model" | xargs)
            echo -e "  Model: $model"
        elif [[ -f "$device/dm/name" ]]; then
            echo -e "  Type: Device Mapper"
        elif [[ -f "$device/device/type" ]]; then
            local type=$(cat "$device/device/type")
            echo -e "  Type: $type"
        fi
        
        # Get rotational (HDD vs SSD)
        if [[ -f "$device/queue/rotational" ]]; then
            local rotational=$(cat "$device/queue/rotational")
            if [[ $rotational -eq 1 ]]; then
                echo -e "  Type: ${YELLOW}HDD${NC}"
            else
                echo -e "  Type: ${GREEN}SSD${NC}"
            fi
        fi
        
        # Get scheduler
        if [[ -f "$device/queue/scheduler" ]]; then
            local scheduler=$(cat "$device/queue/scheduler" | sed 's/\[//g; s/\]//g')
            echo -e "  Scheduler: $scheduler"
        fi
        
        # Get read/write statistics
        if [[ -f "$device/stat" ]]; then
            local r_ios r_merges r_sectors r_ticks w_ios w_merges w_sectors w_ticks
            read r_ios r_merges r_sectors r_ticks w_ios w_merges w_sectors w_ticks < "$device/stat"
            
            echo -e "  Read Operations: ${r_ios}"
            echo -e "  Write Operations: ${w_ios}"
            
            # Convert sectors to MB
            local read_mb=$(echo "scale=2; $r_sectors * 512 / 1024 / 1024" | bc)
            local write_mb=$(echo "scale=2; $w_sectors * 512 / 1024 / 1024" | bc)
            echo -e "  Data Read: ${read_mb} MB"
            echo -e "  Data Written: ${write_mb} MB"
        fi
        
        # Get queue length
        if [[ -f "$device/inflight" ]]; then
            local inflight=$(cat "$device/inflight")
            echo -e "  In-flight requests: $inflight"
        fi
        
        # Check for partitions
        if ls "$device"/$dev_name* 2>/dev/null | grep -q ''; then
            echo -e "  ${BLUE}Partitions:${NC}"
            for partition in "$device"/$dev_name*; do
                if [[ -f "$partition/size" ]]; then
                    local part_name=$(basename "$partition")
                    local part_size=$(cat "$partition/size")
                    part_size=$(echo "scale=2; $part_size * 512 / 1024 / 1024 / 1024" | bc)
                    echo -e "    /dev/${part_name}: ${part_size} GB"
                fi
            done
        fi
    done
}

get_disk_io_stats() {
    echo -e "\n${CYAN}Disk I/O Statistics:${NC}"
    
    # Read /proc/diskstats
    while read -r line; do
        local fields=($line)
        if [[ ${#fields[@]} -ge 11 ]]; then
            local dev_name=${fields[2]}
            
            # Skip minor devices and ramdisks
            if [[ $dev_name == loop* ]] || [[ $dev_name == ram* ]] || [[ $dev_name == *[0-9] ]]; then
                continue
            fi
            
            local read_ios=${fields[3]}
            local read_sectors=${fields[5]}
            local write_ios=${fields[7]}
            local write_sectors=${fields[9]}
            local io_in_progress=${fields[11]}
            
            local read_mb=$(echo "scale=2; $read_sectors * 512 / 1024 / 1024" | bc)
            local write_mb=$(echo "scale=2; $write_sectors * 512 / 1024 / 1024" | bc)
            
            echo -e "  ${dev_name}:"
            echo -e "    Reads: ${read_ios} ops (${read_mb} MB)"
            echo -e "    Writes: ${write_ios} ops (${write_mb} MB)"
            echo -e "    Active I/O: $io_in_progress"
        fi
    done < /proc/diskstats
}

# ============================================
# MEMORY METRICS FUNCTIONS
# ============================================

get_memory_metrics() {
    echo -e "\n${PURPLE}=== MEMORY METRICS ===${NC}"
    
    # Read from /proc/meminfo
    local total_mem=$(grep 'MemTotal:' /proc/meminfo | awk '{print $2}')
    local free_mem=$(grep 'MemFree:' /proc/meminfo | awk '{print $2}')
    local available_mem=$(grep 'MemAvailable:' /proc/meminfo | awk '{print $2}')
    local buffers=$(grep 'Buffers:' /proc/meminfo | awk '{print $2}')
    local cached=$(grep '^Cached:' /proc/meminfo | awk '{print $2}')
    
    # Convert to MB
    total_mem=$((total_mem / 1024))
    free_mem=$((free_mem / 1024))
    available_mem=$((available_mem / 1024))
    buffers=$((buffers / 1024))
    cached=$((cached / 1024))
    
    local used_mem=$((total_mem - free_mem - buffers - cached))
    local usage_percent=$((used_mem * 100 / total_mem))
    
    echo -e "${CYAN}RAM Usage:${NC}"
    echo -e "  Total: ${total_mem} MB"
    echo -e "  Used: ${used_mem} MB (${usage_percent}%)"
    echo -e "  Free: ${free_mem} MB"
    echo -e "  Available: ${available_mem} MB"
    echo -e "  Buffers: ${buffers} MB"
    echo -e "  Cached: ${cached} MB"
    
    # Check swap
    local swap_total=$(grep 'SwapTotal:' /proc/meminfo | awk '{print $2}')
    local swap_free=$(grep 'SwapFree:' /proc/meminfo | awk '{print $2}')
    
    if [[ $swap_total -gt 0 ]]; then
        swap_total=$((swap_total / 1024))
        swap_free=$((swap_free / 1024))
        local swap_used=$((swap_total - swap_free))
        local swap_percent=$((swap_used * 100 / swap_total))
        
        echo -e "\n${CYAN}Swap Usage:${NC}"
        echo -e "  Total: ${swap_total} MB"
        echo -e "  Used: ${swap_used} MB (${swap_percent}%)"
        echo -e "  Free: ${swap_free} MB"
        
        if [[ $swap_percent -gt 80 ]]; then
            echo -e "${RED}⚠ WARNING: High swap usage!${NC}"
        fi
    fi
}

# ============================================
# SYSTEM INFO FUNCTIONS
# ============================================

get_system_info() {
    echo -e "\n${PURPLE}=== SYSTEM INFORMATION ===${NC}"
    
    # Kernel info
    echo -e "${CYAN}Kernel:${NC}"
    echo -e "  Version: $(uname -r)"
    echo -e "  Architecture: $(uname -m)"
    
    # CPU info
    echo -e "\n${CYAN}CPU:${NC}"
    local cpu_model=$(grep 'model name' /proc/cpuinfo | head -1 | cut -d: -f2 | xargs)
    local cpu_cores=$(grep -c '^processor' /proc/cpuinfo)
    local cpu_threads=$(grep 'siblings' /proc/cpuinfo | head -1 | cut -d: -f2 | xargs)
    
    echo -e "  Model: $cpu_model"
    echo -e "  Cores: $cpu_cores"
    echo -e "  Threads per core: $((cpu_threads / cpu_cores))"
    
    # Check CPU vulnerabilities
    if [[ -d "/sys/devices/system/cpu/vulnerabilities" ]]; then
        echo -e "\n${CYAN}CPU Vulnerabilities:${NC}"
        for vuln in /sys/devices/system/cpu/vulnerabilities/*; do
            local vuln_name=$(basename "$vuln")
            local status=$(cat "$vuln")
            echo -e "  ${vuln_name}: ${status}"
        done
    fi
    
    # Uptime
    local uptime_seconds=$(awk '{print $1}' /proc/uptime)
    local uptime_days=$(echo "scale=0; $uptime_seconds / 86400" | bc)
    local uptime_hours=$(echo "scale=0; ($uptime_seconds % 86400) / 3600" | bc)
    local uptime_minutes=$(echo "scale=0; ($uptime_seconds % 3600) / 60" | bc)
    
    echo -e "\n${CYAN}Uptime:${NC}"
    echo -e "  ${uptime_days}d ${uptime_hours}h ${uptime_minutes}m"
    
    # Load average
    local loadavg=$(cat /proc/loadavg)
    echo -e "\n${CYAN}Load Average:${NC}"
    echo -e "  $loadavg"
}

# ============================================
# POWER METRICS (if available)
# ============================================

get_power_metrics() {
    echo -e "\n${PURPLE}=== POWER METRICS ===${NC}"
    
    # Check for ACPI power info
    if [[ -d "/sys/class/power_supply" ]]; then
        echo -e "${CYAN}Power Supplies:${NC}"
        for ps in /sys/class/power_supply/*; do
            local ps_name=$(basename "$ps")
            if [[ -f "$ps/type" ]]; then
                local ps_type=$(cat "$ps/type")
                echo -e "\n  ${ps_name} (${ps_type}):"
                
                # Battery specific
                if [[ $ps_type == "Battery" ]]; then
                    if [[ -f "$ps/capacity" ]]; then
                        local capacity=$(cat "$ps/capacity")
                        echo -e "    Capacity: ${capacity}%"
                    fi
                    if [[ -f "$ps/status" ]]; then
                        local status=$(cat "$ps/status")
                        echo -e "    Status: $status"
                    fi
                fi
                
                # Show available metrics
                for metric in present online voltage_now current_now power_now energy_now; do
                    if [[ -f "$ps/$metric" ]]; then
                        local value=$(cat "$ps/$metric")
                        # Convert if it's a power/energy value
                        if [[ $metric == *power* ]] || [[ $metric == *energy* ]] || [[ $metric == *current* ]] || [[ $metric == *voltage* ]]; then
                            value=$(echo "scale=2; $value / 1000000" | bc)
                            echo -e "    ${metric}: ${value} (scaled)"
                        else
                            echo -e "    ${metric}: ${value}"
                        fi
                    fi
                done
            fi
        done
    else
        echo -e "${YELLOW}No power supply information available${NC}"
    fi
}

# ============================================
# MAIN MONITORING LOOP
# ============================================

monitor_system() {
    local sample_count=0
    
    echo -e "${GREEN}Starting WSL System Monitor${NC}"
    echo -e "Sampling interval: ${INTERVAL}s, Samples: ${SAMPLES}"
    echo -e "Press Ctrl+C to stop\n"
    
    # Initialize CPU usage tracking
    PREV_TOTAL=""
    PREV_IDLE=""
    get_cpu_usage > /dev/null  # First call to set baseline
    
    while [[ $sample_count -lt $SAMPLES ]] || [[ $SAMPLES -eq 0 ]]; do
        clear
        echo -e "${BLUE}=== WSL SYSTEM METRICS === $(date '+%Y-%m-%d %H:%M:%S') ===${NC}"
        echo -e "Sample: $((sample_count + 1))/${SAMPLES:-∞}\n"
        
        # Get CPU metrics
        echo -e "${PURPLE}=== CPU METRICS ===${NC}"
        local cpu_usage=$(get_cpu_usage)
        if [[ -n "$cpu_usage" ]]; then
            echo -e "${CYAN}Overall CPU Usage:${NC} ${GREEN}${cpu_usage}%${NC}"
        fi
        get_per_cpu_usage
        get_cpu_temperature
        
        # Get memory metrics
        get_memory_metrics
        
        # Get disk metrics (first sample only or every 5 samples)
        if [[ $sample_count -eq 0 ]] || [[ $((sample_count % 5)) -eq 0 ]]; then
            get_disk_metrics
            get_disk_io_stats
        else
            echo -e "\n${YELLOW}Disk metrics: Refresh in $((5 - (sample_count % 5))) samples${NC}"
        fi
        
        # Get system info (first sample only)
        if [[ $sample_count -eq 0 ]]; then
            get_system_info
        fi
        
        # Get power metrics (first sample only)
        if [[ $sample_count -eq 0 ]]; then
            get_power_metrics
        fi
        
        # Log if enabled
        if [[ "$ENABLE_LOG" == "true" ]]; then
            echo "$(date '+%Y-%m-%d %H:%M:%S'),CPU,$cpu_usage" >> "$LOG_FILE"
        fi
        
        sample_count=$((sample_count + 1))
        
        if [[ $sample_count -lt $SAMPLES ]] || [[ $SAMPLES -eq 0 ]]; then
            echo -e "\n${CYAN}Next update in ${INTERVAL} seconds...${NC}"
            sleep "$INTERVAL"
        fi
    done
}

# ============================================
# QUICK CHECK MODE
# ============================================

quick_check() {
    echo -e "${GREEN}=== WSL SYSTEM QUICK CHECK ===${NC}"
    echo -e "Timestamp: $(date '+%Y-%m-%d %H:%M:%S')\n"
    
    # Quick CPU check
    echo -e "${CYAN}[CPU]${NC}"
    local cpu_count=$(grep -c '^processor' /proc/cpuinfo)
    echo -e "  Cores: $cpu_count"
    
    # Quick memory check
    echo -e "\n${CYAN}[Memory]${NC}"
    local total_mem=$(grep 'MemTotal:' /proc/meminfo | awk '{print $2}')
    local available_mem=$(grep 'MemAvailable:' /proc/meminfo | awk '{print $2}')
    total_mem=$((total_mem / 1024))
    available_mem=$((available_mem / 1024))
    local used_mem=$((total_mem - available_mem))
    local usage=$((used_mem * 100 / total_mem))
    
    echo -e "  Total: ${total_mem}MB"
    echo -e "  Used: ${used_mem}MB (${usage}%)"
    
    # Quick disk check
    echo -e "\n${CYAN}[Disk]${NC}"
    local block_devices=$(ls /sys/block/ 2>/dev/null | grep -E '^[sv]d|^nvme|^mmc' | head -3)
    for dev in $block_devices; do
        if [[ -f "/sys/block/$dev/size" ]]; then
            local size=$(cat "/sys/block/$dev/size")
            size=$(echo "scale=1; $size * 512 / 1024 / 1024 / 1024" | bc)
            echo -e "  /dev/$dev: ${size}GB"
        fi
    done
    
    # Load average
    echo -e "\n${CYAN}[Load Average]${NC}"
    cat /proc/loadavg
    
    # Uptime
    echo -e "\n${CYAN}[Uptime]${NC}"
    uptime -p
}

# ============================================
# HELP FUNCTION
# ============================================

show_help() {
    echo -e "${GREEN}WSL System Metrics Monitor${NC}"
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  monitor [interval] [samples]   Continuous monitoring mode"
    echo "                                  interval: seconds between updates (default: 1)"
    echo "                                  samples: number of samples (default: 1, 0=infinite)"
    echo "  quick                           Quick system check"
    echo "  cpu                             CPU metrics only"
    echo "  disk                            Disk metrics only"
    echo "  memory                          Memory metrics only"
    echo "  power                           Power metrics only"
    echo "  info                            System information"
    echo "  help                            Show this help"
    echo ""
    echo "Examples:"
    echo "  $0 monitor               # Monitor with default settings"
    echo "  $0 monitor 2 10          # Monitor every 2 seconds, 10 samples"
    echo "  $0 monitor 5 0           # Monitor every 5 seconds, infinite"
    echo "  $0 quick                 # Quick system check"
    echo "  $0 cpu                   # Show CPU metrics"
    echo "  $0 disk                  # Show disk metrics"
}

# ============================================
# MAIN SCRIPT
# ============================================

case "$1" in
    "monitor")
        INTERVAL=${2:-1}
        SAMPLES=${3:-1}
        monitor_system
        ;;
    "quick")
        quick_check
        ;;
    "cpu")
        echo -e "${GREEN}=== CPU METRICS ===${NC}"
        get_cpu_usage > /dev/null
        sleep 1
        usage=$(get_cpu_usage)
        echo -e "Overall CPU Usage: ${GREEN}${usage}%${NC}"
        get_per_cpu_usage
        get_cpu_temperature
        ;;
    "disk")
        get_disk_metrics
        get_disk_io_stats
        ;;
    "memory")
        get_memory_metrics
        ;;
    "power")
        get_power_metrics
        ;;
    "info")
        get_system_info
        ;;
    "help"|"--help"|"-h")
        show_help
        ;;
    *)
        if [[ $# -eq 0 ]]; then
            # Default: quick check
            quick_check
        else
            echo -e "${RED}Unknown option: $1${NC}"
            show_help
            exit 1
        fi
        ;;
esac

echo -e "\n${GREEN}Done!${NC}"
