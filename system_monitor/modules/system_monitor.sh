#!/bin/bash

get_load_average() {
    uptime | awk -F'load average:' '{print $2}' | sed 's/^ *//;s/ *$//'
}

get_uptime() {
    uptime -p | sed 's/up //'
}

get_process_count() {
    ps aux | wc -l
}

get_user_count() {
    who | wc -l
}

get_os_info() {
    if grep -q "Microsoft" /proc/version 2>/dev/null || [ -n "$WSL_DISTRO_NAME" ]; then
        echo "Windows (WSL)"
    elif [[ -f /etc/os-release ]]; then
        grep PRETTY_NAME /etc/os-release | cut -d'"' -f2
    else
        uname -srm
    fi
}

get_kernel_version() {
    uname -r
}

get_system_time() {
    date
}

get_timezone() {
    if [[ -f /etc/timezone ]]; then
        cat /etc/timezone
    else
        date +%Z
    fi
}

get_architecture() {
    uname -m
}

export -f get_load_average get_uptime get_process_count get_user_count get_os_info get_kernel_version get_system_time get_timezone get_architecture