# SetupHealthMonitoring.ps1
# Downloads and sets up health monitoring files and scheduled task for PhotoBooth
# Idempotent: Safe to run multiple times, handles network failures gracefully

# Hardcoded download URLs
$HealthMonitorUrl = "https://storage.googleapis.com/photobooz_script_assets/health_monitoring/PhotoBoothHealthMonitor.ps1"
$TaskXmlUrl = "https://storage.googleapis.com/photobooz_script_assets/health_monitoring/Photobooth%20Healthcheck.xml"

# Configuration
$MaxRetries = 3
$RetryDelaySeconds = 2

# Base paths
$ScriptsFolder = "C:\Users\Administrator\Desktop\Photobooth Settings\Scripts"
$TempFolder = $env:TEMP

# Track results
$Results = @{
    Success = @()
    Failed = @()
}

# Ensure directories exist (idempotent)
Write-Host "Ensuring directories exist..." -ForegroundColor Cyan
if (-not (Test-Path $ScriptsFolder)) {
    New-Item -Path $ScriptsFolder -ItemType Directory -Force | Out-Null
    Write-Host "Created Scripts folder: $ScriptsFolder" -ForegroundColor Green
} else {
    Write-Host "Scripts folder already exists: $ScriptsFolder" -ForegroundColor Gray
}

# Function to download a file with retry logic
function Download-File {
    param(
        [string]$Url,
        [string]$DestinationPath,
        [string]$Description
    )
    
    # Check if file already exists (idempotent check)
    if (Test-Path $DestinationPath) {
        Write-Host "$Description already exists: $DestinationPath" -ForegroundColor Yellow
        Write-Host "Re-downloading to ensure latest version..." -ForegroundColor Gray
    }
    
    $attempt = 0
    while ($attempt -lt $MaxRetries) {
        $attempt++
        
        try {
            Write-Host "[Attempt $attempt/$MaxRetries] Downloading $Description..." -ForegroundColor Cyan
            Write-Host "  From: $Url" -ForegroundColor Gray
            Write-Host "  To: $DestinationPath" -ForegroundColor Gray
            
            # Use Invoke-WebRequest for PowerShell 5.1+ compatibility
            $ProgressPreference = 'SilentlyContinue'
            $ErrorActionPreference = 'Stop'
            Invoke-WebRequest -Uri $Url -OutFile $DestinationPath -UseBasicParsing -TimeoutSec 30
            
            if (Test-Path $DestinationPath) {
                $fileSize = (Get-Item $DestinationPath).Length
                if ($fileSize -gt 0) {
                    Write-Host "Successfully downloaded $Description ($fileSize bytes)" -ForegroundColor Green
                    return $true
                } else {
                    Write-Host "Downloaded file is empty, will retry..." -ForegroundColor Yellow
                    Remove-Item $DestinationPath -Force -ErrorAction SilentlyContinue
                }
            } else {
                Write-Host "Download failed: File not found at destination" -ForegroundColor Yellow
            }
        }
        catch {
            Write-Host "Error on attempt $attempt : $($_.Exception.Message)" -ForegroundColor Yellow
            if (Test-Path $DestinationPath) {
                Remove-Item $DestinationPath -Force -ErrorAction SilentlyContinue
            }
        }
        
        if ($attempt -lt $MaxRetries) {
            Write-Host "Waiting $RetryDelaySeconds seconds before retry..." -ForegroundColor Gray
            Start-Sleep -Seconds $RetryDelaySeconds
        }
    }
    
    Write-Host "Failed to download $Description after $MaxRetries attempts" -ForegroundColor Red
    return $false
}

# Download PhotoBoothHealthMonitor.ps1
Write-Host "`n=== Step 1: PhotoBoothHealthMonitor.ps1 ===" -ForegroundColor Cyan
$HealthMonitorPath = Join-Path $ScriptsFolder "PhotoBoothHealthMonitor.ps1"
if (Download-File -Url $HealthMonitorUrl -DestinationPath $HealthMonitorPath -Description "PhotoBoothHealthMonitor.ps1") {
    $Results.Success += "PhotoBoothHealthMonitor.ps1"
} else {
    $Results.Failed += "PhotoBoothHealthMonitor.ps1"
}

# Download Task XML
Write-Host "`n=== Step 2: Task XML ===" -ForegroundColor Cyan
$TaskXmlPath = Join-Path $TempFolder "PhotoboothHealthcheck.xml"
if (Download-File -Url $TaskXmlUrl -DestinationPath $TaskXmlPath -Description "Task XML") {
    $Results.Success += "Task XML"
} else {
    $Results.Failed += "Task XML"
    $TaskXmlPath = $null
}

# Create/Update Scheduled Task
Write-Host "`n=== Step 3: Scheduled Task ===" -ForegroundColor Cyan

if ($TaskXmlPath -and (Test-Path $TaskXmlPath)) {
    try {
        # Extract task name from XML
        $xmlContent = Get-Content $TaskXmlPath -Raw
        $xml = [xml]$xmlContent
        $uri = $xml.Task.RegistrationInfo.URI
        if ($uri -match '^\\(.+)$') {
            $TaskName = $matches[1]
            Write-Host "Extracted task name from XML: $TaskName" -ForegroundColor Gray
        } else {
            throw "Could not extract task name from XML URI: $uri"
        }
        
        # Check if task already exists
        $existingTask = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
        
        if ($existingTask) {
            Write-Host "Task '$TaskName' already exists. Updating..." -ForegroundColor Yellow
            
            # Check if task is currently running
            $taskInfo = Get-ScheduledTaskInfo -TaskName $TaskName -ErrorAction SilentlyContinue
            $wasRunning = $false
            
            if ($taskInfo -and $taskInfo.State -eq 'Running') {
                Write-Host "Task is currently running. Stopping it first..." -ForegroundColor Yellow
                try {
                    Stop-ScheduledTask -TaskName $TaskName -ErrorAction Stop
                    Write-Host "Task stopped successfully" -ForegroundColor Gray
                    $wasRunning = $true
                    # Wait a moment for the task to fully stop
                    Start-Sleep -Seconds 2
                } catch {
                    Write-Host "Warning: Could not stop running task: $($_.Exception.Message)" -ForegroundColor Yellow
                    Write-Host "Attempting to unregister anyway..." -ForegroundColor Gray
                }
            }
            
            # Unregister existing task
            Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction Stop
            Write-Host "Unregistered existing task" -ForegroundColor Gray
        }
        
        # Register the task from XML
        Write-Host "Registering scheduled task from XML..." -ForegroundColor Cyan
        Register-ScheduledTask -Xml (Get-Content $TaskXmlPath -Raw) -TaskName $TaskName -Force | Out-Null
        
        Write-Host "Scheduled task '$TaskName' created/updated successfully" -ForegroundColor Green
        $Results.Success += "Scheduled Task"
        
        # Start the task (stop it first if already running, then start fresh)
        Write-Host "`n=== Step 4: Starting Task ===" -ForegroundColor Cyan
        try {
            # Check if task is already running
            $taskInfo = Get-ScheduledTaskInfo -TaskName $TaskName -ErrorAction SilentlyContinue
            if ($taskInfo -and $taskInfo.State -eq 'Running') {
                Write-Host "Task is already running. Stopping it first..." -ForegroundColor Yellow
                try {
                    Stop-ScheduledTask -TaskName $TaskName -ErrorAction Stop
                    Write-Host "Task stopped successfully" -ForegroundColor Gray
                    # Wait a moment for the task to fully stop
                    Start-Sleep -Seconds 2
                } catch {
                    Write-Host "Warning: Could not stop running task: $($_.Exception.Message)" -ForegroundColor Yellow
                }
            }
            
            # Start the task (fresh start)
            Start-ScheduledTask -TaskName $TaskName -ErrorAction Stop
            Write-Host "Task '$TaskName' started successfully" -ForegroundColor Green
            $Results.Success += "Task Start"
        }
        catch {
            Write-Host "Warning: Task registered but could not be started: $($_.Exception.Message)" -ForegroundColor Yellow
            Write-Host "The task will run according to its schedule" -ForegroundColor Gray
            $Results.Failed += "Task Start"
        }
    }
    catch {
        Write-Host "Error creating/updating scheduled task: $($_.Exception.Message)" -ForegroundColor Red
        $Results.Failed += "Scheduled Task"
    }
    finally {
        # Clean up temporary XML file
        if (Test-Path $TaskXmlPath) {
            Remove-Item $TaskXmlPath -Force -ErrorAction SilentlyContinue
        }
    }
} else {
    Write-Host "Skipping task creation - Task XML not available" -ForegroundColor Yellow
    $Results.Failed += "Scheduled Task (prerequisite missing)"
}

# Summary
Write-Host "`n=== Setup Summary ===" -ForegroundColor Cyan
Write-Host "Successfully processed: $($Results.Success.Count) items" -ForegroundColor Green
if ($Results.Success.Count -gt 0) {
    $Results.Success | ForEach-Object { Write-Host "  ✓ $_" -ForegroundColor Green }
}

if ($Results.Failed.Count -gt 0) {
    Write-Host "`nFailed: $($Results.Failed.Count) items" -ForegroundColor Red
    $Results.Failed | ForEach-Object { Write-Host "  ✗ $_" -ForegroundColor Red }
    Write-Host "`nNote: You can re-run this script to retry failed operations." -ForegroundColor Yellow
    exit 1
} else {
    Write-Host "`n=== Setup Complete ===" -ForegroundColor Green
    Write-Host "Health monitoring has been set up successfully!" -ForegroundColor Green
    exit 0
}

