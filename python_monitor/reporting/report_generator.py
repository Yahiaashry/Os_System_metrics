#!/usr/bin/env python3
"""
Report Generator - HTML/PDF Reports with Charts
Generates visual reports from metrics data
"""

import os
import sqlite3
from datetime import datetime, timedelta
from typing import Dict, List, Optional, Tuple
import json

try:
    import matplotlib
    matplotlib.use('Agg')  # Non-interactive backend
    import matplotlib.pyplot as plt
    import matplotlib.dates as mdates
    MATPLOTLIB_AVAILABLE = True
except ImportError:
    MATPLOTLIB_AVAILABLE = False
    print("Warning: matplotlib not available. Install with: pip install matplotlib")

try:
    from jinja2 import Template
    JINJA2_AVAILABLE = True
except ImportError:
    JINJA2_AVAILABLE = False
    print("Warning: jinja2 not available. Install with: pip install jinja2")


class ReportGenerator:
    """Generate HTML/PDF reports with charts from metrics data."""
    
    def __init__(self, db_path: str, output_dir: str = "reports"):
        """
        Initialize report generator.
        
        Args:
            db_path: Path to SQLite database
            output_dir: Directory to save reports
        """
        self.db_path = db_path
        self.output_dir = output_dir
        os.makedirs(output_dir, exist_ok=True)
        os.makedirs(f"{output_dir}/charts", exist_ok=True)
    
    def generate_chart(
        self,
        metric_type: str,
        hours: int = 24,
        title: str = None
    ) -> Optional[str]:
        """
        Generate a chart for a specific metric.
        
        Args:
            metric_type: Type of metric (cpu, memory, disk, etc.)
            hours: Number of hours to include
            title: Chart title (auto-generated if None)
        
        Returns:
            Path to generated chart image or None if failed
        """
        if not MATPLOTLIB_AVAILABLE:
            return None
        
        # Fetch data
        data = self._fetch_metrics(metric_type, hours)
        if not data:
            return None
        
        timestamps = [row[0] for row in data]
        values = [row[1] for row in data]
        
        # Parse timestamps
        dt_timestamps = [datetime.fromisoformat(ts) for ts in timestamps]
        
        # Create plot
        fig, ax = plt.subplots(figsize=(12, 6))
        ax.plot(dt_timestamps, values, linewidth=2, color='#2563eb')
        
        # Formatting
        if title is None:
            title = f"{metric_type.upper()} Usage - Last {hours} Hours"
        ax.set_title(title, fontsize=14, fontweight='bold')
        ax.set_xlabel('Time', fontsize=12)
        ax.set_ylabel('Usage (%)', fontsize=12)
        ax.grid(True, alpha=0.3)
        
        # Format x-axis
        ax.xaxis.set_major_formatter(mdates.DateFormatter('%H:%M'))
        plt.xticks(rotation=45)
        
        # Add threshold lines
        ax.axhline(y=80, color='orange', linestyle='--', alpha=0.5, label='Warning (80%)')
        ax.axhline(y=90, color='red', linestyle='--', alpha=0.5, label='Critical (90%)')
        ax.legend()
        
        plt.tight_layout()
        
        # Save chart
        chart_path = f"{self.output_dir}/charts/{metric_type}_{hours}h.png"
        plt.savefig(chart_path, dpi=100)
        plt.close()
        
        return chart_path
    
    def generate_html_report(
        self,
        hours: int = 24,
        include_charts: bool = True
    ) -> str:
        """
        Generate HTML report.
        
        Args:
            hours: Number of hours to include
            include_charts: Whether to include charts
        
        Returns:
            Path to generated HTML file
        """
        # Generate charts
        chart_paths = {}
        if include_charts and MATPLOTLIB_AVAILABLE:
            for metric_type in ['cpu', 'memory', 'disk', 'network']:
                chart_path = self.generate_chart(metric_type, hours)
                if chart_path:
                    chart_paths[metric_type] = os.path.basename(chart_path)
        
        # Collect summary statistics
        summary = self._get_summary_stats(hours)
        
        # Get latest metrics
        latest_metrics = self._get_latest_metrics()
        
        # Generate HTML
        html_content = self._generate_html_content(
            hours, summary, latest_metrics, chart_paths
        )
        
        # Save report
        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        report_path = f"{self.output_dir}/report_{timestamp}.html"
        
        with open(report_path, 'w') as f:
            f.write(html_content)
        
        return report_path
    
    def _load_fallback_data(self, hours: int = 24) -> List[dict]:
        """Load data from fallback JSON files (Windows + Linux)."""
        import glob
        import json
        from datetime import datetime, timedelta
        
        cutoff = datetime.now() - timedelta(hours=hours)
        data = []
        
        # Paths to check (both Windows native and Linux WSL)
        paths = [
            "/mnt/c/Users/HP/Desktop/Projects/OS-Project/data/windows_data/history/*.json",
            "/home/yahia/12thprojectos/data/python_data/history/*.json"
        ]
        
        for pattern in paths:
            try:
                for filepath in glob.glob(pattern):
                    try:
                        with open(filepath) as f:
                            record = json.load(f)
                            # Parse timestamp
                            ts_str = record.get('timestamp', '')
                            if ts_str:
                                try:
                                    timestamp = datetime.fromisoformat(ts_str.replace('Z', '+00:00'))
                                    if timestamp >= cutoff:
                                        data.append(record)
                                except:
                                    pass
                    except Exception as e:
                        print(f"Error loading {filepath}: {e}")
            except Exception as e:
                # Path may not exist, continue
                pass
        
        return data
    
    def _fetch_metrics(
        self,
        metric_type: str,
        hours: int
    ) -> List[Tuple[str, float]]:
        """Fetch metrics from database."""
        try:
            conn = sqlite3.connect(self.db_path)
            cursor = conn.cursor()
            
            since = datetime.now() - timedelta(hours=hours)
            
            cursor.execute("""
                SELECT timestamp, value 
                FROM metrics 
                WHERE metric_type = ? 
                AND datetime(timestamp) >= datetime(?)
                ORDER BY timestamp ASC
            """, (metric_type, since.isoformat()))
            
            data = cursor.fetchall()
            conn.close()
            
            # If no data in database, try fallback files
            if not data:
                fallback_data = self._load_fallback_data(hours)
                print(f"Loaded {len(fallback_data)} fallback records")
                # Note: Fallback data structure is different, would need processing
            
            return data
        except Exception as e:
            print(f"Error fetching metrics: {e}")
            # Try fallback on error
            fallback_data = self._load_fallback_data(hours)
            if fallback_data:
                print(f"Using {len(fallback_data)} fallback records")
            return []
    
    def _get_summary_stats(self, hours: int) -> Dict:
        """Get summary statistics for all metrics."""
        summary = {}
        
        try:
            conn = sqlite3.connect(self.db_path)
            cursor = conn.cursor()
            
            since = datetime.now() - timedelta(hours=hours)
            
            for metric_type in ['cpu', 'memory', 'disk', 'network']:
                cursor.execute("""
                    SELECT 
                        AVG(value) as avg,
                        MIN(value) as min,
                        MAX(value) as max,
                        COUNT(*) as count
                    FROM metrics
                    WHERE metric_type = ?
                    AND datetime(timestamp) >= datetime(?)
                """, (metric_type, since.isoformat()))
                
                row = cursor.fetchone()
                if row:
                    summary[metric_type] = {
                        'avg': round(row[0], 2) if row[0] else 0,
                        'min': round(row[1], 2) if row[1] else 0,
                        'max': round(row[2], 2) if row[2] else 0,
                        'count': row[3]
                    }
            
            conn.close()
        except Exception as e:
            print(f"Error getting summary stats: {e}")
        
        return summary
    
    def _get_latest_metrics(self) -> Dict:
        """Get latest metric values."""
        latest = {}
        
        try:
            conn = sqlite3.connect(self.db_path)
            cursor = conn.cursor()
            
            for metric_type in ['cpu', 'memory', 'disk', 'network', 'gpu']:
                cursor.execute("""
                    SELECT value, timestamp
                    FROM metrics
                    WHERE metric_type = ?
                    ORDER BY timestamp DESC
                    LIMIT 1
                """, (metric_type,))
                
                row = cursor.fetchone()
                if row:
                    latest[metric_type] = {
                        'value': round(row[0], 2),
                        'timestamp': row[1]
                    }
            
            conn.close()
        except Exception as e:
            print(f"Error getting latest metrics: {e}")
        
        return latest
    
    def _generate_html_content(
        self,
        hours: int,
        summary: Dict,
        latest: Dict,
        chart_paths: Dict
    ) -> str:
        """Generate HTML content."""
        
        # Simple HTML template (no jinja2 dependency required)
        html = f"""
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>System Monitoring Report</title>
    <style>
        body {{
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Oxygen, Ubuntu, sans-serif;
            margin: 0;
            padding: 20px;
            background-color: #f5f5f5;
        }}
        .container {{
            max-width: 1200px;
            margin: 0 auto;
            background: white;
            padding: 30px;
            border-radius: 8px;
            box-shadow: 0 2px 4px rgba(0,0,0,0.1);
        }}
        h1 {{
            color: #1e40af;
            border-bottom: 3px solid #2563eb;
            padding-bottom: 10px;
        }}
        h2 {{
            color: #374151;
            margin-top: 30px;
        }}
        .timestamp {{
            color: #6b7280;
            font-size: 14px;
        }}
        .metrics-grid {{
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(250px, 1fr));
            gap: 20px;
            margin: 20px 0;
        }}
        .metric-card {{
            background: #f9fafb;
            padding: 20px;
            border-radius: 6px;
            border-left: 4px solid #2563eb;
        }}
        .metric-card h3 {{
            margin: 0 0 10px 0;
            color: #1f2937;
            font-size: 16px;
            text-transform: uppercase;
        }}
        .metric-value {{
            font-size: 32px;
            font-weight: bold;
            color: #2563eb;
            margin: 10px 0;
        }}
        .metric-stats {{
            font-size: 14px;
            color: #6b7280;
            margin-top: 10px;
        }}
        .chart {{
            margin: 20px 0;
            text-align: center;
        }}
        .chart img {{
            max-width: 100%;
            height: auto;
            border-radius: 6px;
            box-shadow: 0 2px 4px rgba(0,0,0,0.1);
        }}
        .status-ok {{ color: #10b981; }}
        .status-warning {{ color: #f59e0b; }}
        .status-critical {{ color: #ef4444; }}
        table {{
            width: 100%;
            border-collapse: collapse;
            margin: 20px 0;
        }}
        th, td {{
            padding: 12px;
            text-align: left;
            border-bottom: 1px solid #e5e7eb;
        }}
        th {{
            background-color: #f9fafb;
            font-weight: 600;
            color: #374151;
        }}
    </style>
</head>
<body>
    <div class="container">
        <h1>📊 System Monitoring Report</h1>
        <p class="timestamp">Generated: {datetime.now().strftime("%Y-%m-%d %H:%M:%S")}</p>
        <p class="timestamp">Period: Last {hours} hours</p>
        
        <h2>📈 Current Status</h2>
        <div class="metrics-grid">
"""
        
        # Add current metrics
        for metric_type, data in latest.items():
            value = data['value']
            status_class = 'status-ok'
            if value > 90:
                status_class = 'status-critical'
            elif value > 80:
                status_class = 'status-warning'
            
            html += f"""
            <div class="metric-card">
                <h3>{metric_type.upper()}</h3>
                <div class="metric-value {status_class}">{value}%</div>
                <div class="metric-stats">Updated: {data['timestamp'][:19]}</div>
            </div>
"""
        
        html += """
        </div>
        
        <h2>📊 Summary Statistics</h2>
        <table>
            <thead>
                <tr>
                    <th>Metric</th>
                    <th>Average</th>
                    <th>Minimum</th>
                    <th>Maximum</th>
                    <th>Samples</th>
                </tr>
            </thead>
            <tbody>
"""
        
        # Add summary table
        for metric_type, stats in summary.items():
            html += f"""
                <tr>
                    <td><strong>{metric_type.upper()}</strong></td>
                    <td>{stats['avg']}%</td>
                    <td>{stats['min']}%</td>
                    <td>{stats['max']}%</td>
                    <td>{stats['count']}</td>
                </tr>
"""
        
        html += """
            </tbody>
        </table>
"""
        
        # Add charts
        if chart_paths:
            html += "\n        <h2>📉 Trend Charts</h2>\n"
            for metric_type, chart_file in chart_paths.items():
                html += f"""
        <div class="chart">
            <h3>{metric_type.upper()} Usage</h3>
            <img src="charts/{chart_file}" alt="{metric_type} chart">
        </div>
"""
        
        html += """
    </div>
</body>
</html>
"""
        
        return html
    
    def generate_json_report(self, hours: int = 24) -> str:
        """
        Generate JSON report.
        
        Args:
            hours: Number of hours to include
        
        Returns:
            Path to generated JSON file
        """
        report_data = {
            'generated_at': datetime.now().isoformat(),
            'period_hours': hours,
            'summary': self._get_summary_stats(hours),
            'latest': self._get_latest_metrics(),
            'trends': {}
        }
        
        # Add trend data
        for metric_type in ['cpu', 'memory', 'disk', 'network']:
            data = self._fetch_metrics(metric_type, hours)
            report_data['trends'][metric_type] = [
                {'timestamp': row[0], 'value': row[1]} 
                for row in data
            ]
        
        # Save report
        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        report_path = f"{self.output_dir}/report_{timestamp}.json"
        
        with open(report_path, 'w') as f:
            json.dump(report_data, f, indent=2)
        
        return report_path


def main():
    """CLI entry point for report generation."""
    import argparse
    
    parser = argparse.ArgumentParser(description='Generate system monitoring reports')
    parser.add_argument('--db', default='metrics.db', help='Path to metrics database')
    parser.add_argument('--output', default='reports', help='Output directory')
    parser.add_argument('--hours', type=int, default=24, help='Hours to include in report')
    parser.add_argument('--format', choices=['html', 'json', 'both'], default='html',
                       help='Report format')
    parser.add_argument('--no-charts', action='store_true', help='Disable charts in HTML')
    
    args = parser.parse_args()
    
    generator = ReportGenerator(args.db, args.output)
    
    if args.format in ['html', 'both']:
        html_path = generator.generate_html_report(args.hours, not args.no_charts)
        print(f"HTML report generated: {html_path}")
    
    if args.format in ['json', 'both']:
        json_path = generator.generate_json_report(args.hours)
        print(f"JSON report generated: {json_path}")


if __name__ == '__main__':
    main()
