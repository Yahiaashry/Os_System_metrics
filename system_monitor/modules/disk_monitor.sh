#!/bin/bash
# ============================================
# DISK MONITORING MODULE - Cross-OS Compatible
# ============================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.."; pwd)"
source "$SCRIPT_DIR/utils/platform_detect.sh"
source "$SCRIPT_DIR/utils/parallel_executor.sh"

get_disk_usage() {
    local os="${DETECTED_OS:-$(detect_os)}"
    
    case "$os" in
        "wsl")
            # Get Windows C: drive usage from WSL
            if command -v powershell.exe &>/dev/null; then
                powershell.exe -Command "\$disk = Get-PSDrive C; [math]::Round((\$disk.Used / (\$disk.Used + \$disk.Free)) * 100, 0)" 2>/dev/null || echo "0"
            elif command -v wmic.exe &>/dev/null; then
                wmic.exe logicaldisk where "DeviceID='C:'" get FreeSpace,Size 2>/dev/null | awk 'NR==2 {printf "%.0f", ((\$2-\$1)/\$2)*100}' || echo "0"
            else
                df / 2>/dev/null | awk 'NR==2 {printf "%.0f", (\$3/\$2)*100}' || echo "0"
            fi
            ;;
        "linux"|"macos")
            df / 2>/dev/null | awk 'NR==2 {printf "%.0f", (\$3/\$2)*100}' || echo "0"
            ;;
        "windows")
            # Windows via wmic
            if command -v wmic.exe &>/dev/null; then
                wmic.exe logicaldisk where "DeviceID='C:'" get FreeSpace,Size 2>/dev/null | awk 'NR==2 {printf "%.0f", (($2-$1)/$2)*100}' || echo "0"
            else
                echo "0"
            fi
            ;;
        *)
            echo "0"
            ;;
    esac
}

get_disk_total() {
    local os="${DETECTED_OS:-$(detect_os)}"
    
    case "$os" in
        "wsl")
            # Query Windows C: drive total space
            if command -v powershell.exe &>/dev/null; then
                powershell.exe -Command "\$disk = Get-PSDrive C; [math]::Round((\$disk.Used + \$disk.Free) / 1GB, 0)" 2>/dev/null || echo "0"
            elif command -v wmic.exe &>/dev/null; then
                wmic.exe logicaldisk where "DeviceID='C:'" get Size 2>/dev/null | awk 'NR==2 {printf "%.0f", $1/1073741824}' || echo "0"
            else
                df -BG / | awk 'NR==2 {print $2}' | sed 's/G//'
            fi
            ;;
        *)
            df -BG / | awk 'NR==2 {print $2}' | sed 's/G//'
            ;;
    esac
}

get_disk_used() {
    local os="${DETECTED_OS:-$(detect_os)}"
    
    case "$os" in
        "wsl")
            # Query Windows C: drive used space
            if command -v powershell.exe &>/dev/null; then
                powershell.exe -Command "\$disk = Get-PSDrive C; [math]::Round(\$disk.Used / 1GB, 0)" 2>/dev/null || echo "0"
            elif command -v wmic.exe &>/dev/null; then
                wmic.exe logicaldisk where "DeviceID='C:'" get FreeSpace,Size 2>/dev/null | awk 'NR==2 {printf "%.0f", ($2-$1)/1073741824}' || echo "0"
            else
                df -BG / | awk 'NR==2 {print $3}' | sed 's/G//'
            fi
            ;;
        *)
            df -BG / | awk 'NR==2 {print $3}' | sed 's/G//'
            ;;
    esac
}

get_disk_free() {
    local os="${DETECTED_OS:-$(detect_os)}"
    
    case "$os" in
        "wsl")
            # Query Windows C: drive free space
            if command -v powershell.exe &>/dev/null; then
                powershell.exe -Command "\$disk = Get-PSDrive C; [math]::Round(\$disk.Free / 1GB, 0)" 2>/dev/null || echo "0"
            elif command -v wmic.exe &>/dev/null; then
                wmic.exe logicaldisk where "DeviceID='C:'" get FreeSpace 2>/dev/null | awk 'NR==2 {printf "%.0f", $1/1073741824}' || echo "0"
            else
                df -BG / | awk 'NR==2 {print $4}' | sed 's/G//'
            fi
            ;;
        *)
            df -BG / | awk 'NR==2 {print $4}' | sed 's/G//'
            ;;
    esac
}

get_smart_status() {
    local os="${DETECTED_OS:-$(detect_os)}"
    
    case "$os" in
        "wsl")
            # Query Windows physical disk health
            if command -v powershell.exe &>/dev/null; then
                local health=$(powershell.exe -Command "(Get-PhysicalDisk | Select-Object -First 1).HealthStatus" 2>/dev/null | tr -d '\r')
                if [[ -n "$health" ]] && [[ "$health" != "" ]]; then
                    echo "$health"
                else
                    echo "N/A"
                fi
            else
                echo "N/A"
            fi
            ;;
        *)
            # Try smartctl on various device paths
            if command -v smartctl &> /dev/null; then
                for dev in /dev/sda /dev/nvme0n1 /dev/hda; do
                    if [[ -b "$dev" ]]; then
                        local smart_result=$(sudo smartctl -H "$dev" 2>/dev/null | grep "SMART overall-health" | awk -F': ' '{print $2}')
                        if [[ -n "$smart_result" ]]; then
                            echo "$smart_result"
                            return
                        fi
                    fi
                done
                echo "Unknown"
            else
                echo "N/A"
            fi
            ;;
    esac
}

get_all_partitions() {
    df -h | awk 'NR>1 {print $1" "$6" "$5" "$3"/"$2}'
}

get_disk_io() {
    if [[ -f /proc/diskstats ]]; then
        iostat -d 1 1 2>/dev/null | tail -n +4 || echo "iostat not available"
    else
        echo "No disk stats"
    fi
}

get_inode_usage() {
    df -i / | awk 'NR==2 {printf "%.1f", ($3/$2)*100}'
}

check_disk_alerts() {
    local usage=$(get_disk_usage)
    
    if (( $(echo "$usage > ${DISK_ALERT_THRESHOLD:-90}" | bc -l 2>/dev/null) )); then
        send_alert "Disk usage is high: ${usage}% (threshold: ${DISK_ALERT_THRESHOLD:-90}%)" "WARNING"
    fi
    
    local smart_status=$(get_smart_status)
    if [[ "$smart_status" == "FAILED" ]]; then
        send_alert "SMART status indicates disk failure!" "CRITICAL"
    fi
    
    local inode_usage=$(get_inode_usage)
    if (( $(echo "$inode_usage > 90" | bc -l 2>/dev/null) )); then
        send_alert "Inode usage is high: ${inode_usage}%" "WARNING"
    fi
}

export -f get_disk_usage get_disk_total get_disk_used get_disk_free get_smart_status get_all_partitions get_disk_io get_inode_usage check_disk_alerts