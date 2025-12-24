#!/bin/bash
# ============================================
# CPU MONITORING MODULE - Cross-OS Compatible
# ============================================

# Source platform detection
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCRIPT_DIR/utils/platform_detect.sh"
source "$SCRIPT_DIR/utils/parallel_executor.sh"

# Associative array for multi-core data
declare -gA CPU_CORE_USAGE

get_cpu_model() {
    local os="${DETECTED_OS:-$(detect_os)}"
    
    case "$os" in
        "wsl")
            # Query Windows CPU model from WSL
            if command -v powershell.exe &>/dev/null; then
                powershell.exe -Command "(Get-CimInstance Win32_Processor).Name" 2>/dev/null | tr -d '\r' | head -1 || echo "Unknown CPU"
            elif command -v wmic.exe &>/dev/null; then
                wmic.exe cpu get name 2>/dev/null | grep -v "Name" | grep -v "^$" | head -1 | sed 's/^[ \t]*//;s/[ \t]*$//' || echo "Unknown CPU"
            else
                grep -m1 "model name" /proc/cpuinfo 2>/dev/null | cut -d: -f2 | sed 's/^[ \t]*//' || echo "Unknown CPU"
            fi
            ;;
        "linux")
            grep -m1 "model name" /proc/cpuinfo 2>/dev/null | cut -d: -f2 | sed 's/^[ \t]*//' || echo "Unknown CPU"
            ;;
        "macos")
            sysctl -n machdep.cpu.brand_string 2>/dev/null || echo "Unknown CPU"
            ;;
        "windows")
            if command -v wmic.exe &>/dev/null; then
                wmic.exe cpu get name 2>/dev/null | grep -v "Name" | grep -v "^$" | head -1 | sed 's/^[ \t]*//;s/[ \t]*$//' || echo "Unknown CPU"
            else
                echo "Unknown CPU"
            fi
            ;;
        *)
            echo "Unknown CPU"
            ;;
    esac
}

get_cpu_usage() {
    local os="${DETECTED_OS:-$(detect_os)}"
    local cpu_usage="0.0"
    
    case "$os" in
        "wsl")
            # Get Windows host metrics from WSL
            cpu_usage=$(_get_cpu_usage_windows_host)
            ;;
        "linux")
            # Use cached result if available
            if [[ "${ENABLE_CACHE:-true}" == "true" ]]; then
                cpu_usage=$(get_cached_metric "cpu_usage" _get_cpu_usage_linux)
            else
                cpu_usage=$(_get_cpu_usage_linux)
            fi
            ;;
        "macos")
            cpu_usage=$(_get_cpu_usage_macos)
            ;;
        "windows")
            cpu_usage=$(_get_cpu_usage_windows)
            ;;
        *)
            cpu_usage="0.0"
            ;;
    esac
    
    echo "$cpu_usage"
}

_get_cpu_usage_linux() {
    local cpu_usage="0.0"
    
    # Use /proc/stat (more reliable than top parsing)
    local stats1=$(grep 'cpu ' /proc/stat | awk '{print $2" "$3" "$4" "$5" "$6" "$7" "$8}')
    sleep 0.5
    local stats2=$(grep 'cpu ' /proc/stat | awk '{print $2" "$3" "$4" "$5" "$6" "$7" "$8}')
    
    local idle1=$(echo $stats1 | awk '{print $4}')
    local idle2=$(echo $stats2 | awk '{print $4}')
    
    local total1=0
    local total2=0
    
    for i in {1..7}; do
        total1=$((total1 + $(echo $stats1 | awk -v i=$i '{print $i}')))
        total2=$((total2 + $(echo $stats2 | awk -v i=$i '{print $i}')))
    done
    
    local total_diff=$((total2 - total1))
    local idle_diff=$((idle2 - idle1))
    
    if [[ $total_diff -gt 0 ]]; then
        cpu_usage=$(echo "scale=1; 100 * ($total_diff - $idle_diff) / $total_diff" | bc 2>/dev/null || echo "0.0")
    fi
    
    echo "${cpu_usage:-0.0}"
}

_get_cpu_usage_macos() {
    if command -v top &>/dev/null; then
        top -l 1 | grep "CPU usage" | awk '{print $3}' | sed 's/%//' || echo "0.0"
    else
        echo "0.0"
    fi
}

_get_cpu_usage_windows() {
    # Windows via wmic (works in Git Bash/WSL with wmic.exe)
    if command -v wmic.exe &>/dev/null; then
        wmic.exe cpu get loadpercentage 2>/dev/null | grep -o '[0-9]*' | head -1 || echo "0"
    else
        echo "0.0"
    fi
}

_get_cpu_usage_windows_host() {
    # Query Windows host CPU from WSL using PowerShell
    if command -v powershell.exe &>/dev/null; then
        powershell.exe -Command "Get-Counter '\\Processor(_Total)\\% Processor Time' | Select-Object -ExpandProperty CounterSamples | Select-Object -ExpandProperty CookedValue" 2>/dev/null | awk '{printf "%.1f", $1}' || echo "0.0"
    elif command -v wmic.exe &>/dev/null; then
        wmic.exe cpu get loadpercentage 2>/dev/null | grep -o '[0-9]*' | head -1 || echo "0"
    else
        echo "0.0"
    fi
}

get_cpu_temp() {
    local os="${DETECTED_OS:-$(detect_os)}"
    local temp="N/A"
    
    case "$os" in
        "linux"|"wsl")
            temp=$(_get_cpu_temp_linux)
            ;;
        "macos")
            temp=$(_get_cpu_temp_macos)
            ;;
        "windows")
            temp="N/A"  # Requires admin privileges and WMI
            ;;
        *)
            temp="N/A"
            ;;
    esac
    
    echo "$temp"
}

_get_cpu_temp_linux() {
    local temp="N/A"
    local os="${DETECTED_OS:-$(detect_os)}"
    
    # WSL: Use Windows thermal info first (most reliable for WSL)
    if [[ "$os" == "wsl" ]] && command -v powershell.exe &>/dev/null; then
        # Method 1: Try Win32_PerfRawData_Counters_ThermalZoneInformation
        local ps_temp=$(powershell.exe -Command "\$zones = Get-WmiObject Win32_PerfRawData_Counters_ThermalZoneInformation -ErrorAction SilentlyContinue 2>\$null; if (\$zones) { \$maxTemp = (\$zones | ForEach-Object { if (\$_.HighPrecisionTemperature -gt 0) { \$_.HighPrecisionTemperature / 10 } elseif (\$_.Temperature -gt 0) { \$_.Temperature } else { 0 } } | Measure-Object -Maximum).Maximum; if (\$maxTemp -gt 0) { [math]::Round(\$maxTemp - 273.15, 1) } else { 'N/A' } } else { 'N/A' }" 2>/dev/null | tr -d '\r\n' | grep -o '^[0-9]\+\.[0-9]\+$')
        
        if [[ -n "$ps_temp" ]] && [[ "$ps_temp" =~ ^[0-9]+\.?[0-9]*$ ]]; then
            echo "${ps_temp}"
            return
        fi
        
        # Method 2: Try MSAcpi_ThermalZoneTemperature
        ps_temp=$(powershell.exe -Command "\$data = Get-CimInstance -Namespace root/wmi -ClassName MSAcpi_ThermalZoneTemperature -ErrorAction SilentlyContinue 2>\$null; if (\$data) { \$maxTemp = (\$data | ForEach-Object { [math]::Round(\$_.CurrentTemperature / 10 - 273.15, 1) } | Measure-Object -Maximum).Maximum; if (\$maxTemp -gt 0) { \$maxTemp } else { 'N/A' } } else { 'N/A' }" 2>/dev/null | tr -d '\r\n' | grep -o '^[0-9]\+\.[0-9]\+$')
        
        if [[ -n "$ps_temp" ]] && [[ "$ps_temp" =~ ^[0-9]+\.?[0-9]*$ ]]; then
            echo "${ps_temp}"
            return
        fi
    fi
    
    # Try thermal zone (native Linux)
    if [[ -d "/sys/class/thermal" ]]; then
        for zone in /sys/class/thermal/thermal_zone*; do
            if [[ -f "$zone/temp" ]]; then
                local raw_temp=$(cat "$zone/temp" 2>/dev/null)
                local zone_type=$(cat "$zone/type" 2>/dev/null)
                
                if [[ "$raw_temp" =~ ^[0-9]+$ ]] && [[ "$raw_temp" -gt 1000 ]]; then
                    local temp_c=$(echo "scale=1; $raw_temp / 1000" | bc 2>/dev/null)
                    
                    # Prefer CPU temperature sources
                    if [[ "$zone_type" == *"cpu"* ]] || [[ "$zone_type" == *"Core"* ]] || [[ "$zone_type" == *"x86"* ]] || [[ "$zone_type" == *"pkg"* ]]; then
                        echo "${temp_c}"
                        return
                    fi
                fi
            fi
        done
    fi
    
    # Try sensors command (requires lm-sensors package)
    if command -v sensors &> /dev/null; then
        local sensors_output=$(sensors 2>/dev/null | grep -E "Core|Package|Tdie|CPU" | grep -E "°C" | head -1)
        if [[ -n "$sensors_output" ]]; then
            temp=$(echo "$sensors_output" | sed -n 's/.*+\([0-9]\+\.[0-9]\)°C.*/\1/p')
            if [[ -n "$temp" ]] && [[ "$temp" =~ ^[0-9]+\.?[0-9]*$ ]]; then
                echo "${temp}"
                return
            fi
        fi
    fi
    
    echo "N/A"
}

_get_cpu_temp_macos() {
    # Requires osx-cpu-temp or istats
    if command -v osx-cpu-temp &>/dev/null; then
        osx-cpu-temp 2>/dev/null | grep -o '[0-9.]*°C' || echo "N/A"
    elif command -v istats &>/dev/null; then
        istats cpu temp --value-only 2>/dev/null | awk '{printf "%.1f°C", $1}' || echo "N/A"
    else
        echo "N/A"
    fi
}

get_cpu_freq() {
    local os="${DETECTED_OS:-$(detect_os)}"
    
    case "$os" in
        "linux"|"wsl")
            # Try cpufreq interface (native Linux)
            if [[ -f /sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq ]]; then
                cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq 2>/dev/null | awk '{printf "%.0f", $1/1000}' || echo "N/A"
            # Try /proc/cpuinfo first (most reliable in WSL)
            elif [[ -f /proc/cpuinfo ]]; then
                local freq=$(grep -i "cpu MHz" /proc/cpuinfo 2>/dev/null | head -1 | awk -F: '{printf "%.0f", $2}')
                if [[ -n "$freq" ]] && [[ "$freq" != "0" ]]; then
                    echo "$freq"
                else
                    echo "N/A"
                fi
            # Try lscpu with multiple grep patterns
            elif command -v lscpu &> /dev/null; then
                local freq=$(lscpu 2>/dev/null | grep -i "CPU MHz" | head -1 | awk '{printf "%.0f", $NF}')
                if [[ -n "$freq" ]] && [[ "$freq" != "0" ]]; then
                    echo "$freq"
                else
                    # Try CPU max MHz as fallback
                    lscpu 2>/dev/null | grep -i "CPU max MHz" | head -1 | awk '{printf "%.0f", $NF}' || echo "N/A"
                fi
            else
                echo "N/A"
            fi
            ;;
        "macos")
            sysctl -n hw.cpufrequency 2>/dev/null | awk '{printf "%.0f", $1/1000000}' || echo "N/A"
            ;;
        *)
            echo "N/A"
            ;;
    esac
}

get_cpu_cores() {
    local os="${DETECTED_OS:-$(detect_os)}"
    
    case "$os" in
        "linux"|"wsl")
            nproc 2>/dev/null || grep -c "^processor" /proc/cpuinfo 2>/dev/null || echo "1"
            ;;
        "macos")
            sysctl -n hw.ncpu 2>/dev/null || echo "1"
            ;;
        "windows")
            echo "${NUMBER_OF_PROCESSORS:-1}"
            ;;
        *)
            echo "1"
            ;;
    esac
}

get_cpu_load_per_core() {
    local os="${DETECTED_OS:-$(detect_os)}"
    
    if [[ "$os" == "linux" || "$os" == "wsl" ]]; then
        if command -v mpstat &> /dev/null; then
            mpstat -P ALL 1 1 2>/dev/null | awk '/Average:/ && $2 ~ /[0-9]+/ {printf "Core %s: %.1f%%\n", $2, 100 - $NF}'
        else
            # Fallback: parse /proc/stat for per-core data
            local core_count=$(get_cpu_cores)
            for ((i=0; i<core_count; i++)); do
                echo "Core $i: N/A"
            done
        fi
    else
        echo "Per-core stats not available on $os"
    fi
}

# Get CPU model/info
get_cpu_model() {
    local os="${DETECTED_OS:-$(detect_os)}"
    
    case "$os" in
        "linux"|"wsl")
            grep "model name" /proc/cpuinfo 2>/dev/null | head -1 | cut -d':' -f2 | xargs || echo "Unknown"
            ;;
        "macos")
            sysctl -n machdep.cpu.brand_string 2>/dev/null || echo "Unknown"
            ;;
        "windows")
            wmic.exe cpu get name 2>/dev/null | grep -v Name | xargs || echo "Unknown"
            ;;
        *)
            echo "Unknown"
            ;;
    esac
}

# Get load average
get_load_average() {
    local os="${DETECTED_OS:-$(detect_os)}"
    
    case "$os" in
        "linux"|"wsl"|"macos")
            if command -v uptime &>/dev/null; then
                uptime | grep -o 'load average:.*' | cut -d':' -f2 | xargs || echo "N/A"
            elif [[ -f /proc/loadavg ]]; then
                cut -d' ' -f1-3 /proc/loadavg 2>/dev/null || echo "N/A"
            else
                echo "N/A"
            fi
            ;;
        *)
            echo "N/A"
            ;;
    esac
}

# Check for thermal throttling
check_thermal_throttling() {
    local os="${DETECTED_OS:-$(detect_os)}"
    
    if [[ "$os" == "linux" || "$os" == "wsl" ]]; then
        if [[ -f /sys/devices/system/cpu/cpu0/thermal_throttle/core_throttle_count ]]; then
            local throttle_count=$(cat /sys/devices/system/cpu/cpu0/thermal_throttle/core_throttle_count 2>/dev/null)
            if [[ "$throttle_count" -gt 0 ]]; then
                echo "WARNING: Thermal throttling detected ($throttle_count events)"
                return 1
            fi
        fi
    fi
    
    echo "No throttling detected"
    return 0
}

check_cpu_alerts() {
    local usage=$(get_cpu_usage)
    local temp_str=$(get_cpu_temp)
    local temp=$(echo "$temp_str" | sed 's/°C//')
    
    if [[ -n "$usage" ]] && [[ "$usage" != "N/A" ]]; then
        if (( $(echo "$usage > ${CPU_ALERT_THRESHOLD:-90}" | bc -l 2>/dev/null) )); then
            send_alert "CPU usage is high: ${usage}% (threshold: ${CPU_ALERT_THRESHOLD:-90}%)" "WARNING"
        fi
    fi
    
    if [[ "$temp" != "N/A" ]] && [[ -n "$temp" ]] && [[ "$temp" =~ ^[0-9.]+$ ]]; then
        if (( $(echo "$temp > ${TEMP_ALERT_THRESHOLD:-80}" | bc -l 2>/dev/null) )); then
            send_alert "CPU temperature is high: ${temp}°C (threshold: ${TEMP_ALERT_THRESHOLD:-80}°C)" "CRITICAL"
        fi
    fi
    
    # Check thermal throttling
    check_thermal_throttling >/dev/null || send_alert "CPU thermal throttling detected" "WARNING"
}

export -f get_cpu_usage get_cpu_temp get_cpu_freq get_cpu_cores 
export -f get_cpu_load_per_core get_cpu_model get_load_average
export -f check_thermal_throttling check_cpu_alerts
export -f _get_cpu_usage_linux _get_cpu_usage_macos _get_cpu_usage_windows
export -f _get_cpu_temp_linux _get_cpu_temp_macos