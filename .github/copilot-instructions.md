# Copilot Instructions - System Monitoring Solution

## Project Context

**Academic Project**: Operating Systems Course (Project 12th) - Arab Academy for Science, Technology & Maritime Transport  
**Member 1**: Yahia Ashry (231027201) - System metrics collection scripts (bash/PowerShell)  
**Focus**: Advanced bash scripting for system monitoring with Python for analytics only

### Project Requirements Fulfilled

**Monitoring Targets**: ✅ CPU (performance, temperature), GPU (utilization, health), Disk (usage, SMART status), Memory (consumption), Network (interface statistics), System load metrics

**Technologies**: ✅ Bash scripting (primary), Python (analytics only), Dialog/Whiptail (GUI dashboard), SQLite (data storage), Markdown/HTML (reporting)

**Key Components**: ✅ Resource monitoring scripts, Alert system (threshold-based), Interactive dashboard, Historical data tracking

## Architecture Overview

**Dual-Platform Hybrid System**: This project implements cross-platform system monitoring with separate data collection layers that share a unified SQLite database.

### Three-Tier Architecture

1. **Data Collection (Platform-Specific)** - Member 1 Responsibility
   - **Bash Scripts** (`system_monitor/*.sh`): Modular bash monitoring with platform detection - supports Linux, macOS, WSL
     - Six monitoring modules: `cpu_monitor.sh`, `memory_monitor.sh`, `disk_monitor.sh`, `network_monitor.sh`, `gpu_monitor.sh`, `system_monitor.sh`
     - Five utility modules: `config.sh`, `logger.sh`, `error_handler.sh`, `platform_detect.sh`, `history_tracker.sh`
   - **Windows Native** (`windows_monitor/*.ps1`): PowerShell scripts using native performance counters
     - Parallel implementation for Windows-native monitoring
2. **Processing & Analytics (Python)** - Advanced Processing Layer
   - `python_monitor/analytics/`: Trend analysis, anomaly detection, moving averages, percentile calculations
   - `python_monitor/database/`: SQLite time-series storage with `data_source` tagging
   - `python_monitor/reporting/`: HTML/Markdown report generation with matplotlib charts
3. **User Interfaces**
   - `windows_launcher.ps1`: PowerShell menu (8 options) for Windows users, orchestrates WSL
   - `system_monitor/dashboard/dashboard.sh`: Interactive TUI using dialog/whiptail (9 dashboard options)

### Critical Design Decisions

**Python is NOT used for data collection** - only for analytics, database operations, and report generation. This is an explicit architectural choice per project requirements to showcase bash scripting capabilities.

**Data Source Tracking**: All metrics tagged with `data_source` field (`'windows'` or `'python'`) in unified `metrics.db` SQLite database to distinguish collection platform.

**Path Duality**: Windows installation uses two parallel directories:

- WSL path: `\\wsl.localhost\Ubuntu\home\yahia\12thprojectos` (Python, database, bash scripts)
- Windows path: `C:\Users\HP\Desktop\Projects\OS-Project` (PowerShell monitoring scripts)

## Developer Workflows

### First-Time Setup

```powershell
# From Windows PowerShell
.\windows_launcher.ps1
# Note: Option [1] Setup has been deprecated
# Dependencies should be installed manually if needed:
# - Bash: bc, jq, yq, curl
# - Python: Create venv and install requirements.txt
# - Make scripts executable: chmod +x system_monitor/**/*.sh
```

### Running Monitoring

**Windows monitoring** (option 2):

```powershell
# Runs: windows_monitor/windows_monitor.ps1 -Continuous -Interval 5
# Saves to: metrics.db with data_source='windows'
```

**Bash monitoring** (option 3):

```bash
# Runs: system_monitor/monitor.sh
# Displays real-time dashboard in terminal
# Stores history in: system_monitor/data/history/*.history
```

**Interactive Dashboard** (option 8):

```bash
# Runs: system_monitor/dashboard/dashboard.sh
# Dialog/whiptail-based TUI with 9 options
# Real-time metrics, alerts, logs, continuous monitoring
```

### Generating Reports

```powershell
# Option 4 in launcher
# Executes: python_monitor/reporting/report_generator.py
# Output: reports/report_YYYYMMDD_HHMMSS.html
# Charts saved to: reports/charts/
```

### Testing & Validation

```bash
# Performance benchmarks
bash tests/benchmark.sh

# Test monitoring directly
bash system_monitor/monitor.sh
```

## Project-Specific Conventions

### Bash Module Pattern

All bash monitoring modules follow this structure:

```bash
# system_monitor/modules/cpu_monitor.sh
get_cpu_usage() { ... }
get_cpu_temp() { ... }
get_cpu_cores() { ... }
check_cpu_alerts() { ... }  # Threshold-based alerting
# Each module exports multiple getter functions
```

Main controller (`monitor.sh`) sources all modules and calls functions:

```bash
source "$SCRIPT_DIR/modules/cpu_monitor.sh"
cpu_usage=$(get_cpu_usage)
```

**Module Sourcing Order** (critical):

```bash
source "$SCRIPT_DIR/utils/config.sh"       # 1. Load configuration first
source "$SCRIPT_DIR/utils/logger.sh"       # 2. Initialize logging
source "$SCRIPT_DIR/utils/error_handler.sh" # 3. Error handling + send_alert()
source "$SCRIPT_DIR/utils/platform_detect.sh" # 4. OS detection
source "$SCRIPT_DIR/utils/history_tracker.sh" # 5. Historical tracking
# Now safe to load monitoring modules
source "$SCRIPT_DIR/modules/cpu_monitor.sh"
```

### Alert System (Threshold-Based)

Each monitoring module implements threshold checking:

```bash
# In cpu_monitor.sh, disk_monitor.sh, gpu_monitor.sh, etc.
check_cpu_alerts() {
    local cpu_usage=$(get_cpu_usage)
    if (( $(echo "$cpu_usage > ${CPU_ALERT_THRESHOLD:-90}" | bc -l) )); then
        send_alert "CPU usage high: ${cpu_usage}%" "WARNING"
    fi
}
```

Alert delivery (in `utils/error_handler.sh`):

- Log-based alerts (always): Written to `system_monitor/logs/system_monitor.log`
- Email alerts (optional): If `ALERT_EMAIL` configured in `config/monitor.yaml`
- Webhook alerts (optional): If `ALERT_WEBHOOK` configured

Thresholds configurable via YAML:

```yaml
thresholds:
  cpu_alert_threshold: 90
  memory_alert_threshold: 85
  disk_alert_threshold: 90
  gpu_alert_threshold: 90
  gpu_temp_threshold: 85
```

### Historical Data Tracking

`utils/history_tracker.sh` provides time-series analysis:

```bash
store_sample "cpu_usage" "$cpu_value"      # Store metric
get_history "cpu_usage" 10                 # Last 10 samples
get_historical_average "cpu_usage"         # Calculate avg
get_trend "cpu_usage"                       # Returns: increasing/decreasing/stable
get_historical_min/max "cpu_usage"         # Min/max values
```

Storage: `system_monitor/data/history/*.history` (text files: `timestamp value`)  
Retention: Last 100 samples per metric (auto-trimmed)

### PowerShell Function Pattern

Windows monitors return hashtables:

```powershell
# windows_monitor/cpu_monitor.ps1
function Get-CPUMetrics {
    return @{
        'overall_usage' = ...
        'per_core_usage' = @(...)
        'frequency_mhz' = ...
    }
}
```

### Python Database Interaction

Always use `MetricsDatabase` class with `data_source` parameter:

```python
from python_monitor.database.metrics_db import MetricsDatabase
db = MetricsDatabase("metrics.db")
db.insert_metrics(hostname, "cpu", data, status="OK", data_source="python")
```

Query by data source:

```python
db.get_metrics_by_source(hours=24, data_source="windows")  # Windows metrics only
db.get_metrics_by_source(hours=24, data_source="python")   # Python/Linux metrics
```

### Configuration via YAML

`config/monitor.yaml` defines platform-specific settings:

```yaml
platforms:
  windows:
    enabled: true
    interval: 5
    data_source: "windows"
  python:
    enabled: true
    interval: 5
    data_source: "python"
```

Always respect `data_source` field when modifying database operations.

## Integration Points

### WSL Bridge

`windows_launcher.ps1` invokes WSL commands using:

```powershell
wsl -d Ubuntu -e bash -c "cd /home/yahia/12thprojectos && <command>"
```

### Database Schema

```sql
CREATE TABLE metrics (
    id INTEGER PRIMARY KEY,
    timestamp DATETIME NOT NULL,
    hostname TEXT NOT NULL,
    metric_type TEXT NOT NULL,
    metric_data TEXT NOT NULL,      -- JSON string
    status TEXT,
    data_source TEXT DEFAULT 'python',  -- 'windows' or 'python'
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP
)
```

### Cross-Platform Utilities

`system_monitor/utils/platform_detect.sh` provides OS detection:

- `detect_os()`: Returns 'linux', 'macos', 'wsl', 'windows'
- Commands auto-adjust based on detected platform (e.g., `nvidia-smi` vs `wmic`)

## Key Files & Directories

- `windows_launcher.ps1`: Main entry point for Windows users (8-option menu)
- `system_monitor/monitor.sh`: Bash monitoring controller
- `system_monitor/modules/`: Six monitoring modules (cpu, memory, disk, network, gpu, system)
- `system_monitor/utils/`: Cross-cutting concerns (logging, error handling, platform detection, history tracking, parallel execution)
- `system_monitor/dashboard/dashboard.sh`: Interactive TUI using dialog/whiptail (9 options)
- `windows_monitor/`: Six PowerShell monitoring modules plus main controller
- `python_monitor/`: Python package for analytics, database, reporting, CLI
- `config/monitor.yaml`: Centralized configuration
- `metrics.db`: Unified SQLite database at project root
- `tests/benchmark.sh`: Performance testing

## Dependencies

**Bash**: bc, jq, yq, curl (install manually if needed)  
**Python**: matplotlib, pyyaml, sqlite3 (see `python_monitor/requirements.txt`)  
**PowerShell**: Built-in cmdlets, no external modules  
**Optional**: nvidia-smi (GPU monitoring), sensors (Linux temperature)

## Common Pitfalls

1. **Never use Python for data collection** - it's architecturally separated for analytics only
2. **Always tag data_source** when inserting metrics - critical for multi-platform reporting
3. **Path handling**: Use forward slashes in bash, backslashes in PowerShell, `\\wsl.localhost\` prefix for cross-boundary access
4. **WSL requirement**: Windows launcher expects WSL Ubuntu at `\\wsl.localhost\Ubuntu\home\yahia\12thprojectos`
5. **Module sourcing order**: In bash scripts, always source `config.sh` → `logger.sh` → `error_handler.sh` before other modules
6. **Database location**: Always at project root `metrics.db` (not in subdirectories)
7. **Alert function availability**: `send_alert()` only available after sourcing `error_handler.sh` - don't call before initialization
8. **History storage**: Call `init_history()` before using `store_sample()` or queries will fail silently

## Key Project Features

### Interactive Dashboard (Dialog/Whiptail TUI)

`system_monitor/dashboard/dashboard.sh` provides 9 menu options:

1. View Real-Time Metrics - Live snapshot of all system metrics
2. View Detailed CPU Info - Per-core usage, frequency, architecture
3. View GPU Information - Type, usage, temperature, memory
4. View Disk Status - Usage, I/O stats, SMART health
5. View Network Status - Interface stats, bandwidth, connections
6. Configure Alerts - Adjust thresholds interactively
7. View System Logs - Browse monitoring logs
8. Generate Report - Trigger Python report generation
9. Continuous Monitoring - Auto-refresh every N seconds

### Error Handling Pattern

All bash scripts use standardized error handling:

```bash
# In utils/error_handler.sh
handle_error() {
    local exit_code=$?
    local line_number=$1
    local error_msg="${2:-Unknown error}"
    log_message "ERROR" "Error on line $line_number: $error_msg (exit code: $exit_code)"
    send_alert "System monitoring error: $error_msg" "ERROR"
}
trap 'handle_error ${LINENO}' ERR
```

### Platform Detection & Adaptation

`utils/platform_detect.sh` exports:

- `DETECTED_OS`: 'linux', 'macos', 'wsl', 'windows'
- `DETECTED_OS_VERSION`: Distribution or version
- Auto-adjusts commands (e.g., `nvidia-smi` on Linux vs `wmic` on Windows for GPU)

Example usage in modules:

```bash
if [[ "$DETECTED_OS" == "macos" ]]; then
    cpu_usage=$(top -l 1 | grep "CPU usage" | awk '{print $3}' | sed 's/%//')
else
    cpu_usage=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | sed 's/%us,//')
fi
```

## Academic Context

**Project 12th - Operating Systems Course**  
**Arab Academy for Science, Technology & Maritime Transport**  
**Member 1: Yahia Ashry (231027201)**

Demonstrates advanced bash scripting (process substitution, arrays, parallel execution), Python OOP, cross-platform compatibility, and system programming concepts.
