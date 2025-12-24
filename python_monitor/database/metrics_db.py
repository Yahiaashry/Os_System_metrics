"""
Metrics Database - SQLite-based time-series storage
"""

import sqlite3
import json
from datetime import datetime, timedelta
from typing import Dict, Any, List, Optional
from pathlib import Path
import logging


class MetricsDatabase:
    """SQLite database for storing time-series metrics"""
    
    def __init__(self, db_path: str = "metrics.db"):
        self.db_path = db_path
        self.logger = logging.getLogger("monitor.database")
        self._init_database()
    
    def _init_database(self) -> None:
        """Initialize database schema"""
        conn = self._get_connection()
        cursor = conn.cursor()
        
        # Create metrics table
        cursor.execute("""
            CREATE TABLE IF NOT EXISTS metrics (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                timestamp DATETIME NOT NULL,
                hostname TEXT NOT NULL,
                metric_type TEXT NOT NULL,
                metric_data TEXT NOT NULL,
                status TEXT,
                data_source TEXT DEFAULT 'python',
                created_at DATETIME DEFAULT CURRENT_TIMESTAMP
            )
        """)
        
        # Add data_source column to existing tables (migration)
        try:
            cursor.execute("""
                ALTER TABLE metrics ADD COLUMN data_source TEXT DEFAULT 'python'
            """)
            self.logger.info("Added data_source column to metrics table")
        except sqlite3.OperationalError:
            # Column already exists
            pass
        
        # Create index for faster queries
        cursor.execute("""
            CREATE INDEX IF NOT EXISTS idx_timestamp 
            ON metrics(timestamp DESC)
        """)
        
        cursor.execute("""
            CREATE INDEX IF NOT EXISTS idx_metric_type 
            ON metrics(metric_type, timestamp DESC)
        """)
        
        cursor.execute("""
            CREATE INDEX IF NOT EXISTS idx_data_source 
            ON metrics(data_source, timestamp DESC)
        """)
        
        conn.commit()
        conn.close()
        
        self.logger.info(f"Database initialized: {self.db_path}")
    
    def _get_connection(self) -> sqlite3.Connection:
        """Get database connection"""
        return sqlite3.connect(self.db_path)
    
    def insert_metrics(self, hostname: str, metric_type: str, 
                      metric_data: Dict[str, Any], status: str = "OK",
                      data_source: str = "python") -> int:
        """
        Insert metrics into database
        
        Args:
            hostname: System hostname
            metric_type: Type of metric (cpu, memory, etc.)
            metric_data: Metric data dictionary
            status: Status string
            data_source: Data source platform (python, windows, etc.)
            
        Returns:
            Inserted row ID
        """
        conn = self._get_connection()
        cursor = conn.cursor()
        
        cursor.execute("""
            INSERT INTO metrics (timestamp, hostname, metric_type, metric_data, status, data_source)
            VALUES (?, ?, ?, ?, ?, ?)
        """, (
            datetime.utcnow().isoformat(),
            hostname,
            metric_type,
            json.dumps(metric_data),
            status,
            data_source
        ))
        
        row_id = cursor.lastrowid
        conn.commit()
        conn.close()
        
        return row_id
    
    def get_latest_metrics(self, metric_type: Optional[str] = None, 
                          limit: int = 100) -> List[Dict[str, Any]]:
        """
        Get latest metrics
        
        Args:
            metric_type: Filter by metric type (optional)
            limit: Maximum number of records
            
        Returns:
            List of metric records
        """
        conn = self._get_connection()
        cursor = conn.cursor()
        
        if metric_type:
            cursor.execute("""
                SELECT id, timestamp, hostname, metric_type, metric_data, status, data_source
                FROM metrics
                WHERE metric_type = ?
                ORDER BY timestamp DESC
                LIMIT ?
            """, (metric_type, limit))
        else:
            cursor.execute("""
                SELECT id, timestamp, hostname, metric_type, metric_data, status, data_source
                FROM metrics
                ORDER BY timestamp DESC
                LIMIT ?
            """, (limit,))
        
        rows = cursor.fetchall()
        conn.close()
        
        return [
            {
                'id': row[0],
                'timestamp': row[1],
                'hostname': row[2],
                'metric_type': row[3],
                'metric_data': json.loads(row[4]),
                'status': row[5],
                'data_source': row[6] if len(row) > 6 else 'unknown',
            }
            for row in rows
        ]
    
    def get_metrics_range(self, start_time: datetime, end_time: datetime,
                         metric_type: Optional[str] = None) -> List[Dict[str, Any]]:
        """Get metrics within time range"""
        conn = self._get_connection()
        cursor = conn.cursor()
        
        if metric_type:
            cursor.execute("""
                SELECT id, timestamp, hostname, metric_type, metric_data, status, data_source
                FROM metrics
                WHERE timestamp BETWEEN ? AND ?
                AND metric_type = ?
                ORDER BY timestamp ASC
            """, (start_time.isoformat(), end_time.isoformat(), metric_type))
        else:
            cursor.execute("""
                SELECT id, timestamp, hostname, metric_type, metric_data, status, data_source
                FROM metrics
                WHERE timestamp BETWEEN ? AND ?
                ORDER BY timestamp ASC
            """, (start_time.isoformat(), end_time.isoformat()))
        
        rows = cursor.fetchall()
        conn.close()
        
        return [
            {
                'id': row[0],
                'timestamp': row[1],
                'hostname': row[2],
                'metric_type': row[3],
                'metric_data': json.loads(row[4]),
                'status': row[5],
                'data_source': row[6] if len(row) > 6 else 'unknown',
            }
            for row in rows
        ]
    
    def cleanup_old_records(self, retention_days: int = 7) -> int:
        """
        Remove old records
        
        Args:
            retention_days: Number of days to retain
            
        Returns:
            Number of deleted records
        """
        conn = self._get_connection()
        cursor = conn.cursor()
        
        cutoff_date = datetime.utcnow() - timedelta(days=retention_days)
        
        cursor.execute("""
            DELETE FROM metrics
            WHERE timestamp < ?
        """, (cutoff_date.isoformat(),))
        
        deleted_count = cursor.rowcount
        conn.commit()
        conn.close()
        
        self.logger.info(f"Cleaned up {deleted_count} old records")
        return deleted_count
    
    def get_database_stats(self) -> Dict[str, Any]:
        """Get database statistics"""
        conn = self._get_connection()
        cursor = conn.cursor()
        
        cursor.execute("SELECT COUNT(*) FROM metrics")
        total_records = cursor.fetchone()[0]
        
        cursor.execute("""
            SELECT metric_type, COUNT(*) as count
            FROM metrics
            GROUP BY metric_type
        """)
        type_counts = {row[0]: row[1] for row in cursor.fetchall()}
        
        cursor.execute("""
            SELECT MIN(timestamp), MAX(timestamp)
            FROM metrics
        """)
        time_range = cursor.fetchone()
        
        conn.close()
        
        return {
            'total_records': total_records,
            'by_type': type_counts,
            'oldest_record': time_range[0],
            'newest_record': time_range[1],
            'db_path': self.db_path,
        }
