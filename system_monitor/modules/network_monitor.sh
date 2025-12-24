#!/bin/bash
# ============================================
# NETWORK MONITORING MODULE - Cross-OS Compatible
# ============================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.."; pwd)"
source "$SCRIPT_DIR/utils/platform_detect.sh"
source "$SCRIPT_DIR/utils/parallel_executor.sh"

get_network_status() {
    local os="${DETECTED_OS:-$(detect_os)}"
    
    case "$os" in
        "linux"|"wsl"|"macos")
            if ping -c 1 -W 2 8.8.8.8 &> /dev/null; then
                echo "Connected"
            else
                echo "Disconnected"
            fi
            ;;
        "windows")
            if ping -n 1 -w 2000 8.8.8.8 &> /dev/null; then
                echo "Connected"
            else
                echo "Disconnected"
            fi
            ;;
        *)
            echo "Unknown"
            ;;
    esac
}

get_network_interface() {
    local os="${DETECTED_OS:-$(detect_os)}"
    
    case "$os" in
        "linux"|"wsl")
            ip route 2>/dev/null | grep default | awk '{print $5}' | head -1 || echo "N/A"
            ;;
        "macos")
            route -n get default 2>/dev/null | grep interface | awk '{print $2}' || echo "N/A"
            ;;
        "windows")
            ipconfig 2>/dev/null | grep -A 1 "Ethernet adapter" | grep -v "Ethernet" | head -1 || echo "N/A"
            ;;
        *)
            echo "N/A"
            ;;
    esac
}

get_rx_bytes() {
    local interface=$(get_network_interface)
    if [[ -n "$interface" ]] && [[ -d "/sys/class/net/$interface" ]]; then
        cat /sys/class/net/$interface/statistics/rx_bytes 2>/dev/null || echo "0"
    else
        echo "0"
    fi
}

get_tx_bytes() {
    local interface=$(get_network_interface)
    if [[ -n "$interface" ]] && [[ -d "/sys/class/net/$interface" ]]; then
        cat /sys/class/net/$interface/statistics/tx_bytes 2>/dev/null || echo "0"
    else
        echo "0"
    fi
}

get_network_speed() {
    local interface=$(get_network_interface)
    if [[ -n "$interface" ]] && command -v ethtool &> /dev/null; then
        ethtool "$interface" 2>/dev/null | grep Speed | awk '{print $2}' || echo "N/A"
    else
        echo "N/A"
    fi
}

get_public_ip() {
    curl -s https://api.ipify.org --max-time 2 2>/dev/null || echo "N/A"
}

get_latency() {
    local os="${DETECTED_OS:-$(detect_os)}"
    local gateway
    
    case "$os" in
        "linux"|"wsl")
            gateway=$(ip route 2>/dev/null | grep default | awk '{print $3}' | head -1)
            if [[ -n "$gateway" ]]; then
                ping -c 1 -W 2 "$gateway" 2>/dev/null | grep "time=" | awk -F'time=' '{print $2}' | awk '{print $1}' || echo "N/A"
            else
                echo "N/A"
            fi
            ;;
        "macos")
            gateway=$(route -n get default 2>/dev/null | grep gateway | awk '{print $2}')
            if [[ -n "$gateway" ]]; then
                ping -c 1 -W 2000 "$gateway" 2>/dev/null | grep "time=" | awk -F'time=' '{print $2}' | awk '{print $1}' || echo "N/A"
            else
                echo "N/A"
            fi
            ;;
        *)
            echo "N/A"
            ;;
    esac
}

# Calculate bandwidth (bytes per second)
get_bandwidth() {
    local interface=$(get_network_interface)
    if [[ "$interface" == "N/A" ]] || [[ ! -d "/sys/class/net/$interface" ]]; then
        echo "rx: N/A, tx: N/A"
        return
    fi
    
    local rx1=$(get_rx_bytes)
    local tx1=$(get_tx_bytes)
    sleep 1
    local rx2=$(get_rx_bytes)
    local tx2=$(get_tx_bytes)
    
    local rx_rate=$((rx2 - rx1))
    local tx_rate=$((tx2 - tx1))
    
    # Convert to human-readable format
    local rx_mbps=$(echo "scale=2; $rx_rate / 1024 / 1024" | bc 2>/dev/null || echo "0")
    local tx_mbps=$(echo "scale=2; $tx_rate / 1024 / 1024" | bc 2>/dev/null || echo "0")
    
    echo "rx: ${rx_mbps} MB/s, tx: ${tx_mbps} MB/s"
}

# Check packet loss
check_packet_loss() {
    local target="${1:-8.8.8.8}"
    local count="${2:-10}"
    
    local os="${DETECTED_OS:-$(detect_os)}"
    
    case "$os" in
        "linux"|"wsl"|"macos")
            ping -c "$count" -W 2 "$target" 2>/dev/null | grep "packet loss" | awk '{print $6}' || echo "N/A"
            ;;
        *)
            echo "N/A"
            ;;
    esac
}

export -f get_network_status get_network_interface get_rx_bytes get_tx_bytes
export -f get_network_speed get_public_ip get_latency get_bandwidth check_packet_loss