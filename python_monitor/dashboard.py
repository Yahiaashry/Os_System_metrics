import time
import psutil
import platform
import subprocess
import datetime
import os
import sys
from rich.live import Live
from rich.layout import Layout
from rich.panel import Panel
from rich.text import Text
from rich.table import Table
from rich import box
from rich.console import Console
from rich.progress import BarColumn, Progress, TextColumn

# --- Data Collection Functions ---

def get_cpu_info():
    usage = psutil.cpu_percent(interval=None)
    cores_logical = psutil.cpu_count(logical=True)
    cores_physical = psutil.cpu_count(logical=False)
    
    # Frequency
    try:
        freq = psutil.cpu_freq().current
        freq_str = f"{freq:.0f} MHz"
    except:
        freq_str = "N/A"

    # Load Average
    try:
        load_avg = psutil.getloadavg()
        load_str = f"{load_avg[0]:.2f}, {load_avg[1]:.2f}, {load_avg[2]:.2f}"
    except AttributeError:
        load_str = "N/A"

    # Model
    model = "Unknown"
    try:
        # Try /proc/cpuinfo
        with open("/proc/cpuinfo", "r") as f:
            for line in f:
                if "model name" in line:
                    model = line.split(":")[1].strip()
                    break
    except:
        model = platform.processor()
    
    # Temperature (Linux)
    temp_str = "N/A"
    
    # Method 1: psutil sensors
    if hasattr(psutil, "sensors_temperatures"):
        try:
            temps = psutil.sensors_temperatures()
            # Common zones
            for name in ["coretemp", "k10temp", "cpu_thermal", "thermal_zone0"]:
                if name in temps and temps[name]:
                    entries = temps[name]
                    current_temps = [t.current for t in entries]
                    if current_temps:
                        avg_temp = sum(current_temps) / len(current_temps)
                        temp_str = f"{avg_temp:.1f}°C"
                        break
        except:
            pass
            
    # Method 2: /sys/class/thermal
    if temp_str == "N/A":
        try:
            thermal_base = "/sys/class/thermal"
            if os.path.exists(thermal_base):
                for zone in os.listdir(thermal_base):
                    if zone.startswith("thermal_zone"):
                        path = os.path.join(thermal_base, zone)
                        try:
                            with open(os.path.join(path, "type"), "r") as f:
                                t_type = f.read().strip()
                            if "acpitz" in t_type or "x86_pkg_temp" in t_type or "cpu" in t_type:
                                with open(os.path.join(path, "temp"), "r") as f:
                                    temp_mC = int(f.read().strip())
                                    temp_str = f"{temp_mC/1000:.1f}°C"
                                    break
                        except:
                            continue
        except:
            pass
            
    return {
        "usage": usage,
        "cores": f"{cores_logical} ({cores_physical} phys)",
        "freq": freq_str,
        "load": load_str,
        "model": model,
        "temp": temp_str
    }

def get_memory_info():
    mem = psutil.virtual_memory()
    
    # Calculate buffers/cache if available (Linux)
    buffers_cache = 0
    if hasattr(mem, 'buffers') and hasattr(mem, 'cached'):
        buffers_cache = mem.buffers + mem.cached
    
    return {
        "total": mem.total,
        "available": mem.available,
        "used": mem.used,
        "percent": mem.percent,
        "buffers_cache": buffers_cache
    }

def get_disk_info():
    partitions = psutil.disk_partitions()
    disks = []
    for p in partitions:
        try:
            usage = psutil.disk_usage(p.mountpoint)
            disks.append({
                "device": p.device,
                "mountpoint": p.mountpoint,
                "total": usage.total,
                "used": usage.used,
                "percent": usage.percent
            })
        except PermissionError:
            continue
    return disks

class NetworkTracker:
    def __init__(self):
        self.last_net_io = psutil.net_io_counters(pernic=True)
        self.last_time = time.time()
        self.cached_ssid = "N/A"
        self.cached_iface_name = "N/A"
        self.cached_ipv4 = "N/A" # Changed to just string to match format
        self.cached_ipv6 = "No IPv6"
        self.first_call = True  # Skip first measurement for accurate rates
        self._update_static_info()

    def _update_static_info(self):
        # Determine "primary" interface to show
        # Logic: Find interface with default gateway or just first active one with IP
        # Prioritize interfaces with actual network activity
        stats = psutil.net_if_stats()
        addrs = psutil.net_if_addrs()
        
        target_iface = None
        
        # First pass: Look for interfaces with IPv4 and that are UP
        for iface, addr_list in addrs.items():
            if iface in stats and stats[iface].isup:
                # Check for non-loopback IPv4
                for addr in addr_list:
                    if addr.family == 2 and not addr.address.startswith("127."):
                        # Prioritize eth/wlan/vEthernet interfaces
                        if any(x in iface.lower() for x in ['eth', 'wlan', 'veth', 'en', 'wl']):
                            target_iface = iface
                            break
                if target_iface:
                    break
        
        # Second pass: if no priority interface found, use first active interface with IPv4
        if not target_iface:
            for iface, addr_list in addrs.items():
                if iface in stats and stats[iface].isup:
                    for addr in addr_list:
                        if addr.family == 2 and not addr.address.startswith("127."):
                            target_iface = iface
                            break
                if target_iface:
                    break
        
        # Fallback if no specific target found
        if not target_iface and addrs:
            # Find first UP interface
            for iface in addrs.keys():
                if iface in stats and stats[iface].isup:
                    target_iface = iface
                    break
            # Last resort: use any interface
            if not target_iface:
                target_iface = list(addrs.keys())[0]

        self.cached_iface_name = target_iface if target_iface else "Unknown"

        if target_iface and target_iface in addrs:
            # IPs
            for addr in addrs[target_iface]:
                if addr.family == 2: # AF_INET
                    self.cached_ipv4 = addr.address
                elif addr.family == 23: # AF_INET6
                    self.cached_ipv6 = addr.address.split('%')[0] # Remove scope ID if present

             # SSID (Windows)
            if platform.system() == "Windows":
                 try:
                     # This command "netsh wlan show interfaces" usually gives current connection
                     out = subprocess.check_output("netsh wlan show interfaces", encoding="utf-8", errors="ignore")
                     for line in out.splitlines():
                         if "SSID" in line and "BSSID" not in line:
                             # Format: "    SSID                   : MyNetwork"
                             parts = line.split(":", 1)
                             if len(parts) > 1:
                                 self.cached_ssid = parts[1].strip()
                                 break
                 except:
                     pass

    def get_metrics(self):
        current_time = time.time()
        
        try:
            current_net_io = psutil.net_io_counters(pernic=True)
        except Exception as e:
            # Fallback if per-interface data unavailable
            return {
                "send_rate": "0.0 Kbps",
                "recv_rate": "0.0 Kbps",
                "adapter": "Unknown",
                "ssid": self.cached_ssid,
                "ipv4": self.cached_ipv4,
                "ipv6": self.cached_ipv6
            }
        
        duration = current_time - self.last_time
        
        # On first call, initialize and return zero rates
        if self.first_call:
            self.first_call = False
            self.last_net_io = current_net_io
            self.last_time = current_time
            rx_kbs = 0.0
            tx_kbs = 0.0
        else:
            # Ensure minimum time window of 0.1 seconds for accurate readings
            if duration < 0.1:
                duration = 0.1
            elif duration <= 0:
                duration = 1

            # Use cached target interface
            iface = self.cached_iface_name
            
            rx_kbs = 0.0
            tx_kbs = 0.0
            
            # Try to get metrics for the interface
            try:
                if iface and iface in current_net_io and iface in self.last_net_io:
                    cur = current_net_io[iface]
                    last = self.last_net_io[iface]
                    
                    # Calculate bytes transferred
                    bytes_recv_delta = cur.bytes_recv - last.bytes_recv
                    bytes_sent_delta = cur.bytes_sent - last.bytes_sent
                    
                    # Convert to Kbps: (bytes * 8 bits/byte) / (seconds * 1000 bits/Kbit)
                    rx_kbs = (bytes_recv_delta * 8) / (duration * 1000)
                    tx_kbs = (bytes_sent_delta * 8) / (duration * 1000)
                    
                    # Ensure non-negative values
                    rx_kbs = max(0, rx_kbs)
                    tx_kbs = max(0, tx_kbs)
                else:
                    # If primary interface not found, try to find any active interface
                    for iface_name in current_net_io.keys():
                        if iface_name in self.last_net_io:
                            try:
                                cur = current_net_io[iface_name]
                                last = self.last_net_io[iface_name]
                                
                                bytes_recv_delta = cur.bytes_recv - last.bytes_recv
                                bytes_sent_delta = cur.bytes_sent - last.bytes_sent
                                
                                if bytes_recv_delta != 0 or bytes_sent_delta != 0:
                                    rx_kbs = (bytes_recv_delta * 8) / (duration * 1000)
                                    tx_kbs = (bytes_sent_delta * 8) / (duration * 1000)
                                    rx_kbs = max(0, rx_kbs)
                                    tx_kbs = max(0, tx_kbs)
                                    self.cached_iface_name = iface_name
                                    break
                            except:
                                continue
            except Exception as e:
                rx_kbs = 0.0
                tx_kbs = 0.0
            
            self.last_net_io = current_net_io
            self.last_time = current_time
        
        return {
            "send_rate": f"{tx_kbs:.1f} Kbps",
            "recv_rate": f"{rx_kbs:.1f} Kbps",
            "adapter": self.cached_iface_name,
            "ssid": self.cached_ssid,
            "ipv4": self.cached_ipv4,
            "ipv6": self.cached_ipv6
        }

def get_network_info():
    # Keep the original one for Total stats if needed, or just remove if we replace usage
    net_io = psutil.net_io_counters()
    
    return {
        "total_rx": net_io.bytes_recv,
        "total_tx": net_io.bytes_sent
    }

def get_gpu_info():
    gpu_data = {
        "model": "Unknown",
        "temp": "N/A",
        "usage": 0,
        "memory_used": 0,
        "memory_total": 0,
        "type": "N/A"
    }

    # 1. Try NVIDIA-SMI first (Best for NVIDIA)
    nvidia_found = False
    try:
        output = subprocess.check_output(
            ["nvidia-smi", "--query-gpu=name,utilization.gpu,temperature.gpu,memory.used,memory.total", "--format=csv,noheader,nounits"],
            encoding='utf-8',
            stderr=subprocess.DEVNULL
        )
        line = output.strip().split('\n')[0]
        parts = [x.strip() for x in line.split(',')]
        if len(parts) >= 5:
            gpu_data["model"] = parts[0]
            gpu_data["usage"] = float(parts[1])
            gpu_data["temp"] = f"{parts[2]}°C"
            gpu_data["memory_used"] = float(parts[3])
            gpu_data["memory_total"] = float(parts[4])
            gpu_data["type"] = "Dedicated (NVIDIA)"
            nvidia_found = True
    except (FileNotFoundError, subprocess.CalledProcessError):
        pass

    if nvidia_found:
        return gpu_data

    # 2. Fallback: lshw (Good for Intel/AMD detection)
    # Note: Usage/Temp often unavailable for these in Docker/WSL without specific passthrough
    try:
        # -C display gives json output
        lshw_out = subprocess.check_output(["lshw", "-C", "display", "-json"], encoding="utf-8", stderr=subprocess.DEVNULL)
        import json
        
        # lshw can return a dict or list of dicts
        try:
            data = json.loads(lshw_out)
            if isinstance(data, dict):
                data = [data]
            
            for device in data:
                # Look for display controller
                if "display" in device.get("id", "") or "display" in device.get("class", ""):
                    gpu_data["model"] = f"{device.get('vendor', '')} {device.get('product', '')}".strip()
                    gpu_data["type"] = "Integrated/Other"
                    gpu_data["usage"] = "N/A" # Cannot easily get usage in container for non-NVIDIA
                    flag_found = True
                    break
        except json.JSONDecodeError:
            pass
    except (FileNotFoundError, subprocess.CalledProcessError):
        pass

    # 3. Last Resort: lspci (Basic detection)
    if gpu_data["model"] == "Unknown":
        try:
             lspci_out = subprocess.check_output(["lspci"], encoding="utf-8", stderr=subprocess.DEVNULL)
             for line in lspci_out.splitlines():
                 if "VGA" in line or "3D controller" in line or "Display controller" in line:
                     # e.g., 00:02.0 VGA compatible controller: Intel Corporation...
                     fullname = line.split(":", 2)[-1].strip()
                     # Clean up common prefixes
                     if "Microsoft Corporation" in fullname:
                         gpu_data["model"] = "Microsoft Basic Render Driver (WSL)"
                     else:
                         gpu_data["model"] = fullname
                     
                     gpu_data["type"] = "Integrated/Other"
                     gpu_data["usage"] = "N/A"
                     break
        except:
             pass

    return gpu_data

def get_system_info():
    boot_time = datetime.datetime.fromtimestamp(psutil.boot_time())
    uptime = datetime.datetime.now() - boot_time
    # Format uptime
    days = uptime.days
    hours, remainder = divmod(uptime.seconds, 3600)
    minutes, seconds = divmod(remainder, 60)
    uptime_str = f"{days}d {hours}h {minutes}m"
    
    distro = "Linux"
    try:
        with open("/etc/os-release") as f:
            for line in f:
                if line.startswith("PRETTY_NAME="):
                    distro = line.split("=", 1)[1].strip().strip('"')
                    break
    except:
        pass
    
    return {
        "uptime": uptime_str,
        "processes": len(psutil.pids()),
        "users": len(psutil.users()),
        "distro": distro
    }

# --- Formatting Utils ---

def sizeof_fmt(num, suffix="B"):
    for unit in ["", "Ki", "Mi", "Gi", "Ti", "Pi", "Ei", "Zi"]:
        if abs(num) < 1024.0:
            return f"{num:3.1f} {unit}{suffix}"
        num /= 1024.0
    return f"{num:.1f} Yi{suffix}"

def create_bar(percent, width=20, color="green"):
    completed = int(width * (percent / 100))
    bar = "█" * completed + "░" * (width - completed)
    return f"[{color}]{bar}[/{color}]"

# --- UI Components ---

def make_header():
    grid = Table.grid(expand=True)
    grid.add_column(justify="center", ratio=1)
    title = f"SYSTEM MONITOR DASHBOARD - {platform.node()} ({platform.system().lower()}) - {datetime.datetime.now().strftime('%Y-%m-%dT%H:%M:%SZ')}"
    grid.add_row(Text(title, style="bold white on blue", justify="center"))
    return grid

def make_cpu_panel(cpu_data):
    # Content
    grid = Table.grid(padding=(0,1))
    grid.add_column(style="cyan", justify="left")
    grid.add_column(style="white", justify="left")
    
    # Usage Bar
    bar = create_bar(cpu_data['usage'], width=10, color="green" if cpu_data['usage'] < 80 else "red")
    
    grid.add_row("Usage:", f"{cpu_data['usage']}% {bar}")
    grid.add_row("Load:", str(cpu_data['load']))
    grid.add_row("Cores:", str(cpu_data['cores']))
    grid.add_row("Model:", str(cpu_data['model']))
    grid.add_row("Temp:", str(cpu_data['temp']))
    
    return Panel(
        grid,
        title="[cyan]CPU METRICS[/cyan]",
        border_style="cyan",
        box=box.ROUNDED
    )

def make_system_load_panel(sys_data):
    # System Load panel
    grid = Table.grid(padding=(0,1))
    grid.add_column(style="yellow", justify="left")
    grid.add_column(style="white", justify="left")
    
    grid.add_row("Uptime:", sys_data['uptime'])
    grid.add_row("Processes:", str(sys_data['processes']))
    grid.add_row("Users:", str(sys_data['users']))
    
    return Panel(
        grid,
        title="[yellow]SYSTEM LOAD[/yellow]",
        border_style="yellow",
        box=box.ROUNDED
    )

def make_memory_panel(mem_data):
    grid = Table.grid(padding=(0,1))
    grid.add_column(style="cyan", justify="left")
    grid.add_column(style="white", justify="left")
    
    total_gb = mem_data['total'] / (1024**3)
    used_gb = mem_data['used'] / (1024**3)
    free_gb = mem_data['available'] / (1024**3)
    
    bar = create_bar(mem_data['percent'], width=10, color="green" if mem_data['percent'] < 80 else "red")
    
    grid.add_row("Used:", f"{used_gb:.2f} GB / {total_gb:.2f} GB")
    grid.add_row("Usage:", f"{mem_data['percent']}% {bar}")
    grid.add_row("Free:", f"{free_gb:.2f} GB")
    
    return Panel(
        grid,
        title="[green]MEMORY[/green]",
        border_style="green",
        box=box.ROUNDED
    )

def make_gpu_panel(gpu_data):
    grid = Table.grid(padding=(0,1))
    grid.add_column(style="cyan", justify="left")
    grid.add_column(style="white", justify="left")
    
    grid.add_row("Temp:", gpu_data['temp'])
    grid.add_row("Vendor:", "NVIDIA" if "NVIDIA" in gpu_data.get('type', '') else "Unknown")
    grid.add_row("Model:", gpu_data['model'])
    grid.add_row("Type:", gpu_data['type'])
    
    # VRAM
    if gpu_data['memory_total'] > 0:
        vram_str = f"{gpu_data['memory_used']/1024:.1f} / {gpu_data['memory_total']/1024:.1f} GB"
        vram_bar = create_bar((gpu_data['memory_used']/gpu_data['memory_total'])*100, width=10)
    else:
        vram_str = "N/A"
        vram_bar = ""
        
    grid.add_row("VRAM:", vram_str)
    
    # Usage
    if isinstance(gpu_data['usage'], (int, float)):
        usage_bar = create_bar(gpu_data['usage'], width=10)
        grid.add_row("Usage:", f"{gpu_data['usage']}% {usage_bar}")
    else:
        grid.add_row("Usage:", "N/A")

    return Panel(
        grid,
        title="[blue]GPU[/blue]",
        border_style="blue",
        box=box.ROUNDED
    )

def make_disk_panel(disks):
    table = Table(box=None, padding=(0,1), show_header=True, header_style="bold white")
    table.add_column("Device", style="cyan")
    table.add_column("Usage", style="yellow")
    table.add_column("Used/Total", style="white")
    table.add_column("Bar", style="white")
    
    for d in disks[:3]: # Limit to top 3 to fit
        total_gb = d['total'] / (1024**3)
        used_gb = d['used'] / (1024**3)
        bar = create_bar(d['percent'], width=10, color="yellow")
        table.add_row(
            d['device'],
            f"{d['percent']}%",
            f"{used_gb:.1f}/{total_gb:.1f} GB",
            bar
        )
    
    return Panel(
        table,
        title="[magenta]DISK[/magenta]",
        border_style="magenta",
        box=box.ROUNDED
    )

def make_network_panel(net_data):
    grid = Table.grid(padding=(0,1))
    grid.add_column(style="cyan", justify="left")
    grid.add_column(style="white", justify="left")
    
    grid.add_row("Total RX:", sizeof_fmt(net_data['total_rx']))
    grid.add_row("Total TX:", sizeof_fmt(net_data['total_tx']))
    grid.add_row(" ", " ")
    
    # Interface Details (Top 2 active maybe?)
    # Just list specific ones if possible or all
    sub_table = Table(box=None, show_header=True, header_style="bold white")
    sub_table.add_column("Interface", style="white")
    sub_table.add_column("RX", style="green")
    sub_table.add_column("TX", style="yellow")
    
    sorted_ifaces = sorted(net_data['interfaces'], key=lambda x: x['rx'] + x['tx'], reverse=True)
    
    for iface in sorted_ifaces[:2]:
        sub_table.add_row(
            iface['name'][:10], # Truncate
            sizeof_fmt(iface['rx']),
            sizeof_fmt(iface['tx'])
        )
    
    return Panel(
        Group(grid, sub_table),
        title="[cyan]NETWORK[/cyan]",
        border_style="cyan",
        box=box.ROUNDED
    )

from rich.console import Group

def make_layout():
    layout = Layout()
    layout.split(
        Layout(name="header", size=3),
        Layout(name="main", ratio=1),
        Layout(name="footer", size=3)
    )
    
    layout["main"].split_row(
        Layout(name="left"),
        Layout(name="right")
    )
    
    layout["left"].split(
        Layout(name="cpu", ratio=1),
        Layout(name="system", ratio=1),
        Layout(name="disk", ratio=1)
    )
    
    layout["right"].split(
        Layout(name="memory", ratio=1),
        Layout(name="gpu", ratio=1),
        Layout(name="network", ratio=1)
    )
    
    return layout

    
def make_detailed_network_panel(net_metrics):
    grid = Table.grid(padding=(0,1))
    grid.add_column(style="cyan", justify="left")
    grid.add_column(style="white", justify="left")
    
    grid.add_row("send:", net_metrics['send_rate'])
    grid.add_row("receive:", net_metrics['recv_rate'])
    grid.add_row("adapter Name:", net_metrics['adapter'])
    grid.add_row("SSID:", net_metrics['ssid'])
    grid.add_row("IPv4:", net_metrics['ipv4'])
    grid.add_row("IPv6:", net_metrics['ipv6'])
    
    return Panel(
        grid,
        title="[cyan]NETWORK METRICS[/cyan]",
        border_style="cyan",
        box=box.ROUNDED
    )

def update_layout(layout, net_tracker):
    cpu_data = get_cpu_info()
    mem_data = get_memory_info()
    disk_data = get_disk_info()
    gpu_data = get_gpu_info()
    net_data = get_network_info()
    sys_data = get_system_info()
    
    # Get detailed network metrics
    net_detailed = net_tracker.get_metrics()
    
    layout["header"].update(make_header())
    
    layout["left"]["cpu"].update(make_cpu_panel(cpu_data))
    layout["left"]["system"].update(make_system_load_panel(sys_data))
    layout["left"]["disk"].update(make_disk_panel(disk_data))
    
    layout["right"]["memory"].update(make_memory_panel(mem_data))
    layout["right"]["gpu"].update(make_gpu_panel(gpu_data))
    
    layout["right"]["network"].update(make_detailed_network_panel(net_detailed))
    
    # Footer
    layout["footer"].update(Panel(Text("INFO System monitoring initialized - Press Ctrl+C to exit", style="bold white"), title="ALERTS (1)", border_style="yellow"))

def main():
    import argparse
    parser = argparse.ArgumentParser()
    parser.add_argument("--duration", type=int, help="Run for N seconds then exit", default=None)
    parser.add_argument("--interval", type=float, help="Refresh interval in seconds", default=5.0)
    args = parser.parse_args()

    console = Console()
    layout = make_layout()
    
    net_tracker = NetworkTracker() # Initialize tracker
    start_time = time.time()
    
    with Live(layout, refresh_per_second=4, screen=True) as live:
        while True:
            update_layout(layout, net_tracker)
            if args.duration and (time.time() - start_time > args.duration):
                break
            time.sleep(args.interval)

if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        print("Exiting...")
