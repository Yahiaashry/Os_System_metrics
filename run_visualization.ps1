# PowerShell Script to Start Visualization System
# Usage: Run this from the project root directory

Write-Host "Starting System Visualization..." -ForegroundColor Green

$root = Get-Location

# 1. Start Metrics Writer (Backend)
Write-Host "Launching Metrics Writer..."
try {
    Start-Process python -ArgumentList "python_monitor/backend/metrics_writer.py" -WorkingDirectory $root -WindowStyle Minimized
} catch {
    Write-Error "Failed to start Metrics Writer. Ensure Python is in your PATH."
}

# 2. Start API Server (Backend)
Write-Host "Launching API Server..."
try {
    Start-Process python -ArgumentList "python_monitor/backend/api_server.py" -WorkingDirectory $root -WindowStyle Minimized
} catch {
    Write-Error "Failed to start API Server."
}

# 3. Start React Frontend
Write-Host "Starting Frontend..."
$frontendPath = Join-Path $root "react\frontend"

if (Test-Path $frontendPath) {
    Set-Location $frontendPath
    npm start
} else {
    Write-Error "Frontend directory not found at $frontendPath"
}
