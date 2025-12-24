# System Monitoring Solution - Installation Guide

## Project Information

- **Project**: 12th Operating Systems Project - Arab Academy
- **Member**: Yahia Ashry (231027201)
- **Components**: Bash Scripting + Advanced Python Monitoring

---

## System Requirements

### Minimum Requirements

- **OS**: Linux (Ubuntu/Debian/RHEL/CentOS), macOS 10.14+, or Windows WSL2
- **RAM**: 512 MB available
- **Disk**: 100 MB free space
- **Python**: 3.7 or higher
- **Bash**: 4.0 or higher

### Recommended Requirements

- **RAM**: 1 GB available
- **Disk**: 500 MB free space
- **Python**: 3.9 or higher
- **Bash**: 5.0 or higher

---

## Installation Instructions

### Ubuntu/Debian Linux

```bash
# 1. Update package lists
sudo apt-get update

# 2. Install system dependencies
sudo apt-get install -y python3 python3-pip python3-venv \
    bc jq curl git lm-sensors sysstat net-tools

# 3. Clone or navigate to project directory
cd /path/to/12thprojectos

# 4. Run the installation script
chmod +x integration/bridge.sh
./integration/bridge.sh install

# 5. Verify installation
./integration/bridge.sh health
```

### RHEL/CentOS/Fedora Linux

```bash
# 1. Install system dependencies
sudo dnf install -y python3 python3-pip bc jq curl git \
    lm_sensors sysstat net-tools

# Or for older versions (CentOS 7):
sudo yum install -y python3 python3-pip bc jq curl git \
    lm_sensors sysstat net-tools

# 2. Navigate to project
cd /path/to/12thprojectos

# 3. Run installation
chmod +x integration/bridge.sh
./integration/bridge.sh install

# 4. Verify
./integration/bridge.sh health
```

### macOS

```bash
# 1. Install Homebrew (if not installed)
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

# 2. Install dependencies
brew install python bc jq curl git

# Optional: Install temperature monitoring tools
brew install osx-cpu-temp iStats

# 3. Navigate to project
cd /path/to/12thprojectos

# 4. Run installation
chmod +x integration/bridge.sh
./integration/bridge.sh install

# 5. Verify
./integration/bridge.sh health
```

### Windows WSL (Ubuntu)

```powershell
# 1. Install WSL2 (if not already installed)
wsl --install -d Ubuntu

# 2. Open Ubuntu terminal and update
sudo apt-get update
sudo apt-get upgrade -y

# 3. Install dependencies
sudo apt-get install -y python3 python3-pip python3-venv \
    bc jq curl git

# 4. Clone or navigate to project
cd /mnt/c/path/to/12thprojectos
# Or if using WSL filesystem:
cd ~/12thprojectos

# 5. Run installation
chmod +x integration/bridge.sh
./integration/bridge.sh install

# 6. Verify
./integration/bridge.sh health
```

---

## Manual Python Setup

If automatic installation fails:

```bash
# Create virtual environment
python3 -m venv python_monitor/venv

# Activate virtual environment
source python_monitor/venv/bin/activate  # Linux/macOS
# OR
python_monitor\venv\Scripts\activate  # Windows

# Install Python packages
pip install --upgrade pip
pip install -r python_monitor/requirements.txt

# Verify installation
python3 -c "import psutil; print('psutil OK')"
python3 -c "import GPUtil; print('GPUtil OK')"
```

---

## Optional Components

### GPU Monitoring (NVIDIA)

```bash
# Install NVIDIA drivers and CUDA toolkit (if not installed)
# Ubuntu:
sudo ubuntu-drivers autoinstall

# Install nvidia-smi
sudo apt-get install nvidia-utils-<version>

# Verify
nvidia-smi
```

### Temperature Sensors (Linux)

```bash
# Install and configure lm-sensors
sudo apt-get install lm-sensors
sudo sensors-detect --auto
sensors
```

### Enhanced Network Monitoring

```bash
# Install additional network tools
sudo apt-get install -y iftop nethogs tcpdump wireshark-common
```

---

## Troubleshooting

### Permission Issues

```bash
# Give execute permissions to all scripts
find system_monitor -name "*.sh" -exec chmod +x {} \;
chmod +x integration/bridge.sh
```

### Python Import Errors

```bash
# Ensure virtual environment is activated
source python_monitor/venv/bin/activate

# Reinstall dependencies
pip install --force-reinstall -r python_monitor/requirements.txt
```

### Missing Commands

```bash
# Check which commands are missing
for cmd in python3 bc jq curl; do
    command -v $cmd &>/dev/null && echo "$cmd: OK" || echo "$cmd: MISSING"
done

# Install missing commands as needed
```

### WSL-Specific Issues

```bash
# If /proc/stat is not accessible
sudo mount -t proc proc /proc

# If sensors don't work in WSL
# Note: Temperature sensors may not be available in WSL
# Use Windows tools instead or run on native Linux
```

---

## Verification

After installation, verify everything works:

```bash
# Run health check
./integration/bridge.sh health

# Test bash monitoring
./integration/bridge.sh bash

# Test Python monitoring
./integration/bridge.sh python collect --output summary

# Test integrated monitoring
./integration/bridge.sh integrated
```

Expected output should show:

- ✓ All scripts found
- ✓ Python 3.x detected
- ✓ All system dependencies available
- ✓ Python packages installed
- ✓ Metrics collected successfully

---

## Next Steps

After installation:

1. Review configuration in `config/monitor.yaml`
2. Read `docs/USAGE.md` for usage examples
3. Set up alerts if needed (email/webhook)
4. Configure database retention policies
5. Set up continuous monitoring (systemd/cron)

---

## Support

For issues or questions:

- Check `docs/USAGE.md` for usage guide
- Review log files in `system_monitor/logs/`
- Check Python logs in `python_monitor/*.log`
- Review project documentation

---

**Installation complete! You can now start monitoring your system.**
