#!/bin/bash
# ============================================
# MEMORY MONITORING MODULE - Cross-OS Compatible
# ============================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCRIPT_DIR/utils/platform_detect.sh"
source "$SCRIPT_DIR/utils/parallel_executor.sh"

get_memory_usage() {
    local os="${DETECTED_OS:-$(detect_os)}"
    
    case "$os" in
        "wsl")
            _get_memory_usage_windows_host
            ;;
        "linux")
            _get_memory_usage_linux
            ;;
        "macos")
            _get_memory_usage_macos
            ;;
        "windows")
            _get_memory_usage_windows
            ;;
        *)
            echo "0.0"
            ;;
    esac
}

_get_memory_usage_linux() {
    if command -v free &>/dev/null; then
        free | awk '/Mem:/ {printf "%.1f", ($2-$7)/$2 * 100}'
    else
        # Parse /proc/meminfo
        local total=$(grep MemTotal /proc/meminfo | awk '{print $2}')
        local available=$(grep MemAvailable /proc/meminfo | awk '{print $2}')
        local used=$((total - available))
        echo "scale=1; $used * 100 / $total" | bc
    fi
}

_get_memory_usage_macos() {
    # macOS memory calculation is more complex
    if command -v vm_stat &>/dev/null; then
        local page_size=$(pagesize 2>/dev/null || echo 4096)
        local vm_stats=$(vm_stat)
        
        local free_pages=$(echo "$vm_stats" | grep "Pages free" | awk '{print $3}' | tr -d '.')
        local active_pages=$(echo "$vm_stats" | grep "Pages active" | awk '{print $3}' | tr -d '.')
        local inactive_pages=$(echo "$vm_stats" | grep "Pages inactive" | awk '{print $3}' | tr -d '.')
        local wired_pages=$(echo "$vm_stats" | grep "Pages wired down" | awk '{print $4}' | tr -d '.')
        
        local used_mem=$(( (active_pages + inactive_pages + wired_pages) * page_size / 1024 / 1024 ))
        local total_mem=$(sysctl -n hw.memsize | awk '{print $1/1024/1024}')
        
        echo "scale=1; $used_mem * 100 / $total_mem" | bc
    else
        echo "0.0"
    fi
}

_get_memory_usage_windows() {
    if command -v wmic.exe &>/dev/null; then
        local total=$(wmic.exe OS get TotalVisibleMemorySize 2>/dev/null | grep -o '[0-9]*' | head -1)
        local free=$(wmic.exe OS get FreePhysicalMemory 2>/dev/null | grep -o '[0-9]*' | head -1)
        
        if [[ -n "$total" ]] && [[ -n "$free" ]] && [[ "$total" -gt 0 ]]; then
            local used=$((total - free))
            echo "scale=1; $used * 100 / $total" | bc
        else
            echo "0.0"
        fi
    else
        echo "0.0"
    fi
}

_get_memory_usage_windows_host() {
    # Query Windows host memory from WSL using PowerShell
    if command -v powershell.exe &>/dev/null; then
        powershell.exe -Command "\$mem = Get-CimInstance Win32_OperatingSystem; [math]::Round((\$mem.TotalVisibleMemorySize - \$mem.FreePhysicalMemory) / \$mem.TotalVisibleMemorySize * 100, 1)" 2>/dev/null || echo "0.0"
    elif command -v wmic.exe &>/dev/null; then
        local total=$(wmic.exe OS get TotalVisibleMemorySize 2>/dev/null | grep -o '[0-9]*' | head -1)
        local free=$(wmic.exe OS get FreePhysicalMemory 2>/dev/null | grep -o '[0-9]*' | head -1)
        if [[ -n "$total" ]] && [[ -n "$free" ]] && [[ "$total" -gt 0 ]]; then
            echo "scale=1; ($total - $free) * 100 / $total" | bc
        else
            echo "0.0"
        fi
    else
        echo "0.0"
    fi
}

get_total_memory() {
    local os="${DETECTED_OS:-$(detect_os)}"
    
    case "$os" in
        "wsl")
            # Query Windows host memory from WSL
            if command -v powershell.exe &>/dev/null; then
                powershell.exe -Command "(Get-CimInstance Win32_OperatingSystem).TotalVisibleMemorySize / 1024" 2>/dev/null | grep -o '[0-9]*' | head -1 || echo "0"
            elif command -v wmic.exe &>/dev/null; then
                wmic.exe OS get TotalVisibleMemorySize 2>/dev/null | grep -o '[0-9]*' | head -1 | awk '{printf "%.0f", $1/1024}'
            else
                # Fallback to WSL memory if Windows query fails
                free -m 2>/dev/null | awk '/Mem:/ {print $2}' || echo "0"
            fi
            ;;
        "linux")
            if command -v free &>/dev/null; then
                free -m | awk '/Mem:/ {print $2}'
            else
                grep MemTotal /proc/meminfo | awk '{printf "%.0f", $2/1024}'
            fi
            ;;
        "macos")
            sysctl -n hw.memsize | awk '{printf "%.0f", $1/1024/1024}'
            ;;
        "windows")
            wmic.exe OS get TotalVisibleMemorySize 2>/dev/null | grep -o '[0-9]*' | head -1 | awk '{printf "%.0f", $1/1024}'
            ;;
        *)
            echo "0"
            ;;
    esac
}

get_used_memory() {
    local os="${DETECTED_OS:-$(detect_os)}"
    
    case "$os" in
        "wsl")
            # Query Windows host memory from WSL
            if command -v powershell.exe &>/dev/null; then
                powershell.exe -Command "\$mem = Get-CimInstance Win32_OperatingSystem; (\$mem.TotalVisibleMemorySize - \$mem.FreePhysicalMemory) / 1024" 2>/dev/null | grep -o '[0-9]*' | head -1 || echo "0"
            elif command -v wmic.exe &>/dev/null; then
                local total=$(wmic.exe OS get TotalVisibleMemorySize 2>/dev/null | grep -o '[0-9]*' | head -1)
                local free=$(wmic.exe OS get FreePhysicalMemory 2>/dev/null | grep -o '[0-9]*' | head -1)
                echo "scale=0; ($total - $free) / 1024" | bc
            else
                # Fallback to WSL memory if Windows query fails
                free -m 2>/dev/null | awk '/Mem:/ {print $2-$7}' || echo "0"
            fi
            ;;
        "linux")
            if command -v free &>/dev/null; then
                # Modern free: total - available = used
                free -m | awk '/Mem:/ {print $2-$7}'
            else
                local total=$(grep MemTotal /proc/meminfo | awk '{print $2}')
                local available=$(grep MemAvailable /proc/meminfo | awk '{print $2}')
                echo "scale=0; ($total - $available) / 1024" | bc
            fi
            ;;
        "macos")
            local page_size=$(pagesize 2>/dev/null || echo 4096)
            local vm_stats=$(vm_stat)
            local active_pages=$(echo "$vm_stats" | grep "Pages active" | awk '{print $3}' | tr -d '.')
            local wired_pages=$(echo "$vm_stats" | grep "Pages wired down" | awk '{print $4}' | tr -d '.')
            echo "scale=0; ($active_pages + $wired_pages) * $page_size / 1024 / 1024" | bc
            ;;
        "windows")
            local total=$(wmic.exe OS get TotalVisibleMemorySize 2>/dev/null | grep -o '[0-9]*' | head -1)
            local free=$(wmic.exe OS get FreePhysicalMemory 2>/dev/null | grep -o '[0-9]*' | head -1)
            echo "scale=0; ($total - $free) / 1024" | bc
            ;;
        *)
            echo "0"
            ;;
    esac
}

get_free_memory() {
    local os="${DETECTED_OS:-$(detect_os)}"
    
    case "$os" in
        "wsl")
            # Query Windows host memory from WSL
            if command -v powershell.exe &>/dev/null; then
                powershell.exe -Command "(Get-CimInstance Win32_OperatingSystem).FreePhysicalMemory / 1024" 2>/dev/null | grep -o '[0-9]*' | head -1 || echo "0"
            elif command -v wmic.exe &>/dev/null; then
                wmic.exe OS get FreePhysicalMemory 2>/dev/null | grep -o '[0-9]*' | head -1 | awk '{printf "%.0f", $1/1024}'
            else
                # Fallback to WSL memory if Windows query fails
                free -m 2>/dev/null | awk '/Mem:/ {print $7}' || echo "0"
            fi
            ;;
        "linux")
            if command -v free &>/dev/null; then
                # Modern free: $7 is available memory (better than $4 which is just free)
                free -m | awk '/Mem:/ {print $7}'
            else
                grep MemAvailable /proc/meminfo | awk '{printf "%.0f", $2/1024}'
            fi
            ;;
        "macos")
            local page_size=$(pagesize 2>/dev/null || echo 4096)
            local free_pages=$(vm_stat | grep "Pages free" | awk '{print $3}' | tr -d '.')
            echo "scale=0; $free_pages * $page_size / 1024 / 1024" | bc
            ;;
        "windows")
            wmic.exe OS get FreePhysicalMemory 2>/dev/null | grep -o '[0-9]*' | head -1 | awk '{printf "%.0f", $1/1024}'
            ;;
        *)
            echo "0"
            ;;
    esac
}

get_swap_usage() {
    local os="${DETECTED_OS:-$(detect_os)}"
    
    case "$os" in
        "linux"|"wsl")
            if command -v free &>/dev/null; then
                free | awk '/Swap:/ {if ($2 == 0) print "0"; else printf "%.1f", $3/$2 * 100}'
            else
                local swap_total=$(grep SwapTotal /proc/meminfo | awk '{print $2}')
                local swap_free=$(grep SwapFree /proc/meminfo | awk '{print $2}')
                
                if [[ "$swap_total" -eq 0 ]]; then
                    echo "0"
                else
                    local swap_used=$((swap_total - swap_free))
                    echo "scale=1; $swap_used * 100 / $swap_total" | bc
                fi
            fi
            ;;
        "macos")
            # macOS swap info
            sysctl vm.swapusage 2>/dev/null | awk -F'[= ]' '{
                total=$4; used=$7;
                gsub(/M/, "", total); gsub(/M/, "", used);
                if (total > 0) printf "%.1f", (used/total)*100; else print "0"
            }' || echo "0"
            ;;
        *)
            echo "0"
            ;;
    esac
}

get_buffer_cache() {
    local os="${DETECTED_OS:-$(detect_os)}"
    
    case "$os" in
        "linux"|"wsl")
            if command -v free &>/dev/null; then
                free -h | awk '/Mem:/ {print "Used: "$3", Free: "$4", Buff/Cache: "$6}'
            else
                local buffers=$(grep Buffers /proc/meminfo | awk '{printf "%.0fM", $2/1024}')
                local cached=$(grep "^Cached" /proc/meminfo | awk '{printf "%.0fM", $2/1024}')
                echo "Buffers: $buffers, Cached: $cached"
            fi
            ;;
        *)
            echo "N/A"
            ;;
    esac
}

# Detailed memory breakdown
get_memory_details() {
    local os="${DETECTED_OS:-$(detect_os)}"
    
    case "$os" in
        "linux"|"wsl")
            if [[ -f /proc/meminfo ]]; then
                echo "=== Memory Details ==="
                grep -E "MemTotal|MemFree|MemAvailable|Buffers|Cached|SwapTotal|SwapFree|Shmem" /proc/meminfo
            fi
            ;;
        "macos")
            echo "=== Memory Details ==="
            vm_stat
            ;;
        *)
            echo "Detailed memory info not available"
            ;;
    esac
}

# Detect potential memory leaks (simplified)
detect_memory_leak() {
    local threshold=95
    local consecutive_high=0
    local max_consecutive=5
    
    for ((i=0; i<$max_consecutive; i++)); do
        local usage=$(get_memory_usage | cut -d. -f1)
        
        if [[ "$usage" -ge "$threshold" ]]; then
            ((consecutive_high++))
        else
            consecutive_high=0
        fi
        
        sleep 2
    done
    
    if [[ $consecutive_high -ge $max_consecutive ]]; then
        echo "POTENTIAL MEMORY LEAK: Memory usage consistently above ${threshold}%"
        return 1
    fi
    
    echo "No memory leak detected"
    return 0
}

check_memory_alerts() {
    local usage=$(get_memory_usage)
    
    if (( $(echo "$usage > ${MEMORY_ALERT_THRESHOLD:-85}" | bc -l 2>/dev/null) )); then
        send_alert "Memory usage is high: ${usage}% (threshold: ${MEMORY_ALERT_THRESHOLD:-85}%)" "WARNING"
    fi
    
    local swap_usage=$(get_swap_usage)
    if (( $(echo "$swap_usage > 80" | bc -l 2>/dev/null) )); then
        send_alert "Swap usage is high: ${swap_usage}%" "WARNING"
    fi
}

export -f get_memory_usage get_total_memory get_used_memory get_free_memory 
export -f get_swap_usage get_buffer_cache get_memory_details detect_memory_leak
export -f check_memory_alerts
export -f _get_memory_usage_linux _get_memory_usage_macos _get_memory_usage_windows