from flask import Flask, jsonify
from flask_cors import CORS
import json
import os
import time

app = Flask(__name__)
CORS(app)  # Enable CORS for React frontend

METRICS_FILE = os.path.join(os.path.dirname(__file__), '..', 'shared', 'metrics.json')

@app.route('/api/metrics')
def get_metrics():
    try:
        if os.path.exists(METRICS_FILE):
            with open(METRICS_FILE, 'r') as f:
                data = json.load(f)
            return jsonify(data)
        else:
            return jsonify({"error": "No metrics available yet", "timestamp": None}), 404
    except Exception as e:
        return jsonify({"error": str(e)}), 500

if __name__ == '__main__':
    print("Starting API Server on port 5000...")
    app.run(port=5000, debug=True)
