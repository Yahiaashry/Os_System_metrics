import React from 'react';
import EnhancedDashboard from './Dashboard';

/**
 * Enhanced Dashboard with all features:
 * - Backend integration (http://localhost:8080/api/metrics)
 * - Automatic fallback to mock data when backend unavailable
 * - Light/Dark theme toggle with persistence
 * - JSON and CSV export functionality
 * - Historical data persistence in localStorage
 * - Configurable alerts with browser notifications
 * - Additional metrics: Latency histogram, GPU, Network details, Process info
 * 
 * To use:
 * 1. Ensure Python backend is running on port 8080
 * 2. Run: npm start
 * 3. Dashboard will auto-connect or use mock data
 */
function App() {
    return <EnhancedDashboard />;
}

export default App;
