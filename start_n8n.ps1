# Script to automate starting Docker and n8n on Windows

Write-Host "Checking if Docker is running..." -ForegroundColor Cyan

# Check if docker command works
$dockerRunning = $false
try {
    # Run docker ps silently and check status
    $res = docker ps 2>$null
    if ($LASTEXITCODE -eq 0) {
        $dockerRunning = $true
    }
} catch {
    # Command failed or docker not in path
}

if (-not $dockerRunning) {
    Write-Host "Docker is not running. Starting Docker Desktop..." -ForegroundColor Yellow
    $dockerPath = "C:\Program Files\Docker\Docker\Docker Desktop.exe"
    if (Test-Path $dockerPath) {
        Start-Process $dockerPath
        Write-Host "Waiting for Docker daemon to start (this can take 30-60 seconds)..." -ForegroundColor Yellow
        
        # Poll docker ps until it succeeds (up to 2 minutes)
        $attempts = 0
        $maxAttempts = 24
        while ($attempts -lt $maxAttempts) {
            Start-Sleep -Seconds 5
            $attempts++
            try {
                $null = docker ps 2>$null
                if ($LASTEXITCODE -eq 0) {
                    Write-Host "Docker daemon is ready!" -ForegroundColor Green
                    break
                }
            } catch {}
            Write-Host "Still waiting for Docker... ($($attempts * 5)s elapsed)" -ForegroundColor Gray
        }
        
        if ($attempts -ge $maxAttempts) {
            Write-Warning "Docker took too long to start. Please check Docker Desktop manually."
            exit 1
        }
    } else {
        Write-Error "Docker Desktop was not found at standard path: $dockerPath"
        exit 1
    }
} else {
    Write-Host "Docker is already running." -ForegroundColor Green
}

# Navigate to docker compose directory and start n8n
$composeDir = "d:\n8n\docker"
if (Test-Path $composeDir) {
    Write-Host "Starting n8n via Docker Compose..." -ForegroundColor Cyan
    Push-Location $composeDir
    docker compose up -d
    Pop-Location
} else {
    Write-Error "Docker compose directory not found at: $composeDir"
    exit 1
}

# Verify container is running
Write-Host "`nChecking container status:" -ForegroundColor Cyan
docker ps --filter name=n8n-whatsapp-crm

Write-Host "`n[SUCCESS] n8n is ready!" -ForegroundColor Green
Write-Host "Access n8n UI at: http://localhost:5678" -ForegroundColor Green
