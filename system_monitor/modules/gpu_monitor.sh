#!/bin/bash

get_gpu_model() {
    if command -v nvidia-smi &> /dev/null; then
        nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null | head -1 | sed 's/^[ \t]*//;s/[ \t]*$//' || echo "Unknown GPU"
    elif command -v rocm-smi &> /dev/null; then
        rocm-smi --showproductname 2>/dev/null | grep "GPU" | awk '{print $2,$3,$4}' || echo "Unknown GPU"
    elif command -v lspci &> /dev/null; then
        lspci 2>/dev/null | grep -i "VGA\|3D" | head -1 | cut -d: -f3 | sed 's/^[ \t]*//;s/[ \t]*$//' || echo "Unknown GPU"
    else
        echo "Unknown GPU"
    fi
}

get_gpu_type() {
    if command -v nvidia-smi &> /dev/null; then
        echo "NVIDIA"
    elif command -v rocm-smi &> /dev/null; then
        echo "AMD"
    elif ls /sys/class/drm/card*/device 2>/dev/null | grep -q card; then
        echo "Integrated"
    else
        echo "None"
    fi
}

get_gpu_usage() {
    local gpu_type=$(get_gpu_type)
    case "$gpu_type" in
        "NVIDIA")
            local usage=$(nvidia-smi --query-gpu=utilization.gpu --format=csv,noheader,nounits 2>/dev/null | head -1 | grep -o '[0-9]*')
            echo "${usage:-0}"
            ;;
        "AMD")
            rocm-smi --showuse 2>/dev/null | grep "GPU Utilization" | awk '{print $3}' | sed 's/%//' || echo "0"
            ;;
        *)
            echo "0"
            ;;
    esac
}

get_gpu_temp() {
    local gpu_type=$(get_gpu_type)
    case "$gpu_type" in
        "NVIDIA")
            nvidia-smi --query-gpu=temperature.gpu --format=csv,noheader 2>/dev/null | head -1 | tr -d ' ' || echo "N/A"
            ;;
        "AMD")
            rocm-smi --showtemp 2>/dev/null | grep "GPU Temperature" | awk '{print $3}' | sed 's/C//' || echo "N/A"
            ;;
        *)
            echo "N/A"
            ;;
    esac
}

get_gpu_memory() {
    local gpu_type=$(get_gpu_type)
    case "$gpu_type" in
        "NVIDIA")
            nvidia-smi --query-gpu=memory.used --format=csv,noheader,nounits 2>/dev/null | head -1 | tr -d ' ' || echo "0"
            ;;
        *)
            echo "0"
            ;;
    esac
}

get_gpu_total_memory() {
    local gpu_type=$(get_gpu_type)
    case "$gpu_type" in
        "NVIDIA")
            nvidia-smi --query-gpu=memory.total --format=csv,noheader,nounits 2>/dev/null | head -1 | tr -d ' ' || echo "0"
            ;;
        "AMD")
            rocm-smi --showmeminfo vram 2>/dev/null | grep "Total" | awk '{print $3}' || echo "0"
            ;;
        *)
            echo "0"
            ;;
    esac
}

get_gpu_driver() {
    local gpu_type=$(get_gpu_type)
    case "$gpu_type" in
        "NVIDIA")
            nvidia-smi --query-gpu=driver_version --format=csv,noheader 2>/dev/null | head -1 || echo "N/A"
            ;;
        "AMD")
            rocm-smi --showdriverversion 2>/dev/null | grep "Driver" | awk '{print $2}' || echo "N/A"
            ;;
        *)
            echo "N/A"
            ;;
    esac
}

check_gpu_alerts() {
    local gpu_usage=$(get_gpu_usage)
    local gpu_temp=$(get_gpu_temp)
    
    if [[ "$gpu_usage" != "0" ]] && [[ "$gpu_usage" != "N/A" ]]; then
        if (( $(echo "$gpu_usage > ${GPU_ALERT_THRESHOLD:-90}" | bc -l 2>/dev/null) )); then
            send_alert "GPU usage is high: ${gpu_usage}% (threshold: ${GPU_ALERT_THRESHOLD:-90}%)" "WARNING"
        fi
    fi
    
    if [[ "$gpu_temp" != "N/A" ]] && [[ -n "$gpu_temp" ]] && [[ "$gpu_temp" =~ ^[0-9]+$ ]]; then
        if (( $(echo "$gpu_temp > ${GPU_TEMP_THRESHOLD:-85}" | bc -l 2>/dev/null) )); then
            send_alert "GPU temperature is high: ${gpu_temp}°C (threshold: ${GPU_TEMP_THRESHOLD:-85}°C)" "CRITICAL"
        fi
    fi
}

# Get multiple GPU info if available
get_all_gpus_info() {
    local gpu_type=$(get_gpu_type)
    
    case "$gpu_type" in
        "NVIDIA")
            if command -v nvidia-smi &>/dev/null; then
                nvidia-smi --query-gpu=index,name,utilization.gpu,temperature.gpu,memory.used,memory.total --format=csv,noheader 2>/dev/null
            fi
            ;;
        "AMD")
            if command -v rocm-smi &>/dev/null; then
                rocm-smi --showuse --showtemp --showmeminfo 2>/dev/null
            fi
            ;;
        *)
            echo "No GPU information available"
            ;;
    esac
}

# Check GPU power consumption (NVIDIA only)
get_gpu_power() {
    if command -v nvidia-smi &>/dev/null; then
        nvidia-smi --query-gpu=power.draw --format=csv,noheader,nounits 2>/dev/null | head -1 || echo "N/A"
    else
        echo "N/A"
    fi
}

export -f get_gpu_type get_gpu_usage get_gpu_temp get_gpu_memory get_gpu_total_memory get_gpu_driver
export -f check_gpu_alerts get_all_gpus_info get_gpu_power
