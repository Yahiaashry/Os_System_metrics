import React, { useState, useEffect, useMemo, useCallback } from 'react';
import {
    LineChart, Line, AreaChart, Area,
    BarChart, Bar, PieChart, Pie, Cell,
    XAxis, YAxis, CartesianGrid, Tooltip as RechartsTooltip, Legend,
    ResponsiveContainer, RadialBarChart, RadialBar,
} from 'recharts';

// ============================================================================
// THEME SYSTEM
// ============================================================================

const themes = {
    dark: {
        bg: '#1a1b26',
        cardBg: '#24283b',
        textPrimary: '#a9b1d6',
        textSecondary: '#565f89',
        accent: '#7aa2f7',
        success: '#9ece6a',
        warning: '#e0af68',
        danger: '#f7768e',
        grid: '#2f3549',
    },
    light: {
        bg: '#f5f7fa',
        cardBg: '#ffffff',
        textPrimary: '#2c3e50',
        textSecondary: '#7f8c8d',
        accent: '#3498db',
        success: '#27ae60',
        warning: '#f39c12',
        danger: '#e74c3c',
        grid: '#ecf0f1',
    },
};

// ============================================================================
// CUSTOM HOOKS
// ============================================================================

// Theme Hook
const useTheme = () => {
    const [theme, setTheme] = useState(() => {
        const saved = localStorage.getItem('theme-preference');
        return saved || 'dark';
    });

    const toggleTheme = useCallback(() => {
        setTheme(prev => {
            const next = prev === 'dark' ? 'light' : 'dark';
            localStorage.setItem('theme-preference', next);
            return next;
        });
    }, []);

    return { theme: themes[theme], themeName: theme, toggleTheme };
};

// LocalStorage Hook
const useLocalStorage = (key, initialValue) => {
    const [storedValue, setStoredValue] = useState(() => {
        try {
            const item = window.localStorage.getItem(key);
            return item ? JSON.parse(item) : initialValue;
        } catch (error) {
            console.error('Error loading from localStorage:', error);
            return initialValue;
        }
    });

    const setValue = useCallback((value) => {
        try {
            const valueToStore = value instanceof Function ? value(storedValue) : value;
            setStoredValue(valueToStore);
            window.localStorage.setItem(key, JSON.stringify(valueToStore));
        } catch (error) {
            console.error('Error saving to localStorage:', error);
        }
    }, [key, storedValue]);

    return [storedValue, setValue];
};

// Backend Metrics Hook
const useBackendMetrics = (apiUrl, refreshInterval) => {
    const [data, setData] = useState(null);
    const [history, setHistory] = useLocalStorage('system-metrics-history', {
        version: '1.0',
        maxPoints: 500,
        data: [],
    });
    const [connectionStatus, setConnectionStatus] = useState('connecting');
    const [lastUpdated, setLastUpdated] = useState(null);
    const [latencies, setLatencies] = useState([]);
    const [error, setError] = useState(null);

    // Fetch from backend
    const fetchMetrics = useCallback(async () => {
        const startTime = performance.now();
        try {
            const response = await fetch(apiUrl, {
                signal: AbortSignal.timeout(10000),
            });

            if (!response.ok) throw new Error(`HTTP ${response.status}: ${response.statusText}`);

            const jsonData = await response.json();
            const latency = performance.now() - startTime;

            setData(jsonData);
            setConnectionStatus('connected');
            setLastUpdated(new Date());
            setLatencies(prev => [...prev.slice(-99), latency]);
            setError(null);

            return jsonData;
        } catch (err) {
            console.error('Backend connection failed:', err.message);
            setConnectionStatus('disconnected');
            setError(err.message);
            return null;
        }
    }, [apiUrl]);

    // Update history
    const updateHistory = useCallback((metricsData) => {
        if (!metricsData) return;

        const timeStr = new Date().toLocaleTimeString([], { hour12: false });

        // Parse network rates
        const parseRate = (rateStr) => {
            if (!rateStr) return 0;
            const match = rateStr.match(/([\d.]+)\s*(\w+)/);
            if (!match) return 0;
            const value = parseFloat(match[1]);
            const unit = match[2].toLowerCase();
            // Convert to Mbps
            if (unit.includes('kbps')) return value / 1000;
            if (unit.includes('mbps')) return value;
            if (unit.includes('gbps')) return value * 1000;
            return value;
        };

        const newPoint = {
            time: timeStr,
            cpu: metricsData.cpu?.usage || 0,
            memory: metricsData.memory?.percent || 0,
            netIn: parseRate(metricsData.network?.detailed?.recv_rate),
            netOut: parseRate(metricsData.network?.detailed?.send_rate),
            diskRead: Math.random() * 100, // Mock for now
            diskWrite: Math.random() * 50,
        };

        setHistory(prev => {
            const newData = [...prev.data, newPoint].slice(-prev.maxPoints);
            return { ...prev, data: newData, lastUpdated: new Date().toISOString() };
        });
    }, [setHistory]);

    // Initial fetch and interval
    useEffect(() => {
        fetchMetrics().then(updateHistory);

        const interval = setInterval(() => {
            fetchMetrics().then(updateHistory);
        }, refreshInterval);

        return () => clearInterval(interval);
    }, [fetchMetrics, updateHistory, refreshInterval]);

    return {
        current: data,
        history: history.data,
        connectionStatus,
        lastUpdated,
        latencies,
        error,
        refetch: fetchMetrics,
        clearHistory: () => setHistory({ version: '1.0', maxPoints: 500, data: [] }),
    };
};

// Alerts Hook
const useAlerts = (current, thresholds) => {
    const [alerts, setAlerts] = useState([]);
    const [alertHistory, setAlertHistory] = useState([]);
    const [notificationCooldowns, setNotificationCooldowns] = useState({});

    useEffect(() => {
        if (!current) return;

        const newAlerts = [];
        const now = Date.now();

        // CPU Alert
        if (current.cpu?.usage > thresholds.cpu.danger) {
            newAlerts.push({
                id: 'cpu-danger',
                metric: 'CPU',
                level: 'danger',
                message: `CPU usage critical: ${current.cpu.usage.toFixed(1)}%`,
                value: current.cpu.usage,
            });
        } else if (current.cpu?.usage > thresholds.cpu.warning) {
            newAlerts.push({
                id: 'cpu-warning',
                metric: 'CPU',
                level: 'warning',
                message: `CPU usage high: ${current.cpu.usage.toFixed(1)}%`,
                value: current.cpu.usage,
            });
        }

        // Memory Alert
        if (current.memory?.percent > thresholds.memory.danger) {
            newAlerts.push({
                id: 'memory-danger',
                metric: 'Memory',
                level: 'danger',
                message: `Memory usage critical: ${current.memory.percent.toFixed(1)}%`,
                value: current.memory.percent,
            });
        } else if (current.memory?.percent > thresholds.memory.warning) {
            newAlerts.push({
                id: 'memory-warning',
                metric: 'Memory',
                level: 'warning',
                message: `Memory usage high: ${current.memory.percent.toFixed(1)}%`,
                value: current.memory.percent,
            });
        }

        // Disk Alert
        if (current.disk?.[0]?.percent > thresholds.disk.danger) {
            newAlerts.push({
                id: 'disk-danger',
                metric: 'Disk',
                level: 'danger',
                message: `Disk usage critical: ${current.disk[0].percent.toFixed(1)}%`,
                value: current.disk[0].percent,
            });
        } else if (current.disk?.[0]?.percent > thresholds.disk.warning) {
            newAlerts.push({
                id: 'disk-warning',
                metric: 'Disk',
                level: 'warning',
                message: `Disk usage high: ${current.disk[0].percent.toFixed(1)}%`,
                value: current.disk[0].percent,
            });
        }

        setAlerts(newAlerts);

        // Browser notifications (with cooldown)
        newAlerts.forEach(alert => {
            const lastNotification = notificationCooldowns[alert.id];
            const cooldownPeriod = 5 * 60 * 1000; // 5 minutes

            if (!lastNotification || now - lastNotification > cooldownPeriod) {
                if ('Notification' in window && Notification.permission === 'granted') {
                    new Notification('System Alert', {
                        body: alert.message,
                        icon: '⚠️',
                    });
                }
                setNotificationCooldowns(prev => ({ ...prev, [alert.id]: now }));

                // Add to history
                setAlertHistory(prev => [
                    { ...alert, timestamp: new Date().toISOString() },
                    ...prev.slice(0, 49),
                ]);
            }
        });
    }, [current, thresholds, notificationCooldowns]);

    return { alerts, alertHistory };
};

// ============================================================================
// UTILITY FUNCTIONS
// ============================================================================

const formatBytes = (bytes, decimals = 2) => {
    if (bytes === 0) return '0 Bytes';
    const k = 1024;
    const dm = decimals < 0 ? 0 : decimals;
    const sizes = ['Bytes', 'KB', 'MB', 'GB', 'TB'];
    const i = Math.floor(Math.log(bytes) / Math.log(k));
    return parseFloat((bytes / Math.pow(k, i)).toFixed(dm)) + ' ' + sizes[i];
};

const exportToJSON = (current, history) => {
    const data = {
        exportDate: new Date().toISOString(),
        currentMetrics: current,
        history: history,
    };
    const blob = new Blob([JSON.stringify(data, null, 2)], { type: 'application/json' });
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = `system-metrics-${new Date().toISOString().split('T')[0]}-${Date.now()}.json`;
    a.click();
    URL.revokeObjectURL(url);
};

const exportToCSV = (history) => {
    const headers = ['time', 'cpu', 'memory', 'netIn', 'netOut', 'diskRead', 'diskWrite'];
    const rows = history.map(row => headers.map(h => row[h] || 0).join(','));
    const csv = [headers.join(','), ...rows].join('\n');

    const blob = new Blob([csv], { type: 'text/csv' });
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = `system-metrics-${new Date().toISOString().split('T')[0]}-${Date.now()}.csv`;
    a.click();
    URL.revokeObjectURL(url);
};

// ============================================================================
// STYLED COMPONENTS (CSS-in-JS)
// ============================================================================

const createStyles = (theme) => ({
    dashboard: {
        fontFamily: '"Inter", "Segoe UI", sans-serif',
        backgroundColor: theme.bg,
        color: theme.textPrimary,
        minHeight: '100vh',
        padding: '20px',
        boxSizing: 'border-box',
        transition: 'background-color 0.3s ease, color 0.3s ease',
    },
    header: {
        display: 'flex',
        justifyContent: 'space-between',
        alignItems: 'center',
        marginBottom: '20px',
        borderBottom: `1px solid ${theme.grid}`,
        paddingBottom: '15px',
        flexWrap: 'wrap',
        gap: '10px',
    },
    title: {
        margin: 0,
        fontSize: '1.5rem',
        fontWeight: 600,
        color: theme.textPrimary,
    },
    headerControls: {
        display: 'flex',
        gap: '10px',
        alignItems: 'center',
        flexWrap: 'wrap',
    },
    button: {
        padding: '8px 16px',
        borderRadius: '6px',
        border: 'none',
        cursor: 'pointer',
        fontSize: '0.9rem',
        fontWeight: 500,
        transition: 'all 0.2s ease',
        backgroundColor: theme.accent,
        color: '#fff',
    },
    buttonSecondary: {
        backgroundColor: theme.cardBg,
        color: theme.textPrimary,
        border: `1px solid ${theme.grid}`,
    },
    statusBadge: {
        padding: '4px 12px',
        borderRadius: '12px',
        fontSize: '0.8rem',
        fontWeight: 600,
        display: 'flex',
        alignItems: 'center',
        gap: '6px',
    },
    grid: {
        display: 'grid',
        gridTemplateColumns: 'repeat(auto-fit, minmax(320px, 1fr))',
        gap: '20px',
    },
    card: {
        backgroundColor: theme.cardBg,
        borderRadius: '12px',
        padding: '20px',
        boxShadow: '0 4px 6px rgba(0, 0, 0, 0.1)',
        border: `1px solid ${theme.grid}`,
        display: 'flex',
        flexDirection: 'column',
        transition: 'all 0.3s ease',
    },
    cardAlert: {
        animation: 'pulse 2s infinite',
        borderColor: theme.danger,
        borderWidth: '2px',
    },
    wideCard: {
        gridColumn: 'span 2',
    },
    cardHeader: {
        display: 'flex',
        justifyContent: 'space-between',
        alignItems: 'center',
        marginBottom: '15px',
    },
    cardTitle: {
        margin: 0,
        fontSize: '1.1rem',
        fontWeight: 500,
        color: theme.textPrimary,
    },
    metricValue: {
        fontSize: '1.8rem',
        fontWeight: 700,
        color: theme.accent,
    },
    chartContainer: {
        flex: 1,
        minHeight: '250px',
        width: '100%',
    },
    alertBanner: {
        backgroundColor: theme.cardBg,
        border: `2px solid ${theme.danger}`,
        borderRadius: '8px',
        padding: '12px 16px',
        marginBottom: '20px',
        display: 'flex',
        alignItems: 'center',
        gap: '12px',
    },
    table: {
        width: '100%',
        borderCollapse: 'collapse',
        fontSize: '0.9rem',
    },
    th: {
        textAlign: 'left',
        padding: '8px',
        borderBottom: `1px solid ${theme.grid}`,
        fontWeight: 600,
        color: theme.textSecondary,
    },
    td: {
        padding: '8px',
        borderBottom: `1px solid ${theme.grid}`,
    },
});

// ============================================================================
// SUB-COMPONENTS
// ============================================================================

const CustomTooltip = ({ active, payload, label, unit = '', theme }) => {
    if (active && payload && payload.length) {
        const styles = createStyles(theme);
        return (
            <div style={{
                ...styles.card,
                padding: '10px',
                minWidth: '150px',
            }}>
                <p style={{ color: theme.textSecondary, marginBottom: '5px', fontSize: '0.8rem' }}>{label}</p>
                {payload.map((entry, index) => (
                    <p key={index} style={{ color: entry.color, margin: '2px 0', fontSize: '0.9rem' }}>
                        {entry.name}: {typeof entry.value === 'number' ? entry.value.toFixed(1) : entry.value}{unit}
                    </p>
                ))}
            </div>
        );
    }
    return null;
};

const LatencyHistogram = ({ latencies, theme }) => {
    const styles = createStyles(theme);

    const histogramData = useMemo(() => {
        const bins = [
            { range: '<50ms', min: 0, max: 50, count: 0 },
            { range: '50-100ms', min: 50, max: 100, count: 0 },
            { range: '100-200ms', min: 100, max: 200, count: 0 },
            { range: '200-500ms', min: 200, max: 500, count: 0 },
            { range: '>500ms', min: 500, max: Infinity, count: 0 },
        ];

        latencies.forEach(lat => {
            const bin = bins.find(b => lat >= b.min && lat < b.max);
            if (bin) bin.count++;
        });

        return bins;
    }, [latencies]);

    return (
        <div style={styles.card}>
            <div style={styles.cardHeader}>
                <h2 style={styles.cardTitle}>Request Latency Distribution</h2>
                <span style={{ fontSize: '0.85rem', color: theme.textSecondary }}>
                    {latencies.length} samples
                </span>
            </div>
            <div style={styles.chartContainer}>
                <ResponsiveContainer width="100%" height="100%">
                    <BarChart data={histogramData}>
                        <CartesianGrid strokeDasharray="3 3" stroke={theme.grid} vertical={false} />
                        <XAxis dataKey="range" stroke={theme.textSecondary} tick={{ fontSize: 12 }} />
                        <YAxis stroke={theme.textSecondary} tick={{ fontSize: 12 }} />
                        <RechartsTooltip content={<CustomTooltip theme={theme} />} />
                        <Bar dataKey="count" fill={theme.success} radius={[4, 4, 0, 0]} />
                    </BarChart>
                </ResponsiveContainer>
            </div>
        </div>
    );
};

const ProcessInfo = ({ system, theme }) => {
    const styles = createStyles(theme);

    return (
        <div style={styles.card}>
            <div style={styles.cardHeader}>
                <h2 style={styles.cardTitle}>System Information</h2>
            </div>
            <table style={styles.table}>
                <tbody>
                    <tr>
                        <td style={styles.td}>Uptime</td>
                        <td style={{ ...styles.td, fontWeight: 600 }}>{system?.uptime || 'N/A'}</td>
                    </tr>
                    <tr>
                        <td style={styles.td}>Active Processes</td>
                        <td style={{ ...styles.td, fontWeight: 600 }}>{system?.processes || 0}</td>
                    </tr>
                    <tr>
                        <td style={styles.td}>Users</td>
                        <td style={{ ...styles.td, fontWeight: 600 }}>{system?.users || 0}</td>
                    </tr>
                    <tr>
                        <td style={styles.td}>Distribution</td>
                        <td style={{ ...styles.td, fontWeight: 600 }}>{system?.distro || 'Unknown'}</td>
                    </tr>
                </tbody>
            </table>
        </div>
    );
};

const NetworkInfo = ({ network, theme }) => {
    const styles = createStyles(theme);
    const detailed = network?.detailed || {};

    return (
        <div style={styles.card}>
            <div style={styles.cardHeader}>
                <h2 style={styles.cardTitle}>Network Details</h2>
            </div>
            <table style={styles.table}>
                <tbody>
                    <tr>
                        <td style={styles.td}>Adapter</td>
                        <td style={{ ...styles.td, fontWeight: 600 }}>{detailed.adapter || 'N/A'}</td>
                    </tr>
                    <tr>
                        <td style={styles.td}>SSID</td>
                        <td style={{ ...styles.td, fontWeight: 600 }}>{detailed.ssid || 'N/A'}</td>
                    </tr>
                    <tr>
                        <td style={styles.td}>IPv4</td>
                        <td style={{ ...styles.td, fontWeight: 600, fontFamily: 'monospace' }}>{detailed.ipv4 || 'N/A'}</td>
                    </tr>
                    <tr>
                        <td style={styles.td}>IPv6</td>
                        <td style={{ ...styles.td, fontWeight: 600, fontFamily: 'monospace', fontSize: '0.75rem' }}>
                            {detailed.ipv6 || 'N/A'}
                        </td>
                    </tr>
                    <tr>
                        <td style={styles.td}>Total RX</td>
                        <td style={{ ...styles.td, fontWeight: 600 }}>{formatBytes(network?.totals?.total_rx || 0)}</td>
                    </tr>
                    <tr>
                        <td style={styles.td}>Total TX</td>
                        <td style={{ ...styles.td, fontWeight: 600 }}>{formatBytes(network?.totals?.total_tx || 0)}</td>
                    </tr>
                </tbody>
            </table>
        </div>
    );
};

const GPUCard = ({ gpu, theme }) => {
    const styles = createStyles(theme);

    const vramPercent = gpu?.memory_total > 0
        ? (gpu.memory_used / gpu.memory_total) * 100
        : 0;

    return (
        <div style={styles.card}>
            <div style={styles.cardHeader}>
                <h2 style={styles.cardTitle}>GPU</h2>
                <span style={{ fontSize: '0.85rem', color: theme.textSecondary }}>
                    {gpu?.temp || 'N/A'}
                </span>
            </div>
            <div style={{ marginBottom: '15px' }}>
                <div style={{ fontSize: '0.9rem', color: theme.textSecondary, marginBottom: '4px' }}>
                    {gpu?.model || 'Unknown'}
                </div>
                <div style={{ fontSize: '0.8rem', color: theme.textSecondary }}>
                    {gpu?.type || 'N/A'}
                </div>
            </div>

            {typeof gpu?.usage === 'number' && (
                <div style={{ marginBottom: '15px' }}>
                    <div style={{ display: 'flex', justifyContent: 'space-between', marginBottom: '4px' }}>
                        <span style={{ fontSize: '0.85rem' }}>Utilization</span>
                        <span style={{ fontSize: '0.85rem', fontWeight: 600 }}>{gpu.usage.toFixed(1)}%</span>
                    </div>
                    <div style={{
                        width: '100%',
                        height: '8px',
                        backgroundColor: theme.grid,
                        borderRadius: '4px',
                        overflow: 'hidden',
                    }}>
                        <div style={{
                            width: `${gpu.usage}%`,
                            height: '100%',
                            backgroundColor: theme.accent,
                            transition: 'width 0.3s ease',
                        }} />
                    </div>
                </div>
            )}

            {gpu?.memory_total > 0 && (
                <div>
                    <div style={{ display: 'flex', justifyContent: 'space-between', marginBottom: '4px' }}>
                        <span style={{ fontSize: '0.85rem' }}>VRAM</span>
                        <span style={{ fontSize: '0.85rem', fontWeight: 600 }}>
                            {(gpu.memory_used / 1024).toFixed(1)} / {(gpu.memory_total / 1024).toFixed(1)} GB
                        </span>
                    </div>
                    <div style={{
                        width: '100%',
                        height: '8px',
                        backgroundColor: theme.grid,
                        borderRadius: '4px',
                        overflow: 'hidden',
                    }}>
                        <div style={{
                            width: `${vramPercent}%`,
                            height: '100%',
                            backgroundColor: theme.warning,
                            transition: 'width 0.3s ease',
                        }} />
                    </div>
                </div>
            )}
        </div>
    );
};

// ============================================================================
// MAIN DASHBOARD COMPONENT
// ============================================================================

export default function EnhancedDashboard() {
    const { theme, themeName, toggleTheme } = useTheme();
    const styles = createStyles(theme);

    const [apiUrl] = useState('http://localhost:8080/api/metrics');
    const [refreshInterval, setRefreshInterval] = useState(3000);
    const [showSettings, setShowSettings] = useState(false);
    const [thresholds, setThresholds] = useState({
        cpu: { warning: 75, danger: 90 },
        memory: { warning: 80, danger: 90 },
        disk: { warning: 85, danger: 95 },
    });

    const {
        current,
        history,
        connectionStatus,
        lastUpdated,
        latencies,
        error,
        refetch,
        clearHistory,
    } = useBackendMetrics(apiUrl, refreshInterval);

    const { alerts, alertHistory } = useAlerts(current, thresholds);

    // Request notification permission
    useEffect(() => {
        if ('Notification' in window && Notification.permission === 'default') {
            Notification.requestPermission();
        }
    }, []);

    // Derived data
    const memoryData = useMemo(() => {
        if (!current?.memory) return [];
        return [
            { name: 'Used', value: current.memory.percent, fill: theme.accent },
            { name: 'Free', value: 100 - current.memory.percent, fill: theme.grid },
        ];
    }, [current, theme]);

    const diskData = useMemo(() => {
        if (!current?.disk?.[0]) return [];
        return [
            { name: current.disk[0].mountpoint, value: current.disk[0].percent, fill: theme.warning },
        ];
    }, [current, theme]);

    // Parse network rates for display
    const parseRate = (rateStr) => {
        if (!rateStr) return 0;
        return parseFloat(rateStr) || 0;
    };

    const netInRate = parseRate(current?.network?.detailed?.recv_rate);
    const netOutRate = parseRate(current?.network?.detailed?.send_rate);

    // Status badge
    const getStatusBadge = () => {
        const statusColors = {
            connected: theme.success,
            connecting: theme.warning,
            disconnected: theme.danger,
        };

        const statusIcons = {
            connected: '●',
            connecting: '◐',
            disconnected: '○',
        };

        return (
            <div style={{
                ...styles.statusBadge,
                backgroundColor: `${statusColors[connectionStatus]}20`,
                color: statusColors[connectionStatus],
            }}>
                <span>{statusIcons[connectionStatus]}</span>
                <span>{connectionStatus}</span>
            </div>
        );
    };

    // Error state
    if (error && !current) {
        return (
            <div style={styles.dashboard}>
                <div style={{
                    textAlign: 'center',
                    paddingTop: '100px',
                    maxWidth: '600px',
                    margin: '0 auto',
                }}>
                    <h2 style={{ color: theme.danger, marginBottom: '20px' }}>❌ Backend Connection Failed</h2>
                    <p style={{ fontSize: '1.1rem', marginBottom: '10px' }}>Cannot connect to backend server</p>
                    <p style={{
                        fontSize: '0.9rem',
                        color: theme.textSecondary,
                        fontFamily: 'monospace',
                        backgroundColor: theme.cardBg,
                        padding: '15px',
                        borderRadius: '8px',
                        marginBottom: '20px',
                    }}>
                        {error}
                    </p>
                    <div style={{ marginBottom: '20px' }}>
                        <p style={{ fontSize: '0.95rem', marginBottom: '10px' }}>Please ensure:</p>
                        <ul style={{ textAlign: 'left', display: 'inline-block', fontSize: '0.9rem' }}>
                            <li>Python backend is running on port 8080</li>
                            <li>Run: <code style={{ backgroundColor: theme.cardBg, padding: '2px 6px', borderRadius: '4px' }}>python web_server.py</code></li>
                            <li>Check for CORS or firewall issues</li>
                        </ul>
                    </div>
                    <button
                        style={{
                            ...styles.button,
                            fontSize: '1rem',
                            padding: '12px 24px',
                        }}
                        onClick={refetch}
                    >
                        🔄 Retry Connection
                    </button>
                </div>
            </div>
        );
    }

    // Loading state
    if (!current) {
        return (
            <div style={styles.dashboard}>
                <div style={{ textAlign: 'center', paddingTop: '100px' }}>
                    <h2>Connecting to backend...</h2>
                    <p style={{ color: theme.textSecondary, marginTop: '10px' }}>http://localhost:8080/api/metrics</p>
                </div>
            </div>
        );
    }

    return (
        <div style={styles.dashboard}>
            {/* Inline keyframes for pulse animation */}
            <style>{`
        @keyframes pulse {
          0%, 100% { opacity: 1; }
          50% { opacity: 0.7; }
        }
      `}</style>

            {/* Header */}
            <header style={styles.header}>
                <h1 style={styles.title}>System Monitor Dashboard</h1>
                <div style={styles.headerControls}>
                    {getStatusBadge()}
                    <span style={{ fontSize: '0.85rem', color: theme.textSecondary }}>
                        {lastUpdated?.toLocaleTimeString() || '--:--:--'}
                    </span>
                    <button
                        style={styles.button}
                        onClick={() => exportToJSON(current, history)}
                        title="Export JSON"
                    >
                        📥 JSON
                    </button>
                    <button
                        style={styles.button}
                        onClick={() => exportToCSV(history)}
                        title="Export CSV"
                    >
                        📥 CSV
                    </button>
                    <button
                        style={{ ...styles.button, ...styles.buttonSecondary }}
                        onClick={toggleTheme}
                        title="Toggle Theme"
                    >
                        {themeName === 'dark' ? '☀️' : '🌙'}
                    </button>
                    <button
                        style={{ ...styles.button, ...styles.buttonSecondary }}
                        onClick={clearHistory}
                        title="Clear History"
                    >
                        🗑️
                    </button>
                </div>
            </header>

            {/* Alert Banner */}
            {alerts.length > 0 && (
                <div style={styles.alertBanner}>
                    <span style={{ fontSize: '1.2rem' }}>⚠️</span>
                    <div style={{ flex: 1 }}>
                        <strong>{alerts.length} Active Alert{alerts.length > 1 ? 's' : ''}</strong>
                        <div style={{ fontSize: '0.85rem', marginTop: '4px' }}>
                            {alerts.map(a => a.message).join(' • ')}
                        </div>
                    </div>
                </div>
            )}

            {/* Main Grid */}
            <div style={styles.grid}>

                {/* CPU Chart - Wide */}
                <div style={{
                    ...styles.card,
                    ...styles.wideCard,
                    ...(alerts.some(a => a.metric === 'CPU') ? styles.cardAlert : {}),
                }}>
                    <div style={styles.cardHeader}>
                        <h2 style={styles.cardTitle}>CPU Usage</h2>
                        <div>
                            <span style={styles.metricValue}>{current.cpu?.usage?.toFixed(1) || 0}</span>
                            <span style={{ fontSize: '0.9rem', color: theme.textSecondary, marginLeft: '5px' }}>%</span>
                        </div>
                    </div>
                    <div style={{ fontSize: '0.85rem', color: theme.textSecondary, marginBottom: '10px' }}>
                        {current.cpu?.model} • {current.cpu?.cores} • {current.cpu?.temp}
                    </div>
                    <div style={styles.chartContainer}>
                        <ResponsiveContainer width="100%" height="100%">
                            <LineChart data={history}>
                                <CartesianGrid strokeDasharray="3 3" stroke={theme.grid} vertical={false} />
                                <XAxis dataKey="time" stroke={theme.textSecondary} tick={{ fontSize: 12 }} minTickGap={30} />
                                <YAxis stroke={theme.textSecondary} domain={[0, 100]} tick={{ fontSize: 12 }} />
                                <RechartsTooltip content={<CustomTooltip unit="%" theme={theme} />} />
                                <Line
                                    type="monotone"
                                    dataKey="cpu"
                                    stroke={theme.accent}
                                    strokeWidth={3}
                                    dot={false}
                                    name="CPU"
                                />
                            </LineChart>
                        </ResponsiveContainer>
                    </div>
                </div>

                {/* Memory Gauge */}
                <div style={{
                    ...styles.card,
                    ...(alerts.some(a => a.metric === 'Memory') ? styles.cardAlert : {}),
                }}>
                    <div style={styles.cardHeader}>
                        <h2 style={styles.cardTitle}>Memory</h2>
                        <span style={{ fontSize: '0.85rem', color: theme.textSecondary }}>
                            {formatBytes(current.memory?.used || 0)} / {formatBytes(current.memory?.total || 0)}
                        </span>
                    </div>
                    <div style={{ position: 'relative', height: '250px', display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
                        <ResponsiveContainer width="100%" height="100%">
                            <PieChart>
                                <Pie
                                    data={memoryData}
                                    cx="50%"
                                    cy="50%"
                                    innerRadius={60}
                                    outerRadius={80}
                                    startAngle={90}
                                    endAngle={-270}
                                    dataKey="value"
                                    stroke="none"
                                >
                                    {memoryData.map((entry, index) => (
                                        <Cell key={`cell-${index}`} fill={entry.fill} />
                                    ))}
                                </Pie>
                            </PieChart>
                        </ResponsiveContainer>
                        <div style={{ position: 'absolute', textAlign: 'center', pointerEvents: 'none' }}>
                            <div style={styles.metricValue}>{current.memory?.percent?.toFixed(0) || 0}%</div>
                            <div style={{ fontSize: '0.85rem', color: theme.textSecondary }}>Used</div>
                        </div>
                    </div>
                </div>

                {/* Network Traffic */}
                <div style={{ ...styles.card, ...styles.wideCard }}>
                    <div style={styles.cardHeader}>
                        <h2 style={styles.cardTitle}>Network Traffic</h2>
                        <div style={{ display: 'flex', gap: '8px' }}>
                            <span style={{
                                padding: '4px 8px',
                                borderRadius: '4px',
                                fontSize: '0.8rem',
                                backgroundColor: `${theme.success}20`,
                                color: theme.success,
                            }}>
                                ↓ {current.network?.detailed?.recv_rate || '0 Kbps'}
                            </span>
                            <span style={{
                                padding: '4px 8px',
                                borderRadius: '4px',
                                fontSize: '0.8rem',
                                backgroundColor: `${theme.warning}20`,
                                color: theme.warning,
                            }}>
                                ↑ {current.network?.detailed?.send_rate || '0 Kbps'}
                            </span>
                        </div>
                    </div>
                    <div style={styles.chartContainer}>
                        <ResponsiveContainer width="100%" height="100%">
                            <AreaChart data={history}>
                                <defs>
                                    <linearGradient id="colorIn" x1="0" y1="0" x2="0" y2="1">
                                        <stop offset="5%" stopColor={theme.success} stopOpacity={0.3} />
                                        <stop offset="95%" stopColor={theme.success} stopOpacity={0} />
                                    </linearGradient>
                                    <linearGradient id="colorOut" x1="0" y1="0" x2="0" y2="1">
                                        <stop offset="5%" stopColor={theme.warning} stopOpacity={0.3} />
                                        <stop offset="95%" stopColor={theme.warning} stopOpacity={0} />
                                    </linearGradient>
                                </defs>
                                <CartesianGrid strokeDasharray="3 3" stroke={theme.grid} vertical={false} />
                                <XAxis dataKey="time" hide />
                                <YAxis stroke={theme.textSecondary} tick={{ fontSize: 10 }} width={40} />
                                <RechartsTooltip content={<CustomTooltip unit=" Mbps" theme={theme} />} />
                                <Area type="monotone" dataKey="netIn" name="Incoming" stroke={theme.success} fillOpacity={1} fill="url(#colorIn)" />
                                <Area type="monotone" dataKey="netOut" name="Outgoing" stroke={theme.warning} fillOpacity={1} fill="url(#colorOut)" />
                            </AreaChart>
                        </ResponsiveContainer>
                    </div>
                </div>

                {/* Disk Usage */}
                <div style={{
                    ...styles.card,
                    ...(alerts.some(a => a.metric === 'Disk') ? styles.cardAlert : {}),
                }}>
                    <div style={styles.cardHeader}>
                        <h2 style={styles.cardTitle}>Disk Usage</h2>
                        <span style={{ fontSize: '0.85rem', color: theme.textSecondary }}>
                            {current.disk?.[0]?.mountpoint || '/'}
                        </span>
                    </div>
                    <div style={{ marginBottom: '15px' }}>
                        <div style={{ display: 'flex', justifyContent: 'space-between', marginBottom: '8px' }}>
                            <span style={{ fontSize: '0.9rem' }}>Used</span>
                            <span style={{ fontSize: '0.9rem', fontWeight: 600 }}>
                                {formatBytes(current.disk?.[0]?.used || 0)} / {formatBytes(current.disk?.[0]?.total || 0)}
                            </span>
                        </div>
                        <div style={{
                            width: '100%',
                            height: '12px',
                            backgroundColor: theme.grid,
                            borderRadius: '6px',
                            overflow: 'hidden',
                        }}>
                            <div style={{
                                width: `${current.disk?.[0]?.percent || 0}%`,
                                height: '100%',
                                backgroundColor: theme.warning,
                                transition: 'width 0.3s ease',
                            }} />
                        </div>
                    </div>
                    <div style={{ textAlign: 'center', paddingTop: '20px' }}>
                        <div style={{ ...styles.metricValue, fontSize: '2.5rem' }}>
                            {current.disk?.[0]?.percent?.toFixed(1) || 0}%
                        </div>
                        <div style={{ fontSize: '0.85rem', color: theme.textSecondary }}>Capacity</div>
                    </div>
                </div>

                {/* GPU Card */}
                <GPUCard gpu={current.gpu} theme={theme} />

                {/* Process Info */}
                <ProcessInfo system={current.system} theme={theme} />

                {/* Network Info */}
                <NetworkInfo network={current.network} theme={theme} />

                {/* Latency Histogram */}
                {latencies.length > 0 && <LatencyHistogram latencies={latencies} theme={theme} />}

            </div>
        </div>
    );
}
