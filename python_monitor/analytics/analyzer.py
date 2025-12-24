"""
Analytics Engine - Trend analysis and anomaly detection
"""

import statistics
from typing import List, Dict, Any, Optional, Tuple
from datetime import datetime, timedelta
import logging


class MetricsAnalyzer:
    """Analyze metrics for trends and anomalies"""
    
    def __init__(self):
        self.logger = logging.getLogger("monitor.analytics")
    
    def calculate_moving_average(self, values: List[float], 
                                window_size: int = 5) -> List[float]:
        """
        Calculate moving average
        
        Args:
            values: List of values
            window_size: Window size for moving average
            
        Returns:
            List of moving averages
        """
        if len(values) < window_size:
            return values
        
        moving_averages = []
        for i in range(len(values) - window_size + 1):
            window = values[i:i + window_size]
            moving_averages.append(sum(window) / window_size)
        
        return moving_averages
    
    def detect_trend(self, values: List[float], threshold: float = 0.1) -> str:
        """
        Detect trend in values
        
        Args:
            values: List of values
            threshold: Minimum change percentage to consider trending
            
        Returns:
            'increasing', 'decreasing', or 'stable'
        """
        if len(values) < 2:
            return 'stable'
        
        # Calculate linear regression slope (simplified)
        n = len(values)
        x_mean = (n - 1) / 2
        y_mean = sum(values) / n
        
        numerator = sum((i - x_mean) * (values[i] - y_mean) for i in range(n))
        denominator = sum((i - x_mean) ** 2 for i in range(n))
        
        if denominator == 0:
            return 'stable'
        
        slope = numerator / denominator
        change_rate = abs(slope / y_mean) if y_mean != 0 else 0
        
        if change_rate < threshold:
            return 'stable'
        elif slope > 0:
            return 'increasing'
        else:
            return 'decreasing'
    
    def detect_anomalies(self, values: List[float], 
                        std_threshold: float = 2.0) -> List[int]:
        """
        Detect anomalies using statistical methods
        
        Args:
            values: List of values
            std_threshold: Number of standard deviations for anomaly
            
        Returns:
            List of indices where anomalies detected
        """
        if len(values) < 3:
            return []
        
        try:
            mean = statistics.mean(values)
            stdev = statistics.stdev(values)
            
            if stdev == 0:
                return []
            
            anomalies = []
            for i, value in enumerate(values):
                z_score = abs((value - mean) / stdev)
                if z_score > std_threshold:
                    anomalies.append(i)
            
            return anomalies
        except Exception as e:
            self.logger.error(f"Error detecting anomalies: {e}")
            return []
    
    def calculate_percentiles(self, values: List[float]) -> Dict[str, float]:
        """Calculate percentile statistics"""
        if not values:
            return {}
        
        sorted_values = sorted(values)
        
        return {
            'min': min(values),
            'max': max(values),
            'mean': statistics.mean(values),
            'median': statistics.median(values),
            'p25': self._percentile(sorted_values, 25),
            'p75': self._percentile(sorted_values, 75),
            'p90': self._percentile(sorted_values, 90),
            'p95': self._percentile(sorted_values, 95),
            'p99': self._percentile(sorted_values, 99),
        }
    
    def _percentile(self, sorted_values: List[float], percentile: int) -> float:
        """Calculate specific percentile"""
        if not sorted_values:
            return 0.0
        
        index = (len(sorted_values) - 1) * percentile / 100
        lower = int(index)
        upper = lower + 1
        
        if upper >= len(sorted_values):
            return sorted_values[lower]
        
        weight = index - lower
        return sorted_values[lower] * (1 - weight) + sorted_values[upper] * weight
    
    def analyze_metric_history(self, metric_data: List[Dict[str, Any]], 
                              metric_key: str) -> Dict[str, Any]:
        """
        Comprehensive analysis of metric history
        
        Args:
            metric_data: List of metric records
            metric_key: Key to extract from metric_data
            
        Returns:
            Analysis results
        """
        try:
            # Extract values
            values = []
            for record in metric_data:
                data = record.get('metric_data', {})
                if isinstance(data, dict) and metric_key in data:
                    value = data[metric_key]
                    if isinstance(value, (int, float)):
                        values.append(float(value))
            
            if not values:
                return {'error': 'No valid data points'}
            
            # Perform analysis
            analysis = {
                'data_points': len(values),
                'statistics': self.calculate_percentiles(values),
                'trend': self.detect_trend(values),
                'anomalies_count': len(self.detect_anomalies(values)),
                'moving_avg_5': self.calculate_moving_average(values, 5)[-5:] if len(values) >= 5 else values,
            }
            
            return analysis
        except Exception as e:
            self.logger.error(f"Error analyzing metric history: {e}")
            return {'error': str(e)}
    
    def predict_next_value(self, values: List[float]) -> Optional[float]:
        """
        Simple prediction of next value using linear extrapolation
        
        Args:
            values: Historical values
            
        Returns:
            Predicted next value
        """
        if len(values) < 2:
            return None
        
        # Use last 10 values for prediction
        recent_values = values[-10:]
        n = len(recent_values)
        
        # Calculate slope
        x_mean = (n - 1) / 2
        y_mean = sum(recent_values) / n
        
        numerator = sum((i - x_mean) * (recent_values[i] - y_mean) for i in range(n))
        denominator = sum((i - x_mean) ** 2 for i in range(n))
        
        if denominator == 0:
            return recent_values[-1]
        
        slope = numerator / denominator
        intercept = y_mean - slope * x_mean
        
        # Predict next value
        next_value = slope * n + intercept
        
        return round(next_value, 2)
