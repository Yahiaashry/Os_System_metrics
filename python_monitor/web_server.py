from flask import Flask, jsonify, render_template
from flask_cors import CORS
import dashboard
import time
import threading
import subprocess
import platform
import json
import psutil # Added for CPUTracker

app = Flask(__name__)
CORS(app)  # Enable CORS for all routes
print("Web Server starting... using dashboard logic.")

# --- Background Trackers ---

class CPUTracker:
    def __init__(self):
        self.usage = 0
        self.lock = threading.Lock()
        # Start immediately
        threading.Thread(target=self._monitor_loop, daemon=True).start()

    def _monitor_loop(self):
        while True:
            # interval=1 blocks for 1 second, providing a stable average
            val = psutil.cpu_percent(interval=1)
            with self.lock:
                self.usage = val
    
    def get_usage(self):
        with self.lock:
            return self.usage

# Initialize Trackers
net_tracker = dashboard.NetworkTracker()
cpu_tracker = CPUTracker() # New CPU Tracker

# Pre-warm the network tracker with an initial measurement
def warm_up_network_tracker():
    """Allow network tracker to establish baseline"""
    time.sleep(1.0)  # Wait for network activity
    net_tracker.get_metrics()  # Initialize with real data
    print("Network tracker warmed up")


# Start warm-up in background thread
threading.Thread(target=warm_up_network_tracker, daemon=True).start()

# --- Visualization Logic ---
import webbrowser
import os

def open_visualization():
    """Starts backend services and opens React frontend."""
    print("Preparing visualization environment...")
    
    # Paths (Relative to project root, assuming web_server is running from project root or python_monitor)
    # Adjusting based on current CWD assumption (12thprojectos or 12thprojectos/python_monitor)
    base_dir = os.path.dirname(os.path.abspath(__file__)) # python_monitor/
    root_dir = os.path.dirname(base_dir) # 12thprojectos/
    
    api_script = os.path.join(base_dir, "backend", "api_server.py")
    writer_script = os.path.join(base_dir, "backend", "metrics_writer.py")
    frontend_dir = os.path.join(root_dir, "react", "frontend")
    
    # 1. Start Backend API (on port 5000)
    try:
        subprocess.Popen(["python", api_script], cwd=root_dir)
        print("Backend API started.")
    except Exception as e:
        print(f"Failed to start API: {e}")

    # 2. Start Metrics Writer
    try:
        subprocess.Popen(["python", writer_script], cwd=root_dir)
        print("Metrics Writer started.")
    except Exception as e:
        print(f"Failed to start Metrics Writer: {e}")

    # 3. Open Browser to Frontend (Assuming npm start is running manually or via script)
    # Ideally, we would start npm start too, but that's complex from Python.
    # We will assume the user has run the setup script or npm start.
    webbrowser.open("http://localhost:3000")
    print("Opening visualization in browser...")

@app.route('/open-visualization')
def route_open_viz():
    # Trigger the visualization logic via web request
    open_visualization()
    return "Visualization environment launched! Check your browser and other windows."


@app.route('/')
def home():
    return render_template('index.html')

@app.route('/api/metrics')
def get_metrics():
    # Update metrics on request
    cpu_data = dashboard.get_cpu_info()
    # Override unstable usage with stable background tracker value
    cpu_data['usage'] = cpu_tracker.get_usage() 
    
    mem_data = dashboard.get_memory_info()
    disk_data = dashboard.get_disk_info()
    gpu_data = dashboard.get_gpu_info()
    net_data = dashboard.get_network_info() # Basic totals
    sys_data = dashboard.get_system_info()
    
    # Detailed network metrics from tracker
    net_detailed = net_tracker.get_metrics()
    
    return jsonify({
        "cpu": cpu_data,
        "memory": mem_data,
        "disk": disk_data,
        "gpu": gpu_data,
        "network": {
            "totals": net_data,
            "detailed": net_detailed
        },
        "system": sys_data
    })

if __name__ == '__main__':
    app.run(debug=True, host='0.0.0.0', port=8080)
