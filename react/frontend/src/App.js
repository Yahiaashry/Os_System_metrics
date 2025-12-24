import React from 'react';
import EnhancedDashboard from './Dashboard';

/**
 * Main App component using Enhanced Dashboard
 * 
 * Features:
 * - Backend integration (http://localhost:8080/api/metrics)
 * - Light/Dark theme toggle
 * - JSON and CSV export
 * - Historical data persistence
 * - Configurable alerts
 * - Additional metrics (Latency, GPU, Network, System)
 */
function App() {
    return <EnhancedDashboard />;
}

export default App;
