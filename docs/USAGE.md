# System Monitor - Usage Guide

## Quick Start

### Run Single Metric Collection

```bash
# Bash monitoring (displays summary)
./integration/bridge.sh bash

# Python monitoring (displays summary)
./integration/bridge.sh python collect --output summary

# Integrated monitoring (both systems)
./integration/bridge.sh integrated
```

### Interactive Menu

```bash
# Launch interactive menu
./integration/bridge.sh menu

# Or simply:
./integration/bridge.sh
```

---

## Bash Monitoring

### Basic Usage

```bash
cd system_monitor

# Collect metrics once
./monitor.sh

# Collect and display JSON
./monitor.sh json

# Collect and display CSV
./monitor.sh csv

# Continuous monitoring (5 second interval)
./monitor.sh continuous

# Continuous with custom interval
./monitor.sh continuous 10
```

### Advanced Bash Features

```bash
# Source individual modules
source utils/platform_detect.sh
detect_os  # Returns: linux, macos, wsl, windows

# Check CPU metrics
source modules/cpu_monitor.sh
get_cpu_usage
get_cpu_temp
get_cpu_freq
get_cpu_cores

# Check memory metrics
source modules/memory_monitor.sh
get_memory_usage
get_total_memory
get_swap_usage

# Export metrics
source utils/exporter.sh
export_all_formats "$json_data" "./output"
```

### Output Formats

Bash monitoring supports multiple output formats:

- **JSON**: Structured, machine-readable
- **CSV**: Spreadsheet-compatible
- **XML**: Standardized format
- **Prometheus**: Metrics format for Prometheus

Configure in `config/monitor.yaml`:

```yaml
output:
  enable_json: true
  enable_csv: true
  enable_xml: false
  enable_prometheus: false
```

---

## Python Monitoring

### Command-Line Interface

```bash
# Activate virtual environment (if not auto-activated)
source python_monitor/venv/bin/activate

# Or run via integration bridge
cd /path/to/12thprojectos
```

### Collect Metrics

```bash
# Collect and display summary
./integration/bridge.sh python collect --output summary

# Collect and output JSON
./integration/bridge.sh python collect --output json

# Collect and save to database
./integration/bridge.sh python collect --save

# Specify custom database path
./integration/bridge.sh python collect --save --db-path /path/to/metrics.db
```

### Analyze Metrics

```bash
# Analyze last 24 hours of CPU metrics
./integration/bridge.sh python analyze --metric-type cpu --hours 24

# Analyze last week of memory metrics
./integration/bridge.sh python analyze --metric-type memory --hours 168

# Analyze disk metrics
./integration/bridge.sh python analyze --metric-type disk --hours 48
```

### Database Management

```bash
# View database statistics
./integration/bridge.sh python database stats

# View latest 10 records
./integration/bridge.sh python database latest --limit 10

# View latest CPU metrics
./integration/bridge.sh python database latest --metric-type cpu --limit 5

# Cleanup old records (keep last 7 days)
./integration/bridge.sh python database cleanup --retention-days 7

# Cleanup (keep last 30 days)
./integration/bridge.sh python database cleanup --retention-days 30
```

### Alert Testing

```bash
# Send test alert (log only)
./integration/bridge.sh python alert "Test alert message"

# Send critical alert
./integration/bridge.sh python alert "Critical issue!" --level CRITICAL

# Send via email (requires configuration)
./integration/bridge.sh python alert "Email test" --email

# Send via webhook
./integration/bridge.sh python alert "Webhook test" --webhook
```

---

## Configuration

### Main Configuration File

Edit `config/monitor.yaml`:

```yaml
# Collection interval
monitoring:
  interval: 5 # seconds
  continuous_interval: 60

# Alert thresholds
thresholds:
  cpu_alert_threshold: 90 # %
  memory_alert_threshold: 85 # %
  disk_alert_threshold: 90 # %
  temp_alert_threshold: 80 # Celsius

# Email alerts
alerts:
  smtp:
    server: "smtp.gmail.com"
    port: 587
    username: "your_email@gmail.com"
    password: "your_app_password"
    to_address: "alert_recipient@example.com"

# Data retention
retention:
  log_retention_days: 30
  metric_retention_days: 7
```

### Bash Configuration

Edit `system_monitor/utils/config.sh`:

```bash
# Monitoring interval
MONITOR_INTERVAL=5

# Alert thresholds
CPU_ALERT_THRESHOLD=90
MEMORY_ALERT_THRESHOLD=85
DISK_ALERT_THRESHOLD=90
```

---

## Use Cases

### 1. Real-time Monitoring

```bash
# Continuous monitoring with bash
cd system_monitor
./monitor.sh continuous 5

# Watch output update every 5 seconds
# Press Ctrl+C to stop
```

### 2. Historical Analysis

```bash
# Collect metrics every minute for analysis
while true; do
    ./integration/bridge.sh python collect --save
    sleep 60
done

# Then analyze:
./integration/bridge.sh python analyze --hours 24
```

### 3. Alert on High Usage

```bash
# Monitor and alert on high CPU
source system_monitor/modules/cpu_monitor.sh
source system_monitor/utils/error_handler.sh

usage=$(get_cpu_usage)
if (( $(echo "$usage > 90" | bc -l) )); then
    send_alert "High CPU usage: ${usage}%" "CRITICAL"
fi
```

### 4. Generate Reports

```bash
# Collect comprehensive metrics
./integration/bridge.sh integrated

# Results saved to:
# - output/integrated/bash_metrics_YYYYMMDD_HHMMSS.json
# - output/integrated/python_metrics_YYYYMMDD_HHMMSS.json
```

### 5. Cross-Platform Monitoring

```bash
# Script automatically detects OS and adjusts commands
source system_monitor/utils/platform_detect.sh

OS=$(detect_os)
echo "Running on: $OS"

# Get metrics appropriate for platform
CPU=$(get_cpu_usage)
MEM=$(get_memory_usage)
```

---

## Automated Monitoring

### Using Cron (Linux/macOS)

```bash
# Edit crontab
crontab -e

# Add entries:
# Run every 5 minutes
*/5 * * * * /path/to/12thprojectos/integration/bridge.sh python collect --save

# Daily analysis
0 8 * * * /path/to/12thprojectos/integration/bridge.sh python analyze --hours 24 > /tmp/daily_report.txt

# Weekly cleanup
0 0 * * 0 /path/to/12thprojectos/integration/bridge.sh python database cleanup --retention-days 7
```

### Using Systemd (Linux)

Create service file `/etc/systemd/system/monitor.service`:

```ini
[Unit]
Description=System Monitoring Service
After=network.target

[Service]
Type=simple
User=your_username
WorkingDirectory=/path/to/12thprojectos
ExecStart=/path/to/12thprojectos/integration/bridge.sh python collect --save
Restart=always
RestartSec=60

[Install]
WantedBy=multi-user.target
```

Enable and start:

```bash
sudo systemctl enable monitor.service
sudo systemctl start monitor.service
sudo systemctl status monitor.service
```

---

## Examples

### Example 1: Check Current System Status

```bash
./integration/bridge.sh bash
```

Output:

```
==========================================
     SYSTEM MONITORING SUMMARY
==========================================
Timestamp: 2025-12-06 10:30:00
Hostname: yahia-laptop
------------------------------------------
CPU Usage: 45.2%
CPU Temp: 62.5°C
GPU: NVIDIA (30.0%)
Memory Usage: 68.3%
Disk Usage: 55.1% (SMART: PASSED)
Network: eth0 - Connected
Load Average: 1.23, 1.45, 1.67
==========================================
```

### Example 2: Detailed Python Analysis

```bash
./integration/bridge.sh python collect --output json
```

Output:

```json
{
  "timestamp": "2025-12-06T10:30:00Z",
  "hostname": "yahia-laptop",
  "metrics": {
    "cpu": {
      "usage_percent": 45.2,
      "usage_per_core": [42.1, 48.3, 44.5, 46.0],
      "frequency": {
        "current": 2800.0,
        "min": 800.0,
        "max": 3500.0
      }
    },
    "memory": {
      "virtual": {
        "total_mb": 16384.0,
        "used_mb": 11200.0,
        "percent": 68.3
      }
    }
  }
}
```

### Example 3: Database Query

```bash
./integration/bridge.sh python database latest --limit 3
```

---

## Performance Tips

1. **Adjust collection interval** based on needs (longer = less overhead)
2. **Enable caching** in config for frequently accessed metrics
3. **Clean up old data** regularly to maintain database performance
4. **Use specific metric types** when querying to reduce data processing
5. **Run continuous monitoring** in background with `&` or screen/tmux

---

## Troubleshooting

### No data collected

```bash
# Check permissions
ls -l system_monitor/monitor.sh

# Make executable
chmod +x system_monitor/monitor.sh
```

### Python import errors

```bash
# Activate virtual environment
source python_monitor/venv/bin/activate

# Reinstall dependencies
pip install -r python_monitor/requirements.txt
```

### Database locked

```bash
# Close all Python processes accessing database
pkill -f monitor_cli.py

# Or remove lock (if safe)
rm python_monitor/data/metrics.db-journal
```

---

## API Reference

See individual module documentation:

- `system_monitor/modules/` - Bash module functions
- `python_monitor/monitors/` - Python monitor classes
- `python_monitor/cli/` - CLI reference

---

**Happy Monitoring!**
