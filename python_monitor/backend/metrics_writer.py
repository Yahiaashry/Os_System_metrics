import json
import time
import os
import psutil
from datetime import datetime

# Path to shared metrics file
METRICS_FILE = os.path.join(os.path.dirname(__file__), '..', 'shared', 'metrics.json')

def collect_metrics():
    """Collects system metrics."""
    cpu_percent = psutil.cpu_percent(interval=1)
    memory = psutil.virtual_memory()
    disk = psutil.disk_usage('/')
    
    return {
        "timestamp": datetime.now().isoformat(),
        "cpu": {
            "usage": cpu_percent,
            "cores": psutil.cpu_count(logical=True)
        },
        "memory": {
            "total": memory.total,
            "used": memory.used,
            "percent": memory.percent
        },
        "disk": {
            "total": disk.total,
            "used": disk.used,
            "percent": disk.percent
        }
    }

def write_metrics_loop(interval=2):
    """Continuously writes metrics to JSON file."""
    os.makedirs(os.path.dirname(METRICS_FILE), exist_ok=True)
    print(f"Starting metrics writer... Output: {METRICS_FILE}")
    
    while True:
        try:
            metrics = collect_metrics()
            # Atomic write pattern to prevent reading partial files
            temp_file = METRICS_FILE + '.tmp'
            with open(temp_file, 'w') as f:
                json.dump(metrics, f, indent=2)
            os.replace(temp_file, METRICS_FILE)
            time.sleep(interval)
        except Exception as e:
            print(f"Error writing metrics: {e}")
            time.sleep(interval)

if __name__ == "__main__":
    write_metrics_loop()
