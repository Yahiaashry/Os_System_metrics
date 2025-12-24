#!/bin/bash

# ============================================
# WSL Simple Network Statistics - FIXED VERSION
# Shows output similar to: send/receive rates, adapter info, IP addresses
# Reads from /proc and /sys folders only
# ============================================

# Colors
GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# ============================================
# GET ACTIVE INTERFACE (WSL-specific)
# ============================================

get_wsl_interface() {
    # WSL typically uses eth0 for networking
    local interface=""
    
    # Try to find the active interface
    for iface in $(ls /sys/class/net/ 2>/dev/null | grep -v lo); do
        local operstate=$(cat /sys/class/net/$iface/operstate 2>/dev/null)
        if [[ "$operstate" == "up" ]]; then
            interface="$iface"
            break
        fi
    done
    
    # Fallback to first non-loopback interface
    if [[ -z "$interface" ]]; then
        interface=$(ls /sys/class/net/ 2>/dev/null | grep -v lo | head -1)
    fi
    
    [[ -z "$interface" ]] && echo "lo" || echo "$interface"
}

# ============================================
# GET CURRENT BYTE COUNTS
# ============================================

get_current_bytes() {
    local interface=$1
    local stats_line=$(grep "^\s*$interface:" /proc/net/dev 2>/dev/null)
    
    if [[ -z "$stats_line" ]]; then
        echo "0,0"
        return
    fi
    
    local stats=($stats_line)
    echo "${stats[1]},${stats[9]}"  # rx_bytes,tx_bytes
}

# ============================================
# CALCULATE NETWORK SPEEDS
# ============================================

calculate_speeds() {
    local interface=$1
    local interval=$2
    
    # Get first measurement
    local bytes1=$(get_current_bytes "$interface")
    local rx1=$(echo "$bytes1" | cut -d',' -f1)
    local tx1=$(echo "$bytes1" | cut -d',' -f2)
    
    # Wait for interval
    sleep "$interval"
    
    # Get second measurement
    local bytes2=$(get_current_bytes "$interface")
    local rx2=$(echo "$bytes2" | cut -d',' -f1)
    local tx2=$(echo "$bytes2" | cut -d',' -f2)
    
    # Calculate rates (bytes per second)
    local rx_rate=$(( (rx2 - rx1) / interval ))
    local tx_rate=$(( (tx2 - tx1) / interval ))
    
    # Convert to Kbps (1 byte/sec = 0.008 Kbps)
    local rx_kbps=$(echo "scale=1; $rx_rate * 0.008" | bc 2>/dev/null || echo "0")
    local tx_kbps=$(echo "scale=1; $tx_rate * 0.008" | bc 2>/dev/null || echo "0")
    
    # Ensure non-negative
    rx_kbps=$(echo "$rx_kbps" | awk '{if ($1 < 0) print "0.0"; else print $1}')
    tx_kbps=$(echo "$tx_kbps" | awk '{if ($1 < 0) print "0.0"; else print $1}')
    
    echo "$tx_kbps,$rx_kbps"
}

# ============================================
# GET ADAPTER NAME (WSL-specific)
# ============================================

get_adapter_name() {
    local interface=$1
    
    # Check if it's the WSL virtual interface
    if [[ "$interface" == "eth0" ]] || [[ -f "/sys/class/net/$interface/device/driver" ]]; then
        local driver_path=$(readlink -f /sys/class/net/$interface/device/driver 2>/dev/null)
        local driver=$(basename "$driver_path" 2>/dev/null)
        
        case "$driver" in
            "hv_netvsc")
                echo "vEthernet (WSL Hyper-V)"
                ;;
            *)
                # Try to get more info
                if [[ -f "/sys/class/net/$interface/address" ]]; then
                    local mac=$(cat "/sys/class/net/$interface/address" 2>/dev/null)
                    if [[ "$mac" == "00:15:5d:*" ]] || [[ "$mac" == "00:15:5d:"* ]]; then
                        echo "vEthernet (WSL Virtual Switch)"
                    else
                        echo "$interface"
                    fi
                else
                    echo "$interface"
                fi
                ;;
        esac
    else
        echo "$interface"
    fi
}

# ============================================
# GET SSID (For WSL - gets Windows host network info)
# ============================================

get_ssid() {
    # In WSL, we can try to get Windows host's SSID
    local ssid="N/A"
    
    # Method 1: Check Windows host via powershell
    if command -v powershell.exe &> /dev/null; then
        local win_ssid=$(powershell.exe -Command "(Get-NetConnectionProfile -ErrorAction SilentlyContinue).Name" 2>/dev/null | head -1 | tr -d '\r')
        if [[ -n "$win_ssid" ]] && [[ ! "$win_ssid" =~ error|failed|not\ found ]]; then
            ssid="$win_ssid"
        fi
    fi
    
    # Method 2: Check if connected to WiFi by looking at default gateway
    if [[ "$ssid" == "N/A" ]]; then
        local gateway=$(ip route show default 2>/dev/null | awk '/default/ {print $3}')
        if [[ -n "$gateway" ]]; then
            ssid="Wired"
        else
            ssid="Disconnected"
        fi
    fi
    
    echo "$ssid"
}

# ============================================
# GET IP ADDRESSES
# ============================================

get_ip_addresses() {
    local interface=$1
    
    # Get IPv4 address - multiple methods
    
    # Method 1: From /proc/net/fib_trie
    local ipv4=""
    if [[ -f "/proc/net/fib_trie" ]]; then
        ipv4=$(awk -v iface="$interface" '
            $0 ~ iface {
                for(i=1; i<=10; i++) {
                    getline
                    if ($0 ~ /32 host/) {
                        print $2
                        exit
                    }
                }
            }
        ' /proc/net/fib_trie 2>/dev/null | head -1)
    fi
    
    # Method 2: From ip command (fallback)
    if [[ -z "$ipv4" ]] && command -v ip &> /dev/null; then
        ipv4=$(ip -4 addr show dev $interface 2>/dev/null | awk '/inet / {print $2}' | cut -d'/' -f1 | head -1)
    fi
    
    # Method 3: From hostname
    if [[ -z "$ipv4" ]]; then
        ipv4=$(hostname -I 2>/dev/null | awk '{print $1}')
    fi
    
    # Get IPv6 address
    local ipv6=""
    
    # Method 1: From /proc/net/if_inet6
    if [[ -f "/proc/net/if_inet6" ]]; then
        ipv6=$(grep -A1 "$interface" /proc/net/if_inet6 2>/dev/null | awk '{print $4}' | head -1)
        if [[ -n "$ipv6" ]] && [[ ${#ipv6} -eq 32 ]]; then
            # Convert hex to IPv6
            ipv6=$(echo "$ipv6" | sed 's/.\{4\}/&:/g; s/:$//')
        fi
    fi
    
    # Method 2: From ip command (fallback)
    if [[ -z "$ipv6" ]] && command -v ip &> /dev/null; then
        ipv6=$(ip -6 addr show dev $interface 2>/dev/null | grep -v 'fe80::' | grep 'inet6' | head -1 | awk '{print $2}' | cut -d'/' -f1)
    fi
    
    # Method 3: Get link-local if nothing else
    if [[ -z "$ipv6" ]] && command -v ip &> /dev/null; then
        ipv6=$(ip -6 addr show dev $interface 2>/dev/null | grep 'fe80::' | head -1 | awk '{print $2}' | cut -d'/' -f1)
    fi
    
    # Set defaults
    [[ -z "$ipv4" ]] && ipv4="No IPv4"
    [[ -z "$ipv6" ]] && ipv6="No IPv6"
    
    echo "$ipv4,$ipv6"
}

# ============================================
# GET CONNECTION STATE
# ============================================

get_connection_state() {
    local interface=$1
    
    # Check carrier state
    local carrier=$(cat /sys/class/net/$interface/carrier 2>/dev/null)
    local operstate=$(cat /sys/class/net/$interface/operstate 2>/dev/null)
    
    if [[ "$operstate" == "up" ]] && [[ "$carrier" == "1" ]]; then
        echo "Connected"
    elif [[ "$operstate" == "up" ]]; then
        echo "No Carrier"
    else
        echo "Disconnected"
    fi
}

# ============================================
# DISPLAY FUNCTION
# ============================================

display_network_info() {
    local interface=$1
    local speeds=$2
    
    local send_kbps=$(echo "$speeds" | cut -d',' -f1)
    local receive_kbps=$(echo "$speeds" | cut -d',' -f2)
    
    local adapter_name=$(get_adapter_name "$interface")
    local ssid=$(get_ssid)
    local ips=$(get_ip_addresses "$interface")
    local ipv4=$(echo "$ips" | cut -d',' -f1)
    local ipv6=$(echo "$ips" | cut -d',' -f2)
    local state=$(get_connection_state "$interface")
    
    clear
    echo -e "${GREEN}════════════════════════════════════════${NC}"
    echo -e "${CYAN}        WSL Network Statistics${NC}"
    echo -e "${GREEN}════════════════════════════════════════${NC}"
    echo ""
    
    # Format numbers nicely
    printf "send:    %12s Kbps\n" "$send_kbps"
    printf "receive: %12s Kbps\n" "$receive_kbps"
    echo ""
    printf "adapter Name: %s\n" "$adapter_name"
    printf "SSID:    %s\n" "$ssid"
    printf "State:   %s\n" "$state"
    printf "IPv4:    %s\n" "$ipv4"
    printf "IPv6:    %s\n" "$ipv6"
    
    echo ""
    echo -e "${GREEN}════════════════════════════════════════${NC}"
    echo -e "${YELLOW}Interface: $interface${NC}"
    echo -e "${YELLOW}Press Ctrl+C to exit${NC}"
    echo -e "${GREEN}════════════════════════════════════════${NC}"
}

# ============================================
# SINGLE SHOT MODE (one-time display) - FIXED
# ============================================

single_shot() {
    local interface=$(get_wsl_interface)
    
    if [[ -z "$interface" ]] || [[ "$interface" == "lo" ]]; then
        echo -e "${RED}Error: No active network interface found${NC}"
        echo "Available interfaces:"
        ls /sys/class/net/ 2>/dev/null || echo "  None found"
        exit 1
    fi
    
    echo -e "${YELLOW}Measuring network speed (1 second)...${NC}"
    
    # Calculate speeds with 1 second interval
    local speeds=$(calculate_speeds "$interface" 1)
    
    local send_kbps=$(echo "$speeds" | cut -d',' -f1)
    local receive_kbps=$(echo "$speeds" | cut -d',' -f2)
    
    local adapter_name=$(get_adapter_name "$interface")
    local ssid=$(get_ssid)
    local ips=$(get_ip_addresses "$interface")
    local ipv4=$(echo "$ips" | cut -d',' -f1)
    local ipv6=$(echo "$ips" | cut -d',' -f2)
    local state=$(get_connection_state "$interface")
    
    echo -e "${GREEN}════════════════════════════════════════${NC}"
    echo -e "${CYAN}        WSL Network Statistics${NC}"
    echo -e "${GREEN}════════════════════════════════════════${NC}"
    echo ""
    
    printf "send:    %12s Kbps\n" "$send_kbps"
    printf "receive: %12s Kbps\n" "$receive_kbps"
    echo ""
    printf "adapter Name: %s\n" "$adapter_name"
    printf "SSID:    %s\n" "$ssid"
    printf "State:   %s\n" "$state"
    printf "IPv4:    %s\n" "$ipv4"
    printf "IPv6:    %s\n" "$ipv6"
    
    echo ""
    echo -e "${GREEN}════════════════════════════════════════${NC}"
    echo -e "Note: Speed measured over 1 second interval"
    echo -e "      Run 'monitor' mode for continuous updates"
    echo -e "${GREEN}════════════════════════════════════════${NC}"
}

# ============================================
# MONITOR MODE (continuous updates) - FIXED
# ============================================

monitor_mode() {
    local interval=${1:-2}
    local interface=$(get_wsl_interface)
    
    if [[ -z "$interface" ]] || [[ "$interface" == "lo" ]]; then
        echo -e "${RED}Error: No active network interface found${NC}"
        exit 1
    fi
    
    echo -e "${GREEN}Starting network monitor...${NC}"
    echo -e "Interface: ${CYAN}$interface${NC}"
    echo -e "Update interval: ${interval}s"
    echo -e "${YELLOW}Press Ctrl+C to exit${NC}"
    echo ""
    echo -e "${YELLOW}Waiting ${interval} seconds for first measurement...${NC}"
    sleep "$interval"
    
    # Initialize previous bytes
    local prev_bytes=$(get_current_bytes "$interface")
    
    while true; do
        local current_bytes=$(get_current_bytes "$interface")
        local prev_rx=$(echo "$prev_bytes" | cut -d',' -f1)
        local prev_tx=$(echo "$prev_bytes" | cut -d',' -f2)
        local curr_rx=$(echo "$current_bytes" | cut -d',' -f1)
        local curr_tx=$(echo "$current_bytes" | cut -d',' -f2)
        
        # Calculate rates
        local rx_rate=$(( (curr_rx - prev_rx) / interval ))
        local tx_rate=$(( (curr_tx - prev_tx) / interval ))
        
        # Convert to Kbps
        local rx_kbps=$(echo "scale=1; $rx_rate * 0.008" | bc 2>/dev/null || echo "0")
        local tx_kbps=$(echo "scale=1; $tx_rate * 0.008" | bc 2>/dev/null || echo "0")
        
        # Ensure non-negative
        rx_kbps=$(echo "$rx_kbps" | awk '{if ($1 < 0) print "0.0"; else print $1}')
        tx_kbps=$(echo "$tx_kbps" | awk '{if ($1 < 0) print "0.0"; else print $1}')
        
        # Update display
        clear
        echo -e "${GREEN}════════════════════════════════════════${NC}"
        echo -e "${CYAN}        WSL Network Statistics${NC}"
        echo -e "${GREEN}════════════════════════════════════════${NC}"
        echo ""
        
        printf "send:    %12s Kbps\n" "$tx_kbps"
        printf "receive: %12s Kbps\n" "$rx_kbps"
        echo ""
        
        # Only get these once to save CPU
        if [[ -z "$CACHED_INFO" ]]; then
            local adapter_name=$(get_adapter_name "$interface")
            local ssid=$(get_ssid)
            local ips=$(get_ip_addresses "$interface")
            local ipv4=$(echo "$ips" | cut -d',' -f1)
            local ipv6=$(echo "$ips" | cut -d',' -f2)
            local state=$(get_connection_state "$interface")
            CACHED_INFO="$adapter_name,$ssid,$state,$ipv4,$ipv6"
        fi
        
        local adapter_name=$(echo "$CACHED_INFO" | cut -d',' -f1)
        local ssid=$(echo "$CACHED_INFO" | cut -d',' -f2)
        local state=$(echo "$CACHED_INFO" | cut -d',' -f3)
        local ipv4=$(echo "$CACHED_INFO" | cut -d',' -f4)
        local ipv6=$(echo "$CACHED_INFO" | cut -d',' -f5)
        
        printf "adapter Name: %s\n" "$adapter_name"
        printf "SSID:    %s\n" "$ssid"
        printf "State:   %s\n" "$state"
        printf "IPv4:    %s\n" "$ipv4"
        printf "IPv6:    %s\n" "$ipv6"
        
        echo ""
        echo -e "${GREEN}════════════════════════════════════════${NC}"
        echo -e "${YELLOW}Interface: $interface | Update: ${interval}s${NC}"
        echo -e "${YELLOW}Press Ctrl+C to exit | $(date +%H:%M:%S)${NC}"
        echo -e "${GREEN}════════════════════════════════════════${NC}"
        
        # Update previous bytes
        prev_bytes="$current_bytes"
        sleep "$interval"
    done
}

# ============================================
# TEST MODE - Generate fake traffic to test
# ============================================

test_mode() {
    echo -e "${YELLOW}Testing network speed measurement...${NC}"
    echo -e "This will generate some network traffic to test the script."
    echo ""
    
    local interface=$(get_wsl_interface)
    
    # Generate some traffic
    echo -e "${CYAN}Pinging localhost to generate traffic...${NC}"
    ping -c 3 127.0.0.1 > /dev/null 2>&1
    
    # Also try to ping gateway
    local gateway=$(ip route show default 2>/dev/null | awk '/default/ {print $3}')
    if [[ -n "$gateway" ]]; then
        echo -e "${CYAN}Pinging gateway $gateway...${NC}"
        ping -c 2 $gateway > /dev/null 2>&1 &
    fi
    
    echo -e "${CYAN}Now measuring network speed...${NC}"
    echo ""
    
    # Run single shot with display
    single_shot
}

# ============================================
# HELP FUNCTION
# ============================================

show_help() {
    cat <<EOF

${GREEN}WSL Network Statistics - FIXED VERSION${NC}
Displays network info in format similar to Windows

${RED}FIXED: Now properly measures network speeds!${NC}

Usage: $0 [OPTION]

Options:
  (no option)   Single display with 1-second measurement
  monitor       Continuous monitoring (2s intervals)
  monitor N     Monitor with N seconds interval
  test          Generate test traffic and measure
  interface     Show current interface name
  debug         Show debug information
  help          Show this help

Examples:
  $0              # One-time display (measures for 1 second)
  $0 monitor      # Continuous monitoring (2s intervals)
  $0 monitor 1    # Continuous monitoring (1s intervals)
  $0 test         # Generate test traffic and measure
  $0 interface    # Show interface name

Why you saw zeros before:
- Network speed = (bytes_now - bytes_1_second_ago) / 1 second
- Original script didn't wait between measurements
- FIXED: Now waits 1 second between measurements

EOF
}

# ============================================
# DEBUG MODE
# ============================================

debug_mode() {
    echo -e "${YELLOW}=== DEBUG INFORMATION ===${NC}"
    echo ""
    
    # Check interface
    local interface=$(get_wsl_interface)
    echo -e "Interface: ${GREEN}$interface${NC}"
    echo ""
    
    # Check /proc/net/dev
    echo -e "${CYAN}/proc/net/dev entry:${NC}"
    grep "^\s*$interface:" /proc/net/dev 2>/dev/null || echo "  Not found!"
    echo ""
    
    # Check sysfs
    echo -e "${CYAN}/sys/class/net/$interface:${NC}"
    ls -la /sys/class/net/$interface/ 2>/dev/null || echo "  Not found!"
    echo ""
    
    # Check carrier/state
    echo -e "operstate: $(cat /sys/class/net/$interface/operstate 2>/dev/null)"
    echo -e "carrier: $(cat /sys/class/net/$interface/carrier 2>/dev/null)"
    echo ""
    
    # Test speed measurement
    echo -e "${CYAN}Testing speed calculation:${NC}"
    local bytes1=$(get_current_bytes "$interface")
    echo "Bytes at T1: $bytes1"
    sleep 1
    local bytes2=$(get_current_bytes "$interface")
    echo "Bytes at T2: $bytes2"
    
    local rx1=$(echo "$bytes1" | cut -d',' -f1)
    local tx1=$(echo "$bytes1" | cut -d',' -f2)
    local rx2=$(echo "$bytes2" | cut -d',' -f1)
    local tx2=$(echo "$bytes2" | cut -d',' -f2)
    
    echo "RX difference: $((rx2 - rx1)) bytes/sec"
    echo "TX difference: $((tx2 - tx1)) bytes/sec"
    
    local rx_kbps=$(echo "scale=1; ($rx2 - $rx1) * 0.008" | bc 2>/dev/null || echo "0")
    local tx_kbps=$(echo "scale=1; ($tx2 - $tx1) * 0.008" | bc 2>/dev/null || echo "0")
    
    echo "RX speed: $rx_kbps Kbps"
    echo "TX speed: $tx_kbps Kbps"
}

# ============================================
# MAIN SCRIPT
# ============================================

# Check if bc is available
if ! command -v bc &> /dev/null; then
    echo -e "${YELLOW}Installing 'bc' calculator...${NC}"
    sudo apt-get update > /dev/null 2>&1 && sudo apt-get install -y bc > /dev/null 2>&1
    echo -e "${GREEN}bc installed!${NC}"
fi

# Parse arguments
case "$1" in
    "monitor")
        INTERVAL=${2:-2}
        monitor_mode "$INTERVAL"
        ;;
    "test")
        test_mode
        ;;
    "interface")
        get_wsl_interface
        ;;
    "debug")
        debug_mode
        ;;
    "help"|"--help"|"-h")
        show_help
        ;;
    *)
        single_shot
        ;;
esac
