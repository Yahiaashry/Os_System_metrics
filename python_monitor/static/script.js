document.addEventListener('DOMContentLoaded', () => {
    let updateCount = 0;

    const updateMetrics = async () => {
        try {
            const response = await fetch('/api/metrics');
            const data = await response.json();

            // CPU
            setText('cpu-usage', `${Math.round(data.cpu.usage)}%`);
            setBar('cpu-bar', data.cpu.usage);
            setText('cpu-load', data.cpu.load);
            setText('cpu-cores', data.cpu.cores);
            setText('cpu-model', data.cpu.model);
            setText('cpu-temp', data.cpu.temp);

            // Memory
            const mem = data.memory;
            const usedGB = (mem.used / (1024 ** 3)).toFixed(2);
            const totalGB = (mem.total / (1024 ** 3)).toFixed(2);
            const freeGB = (mem.available / (1024 ** 3)).toFixed(2);
            const cacheGB = mem.buffers_cache ? (mem.buffers_cache / (1024 ** 3)).toFixed(2) : "0.00";
            
            setText('mem-used-total', `${usedGB} / ${totalGB} GB`);
            setText('mem-usage', `${Math.round(mem.percent)}%`);
            setBar('mem-bar', mem.percent);
            setText('mem-free', `${freeGB} GB`);
            if (document.getElementById('mem-cache')) {
                setText('mem-cache', `${cacheGB} GB included`);
            }

            // Disk
            const diskContent = document.getElementById('disk-content');
            if (diskContent) {
                // Clear existing only if count changes or force refresh periodically (here simplified)
                // ideally we diff contents to simply update bars, but rewriting is fine for 3 items
                diskContent.innerHTML = ''; 

                data.disk.slice(0, 3).forEach((d) => {
                    const total = (d.total / (1024 ** 3)).toFixed(1);
                    const used = (d.used / (1024 ** 3)).toFixed(1);
                    
                    const row = document.createElement('div');
                    row.className = 'disk-item';
                    
                    let barColor = 'disk-bar'; // default class
                    
                    row.innerHTML = `
                         <div class="metric-row">
                            <span class="label" style="color:var(--accent-cyan)">${d.mountpoint}</span>
                             <span class="value" style="color:var(--accent-yellow)">${d.percent}%</span>
                        </div>
                        <div class="progress-container">
                            <div class="progress-bar ${barColor}" style="width: ${d.percent}%; background-color: var(--accent-cyan); box-shadow: 0 0 5px var(--accent-cyan);"></div>
                        </div>
                         <div class="metric-row" style="margin-top:2px">
                            <span class="label" style="font-size:11px">Used/Total</span>
                             <span class="value" style="font-size:11px">${used} / ${total} GB</span>
                        </div>
                    `;
                    diskContent.appendChild(row);
                });
            }

            // GPU
            const gpu = data.gpu;
            setText('gpu-temp', gpu.temp);
            setText('gpu-vendor', gpu.type.includes('NVIDIA') ? 'NVIDIA' : (gpu.type.includes('AMD') ? 'AMD' : 'Intel'));
            setText('gpu-model', gpu.model);
            setText('gpu-type', gpu.type);

            if (gpu.memory_total > 0) {
                const vramUsed = (gpu.memory_used / 1024).toFixed(1);
                const vramTotal = (gpu.memory_total / 1024).toFixed(1);
                setText('gpu-vram', `${vramUsed} / ${vramTotal} GB`);
            } else {
                setText('gpu-vram', 'N/A');
            }

            setText('gpu-usage', `${Math.round(gpu.usage)}%`);
            setBar('gpu-bar', gpu.usage);

            // Network
            const net = data.network.detailed;
            setText('net-send', net.send_rate);
            setText('net-recv', net.recv_rate);
            setText('net-adapter', net.adapter);
            setText('net-ssid', net.ssid);
            setText('net-ipv4', net.ipv4);
            setText('net-ipv6', net.ipv6);

            // System
            setText('sys-uptime', data.system.uptime);
            setText('sys-procs', data.system.processes);
            setText('sys-users', data.system.users);
            if (data.system.distro) {
                 const distroEl = document.getElementById('sys-distro');
                 if (distroEl) distroEl.textContent = data.system.distro;
            }

            updateCount++;
        } catch (error) {
            console.error('Error fetching metrics:', error);
        }
    };

    // Utils
    const setText = (id, text) => {
        const el = document.getElementById(id);
        if (el) {
            if (el.textContent !== String(text)) {
                el.style.animation = 'none';
                el.offsetHeight; // Trigger reflow
                el.style.animation = 'pulse 0.3s ease-out';
                el.textContent = text;
            }
        }
    };

    const setBar = (id, percent) => {
        const el = document.getElementById(id);
        if (el) {
            const targetWidth = Math.min(100, Math.max(0, percent));
            el.style.width = `${targetWidth}%`;
        }
    };

    const formatBytes = (bytes) => {
        if (bytes === 0) return '0 B';
        const k = 1024;
        const sizes = ['B', 'KiB', 'MiB', 'GiB', 'TiB'];
        const i = Math.floor(Math.log(bytes) / Math.log(k));
        return parseFloat((bytes / Math.pow(k, i)).toFixed(1)) + ' ' + sizes[i];
    };

    // Add pulse animation
    const style = document.createElement('style');
    style.textContent = `
        @keyframes pulse {
            0% { opacity: 1; }
            50% { opacity: 0.7; }
            100% { opacity: 1; }
        }
        @keyframes fadeIn {
            from { opacity: 0; transform: translateX(-10px); }
            to { opacity: 1; transform: translateX(0); }
        }
    `;
    document.head.appendChild(style);

    // Update every 1 second
    setInterval(updateMetrics, 1000);
    updateMetrics(); // Initial call
});
