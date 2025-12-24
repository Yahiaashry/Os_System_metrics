"""
Command-Line Interface for Advanced Processing
Python for: Analytics, Database, Reporting only
Data collection handled by Windows/Bash monitors
"""

import argparse
import json
import sys
from pathlib import Path
from datetime import datetime, timedelta

# Add parent directory to path
sys.path.insert(0, str(Path(__file__).parent.parent))

from python_monitor.database.metrics_db import MetricsDatabase
from python_monitor.analytics.analyzer import MetricsAnalyzer


def cmd_analyze(args):
    """Analyze historical metrics"""
    db = MetricsDatabase(args.db_path)
    analyzer = MetricsAnalyzer()
    
    # Get recent metrics
    end_time = datetime.utcnow()
    start_time = end_time - timedelta(hours=args.hours)
    
    metric_type = args.metric_type or 'cpu'
    records = db.get_metrics_range(start_time, end_time, metric_type)
    
    if not records:
        print(f"No data found for {metric_type} in the last {args.hours} hours")
        return
    
    # Analyze
    analysis = analyzer.analyze_metric_history(records, 'usage_percent')
    
    print(f"\n{'='*50}")
    print(f"Analysis for {metric_type} (last {args.hours} hours)")
    print(f"{'='*50}\n")
    print(json.dumps(analysis, indent=2))
    print(f"\n{'='*50}\n")


def cmd_database(args):
    """Database management"""
    db = MetricsDatabase(args.db_path)
    
    if args.action == 'stats':
        stats = db.get_database_stats()
        print(json.dumps(stats, indent=2))
    
    elif args.action == 'cleanup':
        deleted = db.cleanup_old_records(args.retention_days)
        print(f"Deleted {deleted} old records")
    
    elif args.action == 'latest':
        records = db.get_latest_metrics(args.metric_type, args.limit)
        print(json.dumps(records, indent=2))


def main():
    """Main CLI entry point"""
    parser = argparse.ArgumentParser(
        description='System Monitor - Advanced Processing (Analytics, Database, Reporting)'
    )
    
    subparsers = parser.add_subparsers(dest='command', help='Commands')
    
    # Analyze command
    analyze_parser = subparsers.add_parser('analyze', help='Analyze historical metrics')
    analyze_parser.add_argument('--hours', type=int, default=24,
                              help='Hours of history to analyze')
    analyze_parser.add_argument('--metric-type', choices=['cpu', 'memory', 'disk', 'network'],
                              help='Metric type to analyze')
    analyze_parser.add_argument('--db-path', default='metrics.db',
                              help='Database path')
    analyze_parser.set_defaults(func=cmd_analyze)
    
    # Database command
    db_parser = subparsers.add_parser('database', help='Database management')
    db_parser.add_argument('action', choices=['stats', 'cleanup', 'latest'],
                          help='Database action')
    db_parser.add_argument('--db-path', default='metrics.db',
                          help='Database path')
    db_parser.add_argument('--retention-days', type=int, default=7,
                          help='Retention days for cleanup')
    db_parser.add_argument('--metric-type',
                          help='Filter by metric type')
    db_parser.add_argument('--limit', type=int, default=10,
                          help='Limit for latest records')
    db_parser.set_defaults(func=cmd_database)
    
    args = parser.parse_args()
    
    if not args.command:
        parser.print_help()
        return
    
    args.func(args)


if __name__ == '__main__':
    main()
