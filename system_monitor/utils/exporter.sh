#!/bin/bash
# ============================================
# MULTI-FORMAT METRICS EXPORTER
# Supports JSON, CSV, XML, Prometheus formats
# ============================================

# Export metrics as JSON
export_json() {
    local metrics_data="$1"
    local output_file="${2:-}"
    
    if [[ -n "$output_file" ]]; then
        echo "$metrics_data" > "$output_file"
    else
        echo "$metrics_data"
    fi
}

# Export metrics as CSV
export_csv() {
    local metrics_json="$1"
    local output_file="${2:-}"
    
    local csv_output="timestamp,hostname,metric_category,metric_name,value,unit"
    
    # Extract timestamp and hostname
    local timestamp=$(echo "$metrics_json" | grep -o '"timestamp":"[^"]*"' | cut -d'"' -f4)
    local hostname=$(echo "$metrics_json" | grep -o '"hostname":"[^"]*"' | cut -d'"' -f4)
    
    # Parse metrics (simple extraction - use jq for complex JSON)
    if command -v jq &>/dev/null; then
        csv_output+=$'\n'
        csv_output+=$(echo "$metrics_json" | jq -r --arg ts "$timestamp" --arg host "$hostname" '
            .metrics | to_entries | .[] | 
            .value | to_entries | .[] |
            "\($ts),\($host),\(.key),\(.value),string,units"
        ' 2>/dev/null)
    else
        # Fallback: manual parsing
        # CPU metrics
        csv_output+=$'\n'"$timestamp,$hostname,cpu,usage_percent,$(echo "$metrics_json" | grep -o '"usage_percent":[^,}]*' | cut -d':' -f2),percent"
        csv_output+=$'\n'"$timestamp,$hostname,cpu,temperature_c,$(echo "$metrics_json" | grep -o '"temperature_c":"[^"]*"' | cut -d'"' -f4),celsius"
        
        # Memory metrics
        csv_output+=$'\n'"$timestamp,$hostname,memory,usage_percent,$(echo "$metrics_json" | grep -o '"usage_percent":[^,}]*' | cut -d':' -f2 | head -2 | tail -1),percent"
        
        # Disk metrics
        csv_output+=$'\n'"$timestamp,$hostname,disk,usage_percent,$(echo "$metrics_json" | grep -o '"usage_percent":[^,}]*' | cut -d':' -f2 | tail -1),percent"
    fi
    
    if [[ -n "$output_file" ]]; then
        echo "$csv_output" > "$output_file"
    else
        echo "$csv_output"
    fi
}

# Export metrics as XML
export_xml() {
    local metrics_json="$1"
    local output_file="${2:-}"
    
    local timestamp=$(echo "$metrics_json" | grep -o '"timestamp":"[^"]*"' | cut -d'"' -f4)
    local hostname=$(echo "$metrics_json" | grep -o '"hostname":"[^"]*"' | cut -d'"' -f4)
    
    local xml_output='<?xml version="1.0" encoding="UTF-8"?>'
    xml_output+=$'\n'"<system_metrics>"
    xml_output+=$'\n'"  <timestamp>$timestamp</timestamp>"
    xml_output+=$'\n'"  <hostname>$hostname</hostname>"
    xml_output+=$'\n'"  <metrics>"
    
    # CPU metrics
    xml_output+=$'\n'"    <cpu>"
    xml_output+=$'\n'"      <usage_percent>$(echo "$metrics_json" | grep -o '"usage_percent":[^,}]*' | cut -d':' -f2 | head -1)</usage_percent>"
    xml_output+=$'\n'"      <temperature>$(echo "$metrics_json" | grep -o '"temperature_c":"[^"]*"' | cut -d'"' -f4)</temperature>"
    xml_output+=$'\n'"    </cpu>"
    
    # Memory metrics
    xml_output+=$'\n'"    <memory>"
    xml_output+=$'\n'"      <usage_percent>$(echo "$metrics_json" | grep -o '"usage_percent":[^,}]*' | cut -d':' -f2 | head -2 | tail -1)</usage_percent>"
    xml_output+=$'\n'"    </memory>"
    
    # Disk metrics
    xml_output+=$'\n'"    <disk>"
    xml_output+=$'\n'"      <usage_percent>$(echo "$metrics_json" | grep -o '"usage_percent":[^,}]*' | cut -d':' -f2 | tail -1)</usage_percent>"
    xml_output+=$'\n'"    </disk>"
    
    xml_output+=$'\n'"  </metrics>"
    xml_output+=$'\n'"</system_metrics>"
    
    if [[ -n "$output_file" ]]; then
        echo "$xml_output" > "$output_file"
    else
        echo "$xml_output"
    fi
}

# Export metrics in Prometheus format
export_prometheus() {
    local metrics_json="$1"
    local output_file="${2:-}"
    
    local hostname=$(echo "$metrics_json" | grep -o '"hostname":"[^"]*"' | cut -d'"' -f4)
    local timestamp=$(date +%s)000  # Prometheus uses milliseconds
    
    local prom_output="# HELP system_cpu_usage_percent CPU usage percentage"
    prom_output+=$'\n'"# TYPE system_cpu_usage_percent gauge"
    
    local cpu_usage=$(echo "$metrics_json" | grep -o '"usage_percent":[^,}]*' | cut -d':' -f2 | head -1)
    prom_output+=$'\n'"system_cpu_usage_percent{hostname=\"$hostname\"} $cpu_usage $timestamp"
    
    prom_output+=$'\n\n'"# HELP system_memory_usage_percent Memory usage percentage"
    prom_output+=$'\n'"# TYPE system_memory_usage_percent gauge"
    local mem_usage=$(echo "$metrics_json" | grep -o '"usage_percent":[^,}]*' | cut -d':' -f2 | head -2 | tail -1)
    prom_output+=$'\n'"system_memory_usage_percent{hostname=\"$hostname\"} $mem_usage $timestamp"
    
    prom_output+=$'\n\n'"# HELP system_disk_usage_percent Disk usage percentage"
    prom_output+=$'\n'"# TYPE system_disk_usage_percent gauge"
    local disk_usage=$(echo "$metrics_json" | grep -o '"usage_percent":[^,}]*' | cut -d':' -f2 | tail -1)
    prom_output+=$'\n'"system_disk_usage_percent{hostname=\"$hostname\"} $disk_usage $timestamp"
    
    prom_output+=$'\n\n'"# HELP system_cpu_temperature_celsius CPU temperature in Celsius"
    prom_output+=$'\n'"# TYPE system_cpu_temperature_celsius gauge"
    local cpu_temp=$(echo "$metrics_json" | grep -o '"temperature_c":"[^"]*"' | cut -d'"' -f4 | grep -o '[0-9.]*')
    [[ -n "$cpu_temp" ]] && prom_output+=$'\n'"system_cpu_temperature_celsius{hostname=\"$hostname\"} $cpu_temp $timestamp"
    
    prom_output+=$'\n'
    
    if [[ -n "$output_file" ]]; then
        echo "$prom_output" > "$output_file"
    else
        echo "$prom_output"
    fi
}

# Export metrics in all enabled formats
export_all_formats() {
    local metrics_json="$1"
    local output_dir="${2:-$OUTPUT_DIR}"
    
    mkdir -p "$output_dir"
    
    # JSON (always enabled)
    if [[ "${ENABLE_JSON:-true}" == "true" ]]; then
        export_json "$metrics_json" "$output_dir/metrics.json"
        echo "Exported: $output_dir/metrics.json"
    fi
    
    # CSV
    if [[ "${ENABLE_CSV:-true}" == "true" ]]; then
        export_csv "$metrics_json" "$output_dir/metrics.csv"
        echo "Exported: $output_dir/metrics.csv"
    fi
    
    # XML
    if [[ "${ENABLE_XML:-false}" == "true" ]]; then
        export_xml "$metrics_json" "$output_dir/metrics.xml"
        echo "Exported: $output_dir/metrics.xml"
    fi
    
    # Prometheus
    if [[ "${ENABLE_PROMETHEUS:-false}" == "true" ]]; then
        export_prometheus "$metrics_json" "$output_dir/metrics.prom"
        echo "Exported: $output_dir/metrics.prom"
    fi
}

# Append to time-series file
append_timeseries() {
    local metrics_json="$1"
    local timeseries_file="${2:-$OUTPUT_DIR/timeseries.jsonl}"
    
    # JSONL format (JSON Lines) - one JSON object per line
    echo "$metrics_json" >> "$timeseries_file"
    
    # Rotate if file gets too large (>100MB)
    local file_size=$(stat -f%z "$timeseries_file" 2>/dev/null || stat -c%s "$timeseries_file" 2>/dev/null || echo 0)
    if [[ $file_size -gt $((100 * 1024 * 1024)) ]]; then
        local backup_file="${timeseries_file}.$(date +%Y%m%d_%H%M%S)"
        mv "$timeseries_file" "$backup_file"
        gzip "$backup_file" &
    fi
}

# Export snapshot with timestamp
export_snapshot() {
    local metrics_json="$1"
    local snapshot_dir="${2:-$OUTPUT_DIR/snapshots}"
    
    mkdir -p "$snapshot_dir"
    
    local timestamp=$(date +%Y%m%d_%H%M%S)
    local snapshot_file="$snapshot_dir/snapshot_$timestamp.json"
    
    export_json "$metrics_json" "$snapshot_file"
    echo "Snapshot saved: $snapshot_file"
}

# Clean old snapshots based on retention policy
clean_old_snapshots() {
    local snapshot_dir="${1:-$OUTPUT_DIR/snapshots}"
    local retention_days="${METRIC_RETENTION_DAYS:-7}"
    
    if [[ -d "$snapshot_dir" ]]; then
        find "$snapshot_dir" -name "snapshot_*.json" -type f -mtime "+$retention_days" -delete 2>/dev/null
        echo "Cleaned snapshots older than $retention_days days"
    fi
}

# Export functions
export -f export_json export_csv export_xml export_prometheus
export -f export_all_formats append_timeseries export_snapshot clean_old_snapshots
