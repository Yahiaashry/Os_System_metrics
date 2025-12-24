#!/bin/bash
# ============================================
# PLATFORM DETECTION AND OS COMPATIBILITY LAYER
# Project 12th - Arab Academy
# Member 1: Yahia Ashry - 231027201
# ============================================

# Detect Operating System
detect_os() {
    local os_type=""
    local os_version=""
    local os_arch=""
    
    # Get architecture
    os_arch=$(uname -m 2>/dev/null || echo "unknown")
    
    # Detect OS type
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then
        os_type="linux"
        
        # Check if running in WSL
        if grep -qi microsoft /proc/version 2>/dev/null || grep -qi wsl /proc/version 2>/dev/null; then
            os_type="wsl"
        fi
        
        # Get Linux distribution
        if [[ -f /etc/os-release ]]; then
            source /etc/os-release
            os_version="${ID:-unknown}"
        elif [[ -f /etc/redhat-release ]]; then
            os_version="rhel"
        elif [[ -f /etc/debian_version ]]; then
            os_version="debian"
        fi
        
    elif [[ "$OSTYPE" == "darwin"* ]]; then
        os_type="macos"
        os_version=$(sw_vers -productVersion 2>/dev/null || echo "unknown")
        
    elif [[ "$OSTYPE" == "cygwin" ]] || [[ "$OSTYPE" == "msys" ]] || [[ "$OSTYPE" == "win32" ]]; then
        os_type="windows"
        os_version="native"
        
    else
        os_type="unknown"
        os_version="unknown"
    fi
    
    export DETECTED_OS="$os_type"
    export DETECTED_OS_VERSION="$os_version"
    export DETECTED_OS_ARCH="$os_arch"
    
    echo "$os_type"
}

# Get package manager for the OS
get_package_manager() {
    local os="${DETECTED_OS:-$(detect_os)}"
    
    case "$os" in
        "linux"|"wsl")
            if command -v apt-get &>/dev/null; then
                echo "apt"
            elif command -v dnf &>/dev/null; then
                echo "dnf"
            elif command -v yum &>/dev/null; then
                echo "yum"
            elif command -v pacman &>/dev/null; then
                echo "pacman"
            elif command -v zypper &>/dev/null; then
                echo "zypper"
            else
                echo "unknown"
            fi
            ;;
        "macos")
            if command -v brew &>/dev/null; then
                echo "brew"
            elif command -v port &>/dev/null; then
                echo "macports"
            else
                echo "none"
            fi
            ;;
        "windows")
            if command -v choco &>/dev/null; then
                echo "choco"
            elif command -v scoop &>/dev/null; then
                echo "scoop"
            else
                echo "none"
            fi
            ;;
        *)
            echo "unknown"
            ;;
    esac
}

# Check if running with sufficient privileges
check_privileges() {
    local os="${DETECTED_OS:-$(detect_os)}"
    
    if [[ "$os" == "windows" ]]; then
        # Windows: check if running as Administrator
        net session &>/dev/null
        return $?
    else
        # Unix-like: check if running as root
        [[ $EUID -eq 0 ]]
        return $?
    fi
}

# Get CPU temperature command based on OS
get_cpu_temp_cmd() {
    local os="${DETECTED_OS:-$(detect_os)}"
    
    case "$os" in
        "linux"|"wsl")
            if [[ -f /sys/class/thermal/thermal_zone0/temp ]]; then
                echo "cat /sys/class/thermal/thermal_zone0/temp"
            elif command -v sensors &>/dev/null; then
                echo "sensors"
            else
                echo "none"
            fi
            ;;
        "macos")
            if command -v osx-cpu-temp &>/dev/null; then
                echo "osx-cpu-temp"
            elif command -v istats &>/dev/null; then
                echo "istats cpu temp"
            else
                echo "none"
            fi
            ;;
        "windows")
            echo "none"  # Windows requires WMI or third-party tools
            ;;
        *)
            echo "none"
            ;;
    esac
}

# Get GPU detection command based on OS
get_gpu_detect_cmd() {
    local os="${DETECTED_OS:-$(detect_os)}"
    
    # NVIDIA
    if command -v nvidia-smi &>/dev/null; then
        echo "nvidia-smi"
        return 0
    fi
    
    # AMD ROCm
    if command -v rocm-smi &>/dev/null; then
        echo "rocm-smi"
        return 0
    fi
    
    case "$os" in
        "linux"|"wsl")
            if command -v lspci &>/dev/null; then
                echo "lspci"
            else
                echo "none"
            fi
            ;;
        "macos")
            echo "system_profiler SPDisplaysDataType"
            ;;
        "windows")
            echo "wmic path win32_VideoController"
            ;;
        *)
            echo "none"
            ;;
    esac
}

# Get network interface listing command
get_network_cmd() {
    local os="${DETECTED_OS:-$(detect_os)}"
    
    case "$os" in
        "linux"|"wsl")
            if command -v ip &>/dev/null; then
                echo "ip addr show"
            elif command -v ifconfig &>/dev/null; then
                echo "ifconfig"
            else
                echo "cat /proc/net/dev"
            fi
            ;;
        "macos")
            echo "ifconfig"
            ;;
        "windows")
            echo "ipconfig"
            ;;
        *)
            echo "none"
            ;;
    esac
}

# Get process listing command
get_process_cmd() {
    local os="${DETECTED_OS:-$(detect_os)}"
    
    case "$os" in
        "linux"|"wsl"|"macos")
            if command -v ps &>/dev/null; then
                echo "ps aux"
            else
                echo "top -bn1"
            fi
            ;;
        "windows")
            echo "tasklist"
            ;;
        *)
            echo "none"
            ;;
    esac
}

# Get disk usage command
get_disk_cmd() {
    local os="${DETECTED_OS:-$(detect_os)}"
    
    case "$os" in
        "linux"|"wsl"|"macos")
            echo "df -h"
            ;;
        "windows")
            echo "wmic logicaldisk get size,freespace,caption"
            ;;
        *)
            echo "none"
            ;;
    esac
}

# Get memory info command
get_memory_cmd() {
    local os="${DETECTED_OS:-$(detect_os)}"
    
    case "$os" in
        "linux"|"wsl")
            if command -v free &>/dev/null; then
                echo "free -m"
            else
                echo "cat /proc/meminfo"
            fi
            ;;
        "macos")
            echo "vm_stat"
            ;;
        "windows")
            echo "wmic OS get FreePhysicalMemory,TotalVisibleMemorySize"
            ;;
        *)
            echo "none"
            ;;
    esac
}

# Get system uptime command
get_uptime_cmd() {
    local os="${DETECTED_OS:-$(detect_os)}"
    
    case "$os" in
        "linux"|"wsl"|"macos")
            if command -v uptime &>/dev/null; then
                echo "uptime"
            else
                echo "cat /proc/uptime"
            fi
            ;;
        "windows")
            echo "systeminfo | find \"System Boot Time\""
            ;;
        *)
            echo "none"
            ;;
    esac
}

# Install package using OS package manager
install_package() {
    local package_name="$1"
    local pkg_manager=$(get_package_manager)
    
    case "$pkg_manager" in
        "apt")
            sudo apt-get update && sudo apt-get install -y "$package_name"
            ;;
        "dnf")
            sudo dnf install -y "$package_name"
            ;;
        "yum")
            sudo yum install -y "$package_name"
            ;;
        "pacman")
            sudo pacman -S --noconfirm "$package_name"
            ;;
        "zypper")
            sudo zypper install -y "$package_name"
            ;;
        "brew")
            brew install "$package_name"
            ;;
        "macports")
            sudo port install "$package_name"
            ;;
        "choco")
            choco install -y "$package_name"
            ;;
        "scoop")
            scoop install "$package_name"
            ;;
        *)
            echo "Error: Unknown package manager. Please install $package_name manually."
            return 1
            ;;
    esac
}

# Check if command exists, suggest installation if not
ensure_command() {
    local cmd="$1"
    local package="${2:-$cmd}"
    
    if ! command -v "$cmd" &>/dev/null; then
        echo "Warning: '$cmd' not found."
        read -p "Would you like to install '$package'? (y/n) " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            install_package "$package"
            return $?
        else
            return 1
        fi
    fi
    return 0
}

# Get cross-platform temp directory
get_temp_dir() {
    local os="${DETECTED_OS:-$(detect_os)}"
    
    case "$os" in
        "linux"|"wsl"|"macos")
            echo "${TMPDIR:-/tmp}"
            ;;
        "windows")
            echo "${TEMP:-C:\\Temp}"
            ;;
        *)
            echo "/tmp"
            ;;
    esac
}

# Normalize path for current OS
normalize_path() {
    local path="$1"
    local os="${DETECTED_OS:-$(detect_os)}"
    
    case "$os" in
        "windows")
            # Convert forward slashes to backslashes for Windows
            echo "$path" | sed 's/\//\\/g'
            ;;
        *)
            # Convert backslashes to forward slashes for Unix-like
            echo "$path" | sed 's/\\/\//g'
            ;;
    esac
}

# Export functions
export -f detect_os get_package_manager check_privileges
export -f get_cpu_temp_cmd get_gpu_detect_cmd get_network_cmd
export -f get_process_cmd get_disk_cmd get_memory_cmd get_uptime_cmd
export -f install_package ensure_command get_temp_dir normalize_path

# Auto-detect OS on source
detect_os >/dev/null
