#!/bin/bash


get_cpu_all () {
    cpu_usage=$(grep '^cpu ' /proc/stat)
cpu_cores=$(grep -c ^processor /proc/cpuinfo)
cpu_freq=$(cat /proc/cpuinfo | grep "cpu MHz" | awk '{print $4}' | head -n 1)
cpu_model=$(cat /proc/cpuinfo | grep "model name" | awk -F ": " '{print $2}' | head -n 1)
cpu_model=$(cat /proc/cpuinfo | grep "model name" | awk -F ": " '{print $2}' | head -n 1)

}

echo "CPU Usage: $cpu_usage"
echo "CPU Cores: $cpu_cores"
echo "CPU Frequency: $cpu_freq"
echo "CPU Model: $cpu_model"

