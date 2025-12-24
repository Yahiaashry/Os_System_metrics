#!/bin/bash

# ============================================
# WSL GPU Health Monitor
# Compatible with both NVIDIA and AMD GPUs
# ============================================

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Log file (optional)
# Use XDG_STATE_HOME or fallback to HOME, ensuring logs dir exists
LOG_DIR="${XDG_STATE_HOME:-$HOME}/.local/state/gpu_health"
mkdir -p "$LOG_DIR"
LOG_FILE="${LOG_DIR}/gpu_health.log"
DATE_FORMAT=$(date '+%Y-%m-%d %H:%M:%S')

# ============================================
# FUNCTION: Check if running in WSL
# ============================================
check_wsl() {
    if ! grep -qE "(Microsoft|WSL)" /proc/version 2>/dev/null; then
        echo -e "${RED}Error: This script is designed to run in WSL (Windows Subsystem for Linux)${NC}"
        echo "Please run this script from a WSL terminal"
        exit 1
    fi
    echo -e "${GREEN}✓ Running in WSL${NC}"
}

# ============================================
# FUNCTION: Detect GPU vendor
# ============================================
detect_gpu_vendor() {
    echo -e "\n${CYAN}[1] Detecting GPU Vendor...${NC}"
    
    # Check for NVIDIA
    if command -v nvidia-smi &> /dev/null; then
        if nvidia-smi --query-gpu=name --format=csv,noheader &>/dev/null; then
            GPU_VENDOR="NVIDIA"
            return 0
        fi
    fi
    
    # Check for AMD
    if command -v rocm-smi &> /dev/null; then
        if rocm-smi --showproductname --json &>/dev/null; then
            GPU_VENDOR="AMD"
            return 0
        fi
    fi
    
    # Check via lspci
    if command -v lspci &> /dev/null; then
        if lspci | grep -i "nvidia" &>/dev/null; then
            GPU_VENDOR="NVIDIA (tools not installed)"
            return 1
        elif lspci | grep -i "amd" &>/dev/null || lspci | grep -i "radeon" &>/dev/null; then
            GPU_VENDOR="AMD (tools not installed)"
            return 1
        fi
    fi
    
    GPU_VENDOR="Unknown"
    return 2
}

# ============================================
# FUNCTION: Install GPU monitoring tools
# ============================================
install_gpu_tools() {
    echo -e "\n${YELLOW}[!] Installing GPU monitoring tools...${NC}"
    
    if [[ "$GPU_VENDOR" == *"NVIDIA"* ]]; then
        echo "Installing NVIDIA tools..."
        sudo apt update
        # Try common NVIDIA driver versions
        for version in 535 525 520 515 510; do
            echo "Trying nvidia-utils-$version..."
            if sudo apt install -y nvidia-utils-$version 2>/dev/null; then
                echo -e "${GREEN}✓ Successfully installed nvidia-utils-$version${NC}"
                return 0
            fi
        done
        echo -e "${RED}Failed to install NVIDIA tools. Please install manually.${NC}"
        
    elif [[ "$GPU_VENDOR" == *"AMD"* ]]; then
        echo "Installing AMD tools..."
        sudo apt update
        if sudo apt install -y rocm-smi 2>/dev/null; then
            echo -e "${GREEN}✓ Successfully installed rocm-smi${NC}"
            return 0
        else
            echo -e "${YELLOW}Trying alternative: radeontop${NC}"
            sudo apt install -y radeontop
            return 0
        fi
    fi
    
    return 1
}

# ============================================
# FUNCTION: Check NVIDIA GPU
# ============================================
check_nvidia_gpu() {
    echo -e "\n${CYAN}[2] Checking NVIDIA GPU...${NC}"
    
    # Get basic info
    echo -e "${BLUE}GPU Information:${NC}"
    nvidia-smi --query-gpu=name,driver_version,pstate --format=csv 2>/dev/null
    
    # Get utilization and temperature
    echo -e "\n${BLUE}Current Status:${NC}"
    nvidia-smi --query-gpu=utilization.gpu,utilization.memory,temperature.gpu,power.draw,power.limit --format=csv 2>/dev/null
    
    # Get memory info
    echo -e "\n${BLUE}Memory Usage:${NC}"
    nvidia-smi --query-gpu=memory.total,memory.used,memory.free --format=csv 2>/dev/null
    
    # Check for critical conditions
    echo -e "\n${BLUE}Health Check:${NC}"
    TEMP=$(nvidia-smi --query-gpu=temperature.gpu --format=csv,noheader 2>/dev/null | xargs)
    UTIL=$(nvidia-smi --query-gpu=utilization.gpu --format=csv,noheader 2>/dev/null | sed 's/ %//' | xargs)
    
    # Temperature check
    if [[ ! -z "$TEMP" ]] && [[ "$TEMP" -gt 85 ]]; then
        echo -e "${RED}⚠ Warning: High GPU temperature: ${TEMP}°C${NC}"
    elif [[ ! -z "$TEMP" ]]; then
        echo -e "${GREEN}✓ Temperature: ${TEMP}°C (Normal)${NC}"
    fi
    
    # Utilization check
    if [[ ! -z "$UTIL" ]] && [[ "$UTIL" -gt 95 ]]; then
        echo -e "${YELLOW}⚠ High GPU utilization: ${UTIL}%${NC}"
    elif [[ ! -z "$UTIL" ]]; then
        echo -e "${GREEN}✓ Utilization: ${UTIL}%${NC}"
    fi
    
    # Check for errors
    echo -e "\n${BLUE}Error Counters:${NC}"
    nvidia-smi --query-gpu=retired_pages.sbe,retired_pages.dbe --format=csv 2>/dev/null
}

# ============================================
# FUNCTION: Check AMD GPU
# ============================================
check_amd_gpu() {
    echo -e "\n${CYAN}[2] Checking AMD GPU...${NC}"
    
    # Try rocm-smi first
    if command -v rocm-smi &> /dev/null; then
        echo -e "${BLUE}GPU Information:${NC}"
        rocm-smi --showproductname
        
        echo -e "\n${BLUE}Current Status:${NC}"
        rocm-smi --showuse --showtemp --showpower
        
        echo -e "\n${BLUE}Memory Usage:${NC}"
        rocm-smi --showmeminfo vram
        
        echo -e "\n${BLUE}Health Check:${NC}"
        # Extract temperature
        TEMP=$(rocm-smi -t | grep "Temperature" | grep -oE '[0-9]+' | head -1)
        UTIL=$(rocm-smi -u | grep "GPU use" | grep -oE '[0-9]+' | head -1)
        
        if [[ ! -z "$TEMP" ]] && [[ "$TEMP" -gt 85 ]]; then
            echo -e "${RED}⚠ Warning: High GPU temperature: ${TEMP}°C${NC}"
        elif [[ ! -z "$TEMP" ]]; then
            echo -e "${GREEN}✓ Temperature: ${TEMP}°C (Normal)${NC}"
        fi
        
        if [[ ! -z "$UTIL" ]] && [[ "$UTIL" -gt 95 ]]; then
            echo -e "${YELLOW}⚠ High GPU utilization: ${UTIL}%${NC}"
        elif [[ ! -z "$UTIL" ]]; then
            echo -e "${GREEN}✓ Utilization: ${UTIL}%${NC}"
        fi
        
    # Fallback to radeontop
    elif command -v radeontop &> /dev/null; then
        echo -e "${YELLOW}Using radeontop for monitoring (run separately):${NC}"
        echo "Command: sudo radeontop"
        echo "Press Ctrl+C to exit radeontop"
        echo -e "\n${BLUE}Quick check:${NC}"
        timeout 2 sudo radeontop -d "${TMPDIR:-/tmp}/radeontop.out"
        if [[ -f "${TMPDIR:-/tmp}/radeontop.out" ]]; then
            cat "${TMPDIR:-/tmp}/radeontop.out" | head -5
            rm "${TMPDIR:-/tmp}/radeontop.out"
        fi
    fi
}

# ============================================
# FUNCTION: Log results
# ============================================
log_results() {
    if [[ "$ENABLE_LOG" == "true" ]]; then
        echo -e "\n${CYAN}[3] Logging results to ${LOG_FILE}...${NC}"
        {
            echo "=== GPU Health Check - ${DATE_FORMAT} ==="
            echo "Vendor: ${GPU_VENDOR}"
            echo "WSL Version: $(uname -r)"
            if [[ "$GPU_VENDOR" == "NVIDIA" ]]; then
                nvidia-smi --query-gpu=timestamp,name,utilization.gpu,temperature.gpu,memory.used,memory.total --format=csv,noheader 2>/dev/null
            elif [[ "$GPU_VENDOR" == "AMD" ]]; then
                rocm-smi --showproductname --showuse --showtemp --showmeminfo vram --json 2>/dev/null | jq -r '.card0 | "\(."Card SKU"), \(."GPU use (%)")%, \(."Temperature (C)")°C, \(."VRAM Total Memory (B)")B, \(."VRAM Total Used Memory (B)")B"' 2>/dev/null || echo "Raw data available in JSON format"
            fi
            echo "======================================"
        } >> "$LOG_FILE"
        echo -e "${GREEN}✓ Log saved${NC}"
    fi
}

# ============================================
# FUNCTION: Display summary
# ============================================
display_summary() {
    echo -e "\n${CYAN}======================================${NC}"
    echo -e "${CYAN}         GPU HEALTH SUMMARY          ${NC}"
    echo -e "${CYAN}======================================${NC}"
    echo -e "Vendor:        ${GREEN}${GPU_VENDOR}${NC}"
    echo -e "Time:          ${DATE_FORMAT}"
    echo -e "WSL Kernel:    $(uname -r)"
    echo -e "Script Status: ${GREEN}Completed${NC}"
    
    if [[ "$GPU_VENDOR" == "NVIDIA" ]] || [[ "$GPU_VENDOR" == "AMD" ]]; then
        echo -e "Next Steps:    Run './gpu_health.sh monitor' for continuous monitoring"
    else
        echo -e "${YELLOW}Recommendation: Install GPU tools for detailed monitoring${NC}"
    fi
    echo -e "${CYAN}======================================${NC}"
}

# ============================================
# FUNCTION: Continuous monitoring mode
# ============================================
monitor_mode() {
    echo -e "${CYAN}Starting GPU monitor (2-second intervals)${NC}"
    echo -e "Press ${RED}Ctrl+C${NC} to stop monitoring\n"
    
    while true; do
        clear
        echo -e "${CYAN}=== Live GPU Monitoring === $(date '+%H:%M:%S')${NC}"
        echo -e "${CYAN}Press Ctrl+C to exit${NC}\n"
        
        if [[ "$GPU_VENDOR" == "NVIDIA" ]]; then
            nvidia-smi --query-gpu=utilization.gpu,temperature.gpu,memory.used,memory.total --format=csv
        elif [[ "$GPU_VENDOR" == "AMD" ]] && command -v rocm-smi &>/dev/null; then
            rocm-smi --showuse --showtemp --showmeminfo vram
        else
            echo "Monitoring not available for current configuration"
            break
        fi
        
        sleep 2
    done
}

# ============================================
# FUNCTION: Show help
# ============================================
show_help() {
    echo -e "${CYAN}WSL GPU Health Monitor${NC}"
    echo "Usage: $0 [OPTION]"
    echo ""
    echo "Options:"
    echo "  (no option)    Run single health check"
    echo "  monitor        Run continuous monitoring"
    echo "  install        Install GPU monitoring tools"
    echo "  log            Enable logging to ~/.local/state/gpu_health/gpu_health.log"
    echo "  help           Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0              # Single health check"
    echo "  $0 monitor      # Live monitoring"
    echo "  $0 install      # Install tools"
    echo "  $0 log          # Run with logging enabled"
}

# ============================================
# MAIN SCRIPT
# ============================================

# Parse command line arguments
MODE="check"
ENABLE_LOG="false"

case "$1" in
    "monitor")
        MODE="monitor"
        ;;
    "install")
        MODE="install"
        ;;
    "log")
        ENABLE_LOG="true"
        ;;
    "help"|"--help"|"-h")
        show_help
        exit 0
        ;;
esac

# Main execution
echo -e "${CYAN}=== WSL GPU Health Monitor ===${NC}"

# Check if running in WSL
check_wsl

# Detect GPU vendor
if ! detect_gpu_vendor; then
    echo -e "${YELLOW}⚠ GPU detected but monitoring tools not installed${NC}"
    if [[ "$MODE" == "install" ]]; then
        install_gpu_tools
        # Re-detect after installation
        detect_gpu_vendor
    else
        echo -e "Run: ${CYAN}$0 install${NC} to install monitoring tools"
    fi
fi

echo -e "Detected: ${GREEN}${GPU_VENDOR}${NC}"

# Execute based on mode
case "$MODE" in
    "check")
        if [[ "$GPU_VENDOR" == "NVIDIA" ]]; then
            check_nvidia_gpu
        elif [[ "$GPU_VENDOR" == "AMD" ]]; then
            check_amd_gpu
        else
            echo -e "${YELLOW}No supported GPU detected or tools not available${NC}"
            echo "Available tools:"
            command -v nvidia-smi &>/dev/null && echo "✓ nvidia-smi" || echo "✗ nvidia-smi"
            command -v rocm-smi &>/dev/null && echo "✓ rocm-smi" || echo "✗ rocm-smi"
            command -v radeontop &>/dev/null && echo "✓ radeontop" || echo "✗ radeontop"
        fi
        log_results
        display_summary
        ;;
    
    "monitor")
        if [[ "$GPU_VENDOR" == "NVIDIA" ]] || [[ "$GPU_VENDOR" == "AMD" ]]; then
            monitor_mode
        else
            echo -e "${RED}Cannot monitor: No GPU tools available${NC}"
            echo "Run '$0 install' first"
        fi
        ;;
    
    "install")
        install_gpu_tools
        ;;
esac

echo -e "\n${GREEN}Script completed!${NC}"
