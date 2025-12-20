# SetupMaintenanceMode.ps1
# Downloads and sets up maintenance mode files for PhotoBooth
# Idempotent: Safe to run multiple times, handles network failures gracefully

# Hardcoded download URLs
$WatchdogUrl = "https://storage.googleapis.com/photobooz_script_assets/new_modes/PhotoBoothWatchdog.ps1"
$SetPhotoBoothModePs1Url = "https://storage.googleapis.com/photobooz_script_assets/new_modes/Set-PhotoBoothMode.ps1"
$SetPhotoBoothModeBatUrl = "https://storage.googleapis.com/photobooz_script_assets/new_modes/Set-PhotoBoothMode.bat"
$PhotoBoothModesJsonUrl = "https://storage.googleapis.com/photobooz_script_assets/new_modes/PhotoBoothModes.json"
$FreeXmlUrl = "https://storage.googleapis.com/photobooz_script_assets/new_modes/Free.xml"

# Configuration
$MaxRetries = 3
$RetryDelaySeconds = 2

# Base paths
$ScriptsFolder = "C:\Users\Administrator\Desktop\Photobooth Settings\Scripts"
$SettingsFolder = "C:\Users\Administrator\Desktop\Photobooth Settings"
$FreeFolder = Join-Path $SettingsFolder "Free"

# Get desktop path with fallback
$DesktopPath = [Environment]::GetFolderPath("Desktop")
if ([string]::IsNullOrEmpty($DesktopPath)) {
    # Fallback to Administrator's desktop if GetFolderPath fails
    $DesktopPath = "C:\Users\Administrator\Desktop"
    Write-Host "Using fallback desktop path: $DesktopPath" -ForegroundColor Yellow
}

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

if (-not (Test-Path $FreeFolder)) {
    New-Item -Path $FreeFolder -ItemType Directory -Force | Out-Null
    Write-Host "Created Free folder: $FreeFolder" -ForegroundColor Green
} else {
    Write-Host "Free folder already exists: $FreeFolder" -ForegroundColor Gray
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

# Download and replace PhotoBoothWatchdog.ps1
Write-Host "`n=== Step 1: PhotoBoothWatchdog.ps1 ===" -ForegroundColor Cyan
$WatchdogPath = Join-Path $ScriptsFolder "PhotoBoothWatchdog.ps1"
if (Download-File -Url $WatchdogUrl -DestinationPath $WatchdogPath -Description "PhotoBoothWatchdog.ps1") {
    $Results.Success += "PhotoBoothWatchdog.ps1"
} else {
    $Results.Failed += "PhotoBoothWatchdog.ps1"
}

# Download Set-PhotoBoothMode.ps1
Write-Host "`n=== Step 2: Set-PhotoBoothMode.ps1 ===" -ForegroundColor Cyan
$SetPhotoBoothModePs1Path = Join-Path $ScriptsFolder "Set-PhotoBoothMode.ps1"
if (Download-File -Url $SetPhotoBoothModePs1Url -DestinationPath $SetPhotoBoothModePs1Path -Description "Set-PhotoBoothMode.ps1") {
    $Results.Success += "Set-PhotoBoothMode.ps1"
} else {
    $Results.Failed += "Set-PhotoBoothMode.ps1"
}

# Download Set-PhotoBoothMode.bat
Write-Host "`n=== Step 3: Set-PhotoBoothMode.bat ===" -ForegroundColor Cyan
$SetPhotoBoothModeBatPath = Join-Path $ScriptsFolder "Set-PhotoBoothMode.bat"
if (Download-File -Url $SetPhotoBoothModeBatUrl -DestinationPath $SetPhotoBoothModeBatPath -Description "Set-PhotoBoothMode.bat") {
    $Results.Success += "Set-PhotoBoothMode.bat"
} else {
    $Results.Failed += "Set-PhotoBoothMode.bat"
}

# Download PhotoBoothModes.json
Write-Host "`n=== Step 4: PhotoBoothModes.json ===" -ForegroundColor Cyan
$ModesJsonPath = Join-Path $ScriptsFolder "PhotoBoothModes.json"
if (Download-File -Url $PhotoBoothModesJsonUrl -DestinationPath $ModesJsonPath -Description "PhotoBoothModes.json") {
    $Results.Success += "PhotoBoothModes.json"
} else {
    $Results.Failed += "PhotoBoothModes.json"
}

# Create desktop shortcut for Set-PhotoBoothMode.bat (idempotent - overwrites if exists)
Write-Host "`n=== Step 5: Desktop Shortcut ===" -ForegroundColor Cyan

# Validate desktop path exists
if ([string]::IsNullOrEmpty($DesktopPath) -or -not (Test-Path $DesktopPath)) {
    Write-Host "Desktop path not accessible: $DesktopPath" -ForegroundColor Red
    Write-Host "Skipping shortcut creation" -ForegroundColor Yellow
    $Results.Failed += "Desktop Shortcut (desktop path not accessible)"
} elseif (Test-Path $SetPhotoBoothModeBatPath) {
    try {
        $ShortcutPath = Join-Path $DesktopPath "Set-PhotoBoothMode.lnk"
        $WshShell = New-Object -ComObject WScript.Shell
        $Shortcut = $WshShell.CreateShortcut($ShortcutPath)
        $Shortcut.TargetPath = $SetPhotoBoothModeBatPath
        $Shortcut.WorkingDirectory = $ScriptsFolder
        $Shortcut.Description = "Set PhotoBooth Mode"
        $Shortcut.Save()
        
        Write-Host "Desktop shortcut created/updated: $ShortcutPath" -ForegroundColor Green
        $Results.Success += "Desktop Shortcut"
    }
    catch {
        Write-Host "Error creating shortcut: $($_.Exception.Message)" -ForegroundColor Red
        $Results.Failed += "Desktop Shortcut"
    }
} else {
    Write-Host "Skipping shortcut creation - Set-PhotoBoothMode.bat not available" -ForegroundColor Yellow
    $Results.Failed += "Desktop Shortcut (prerequisite missing)"
}

# Download Free.xml to Free folder
Write-Host "`n=== Step 6: Free.xml ===" -ForegroundColor Cyan
$FreeXmlPath = Join-Path $FreeFolder "Free.xml"
if (Download-File -Url $FreeXmlUrl -DestinationPath $FreeXmlPath -Description "Free.xml") {
    $Results.Success += "Free.xml"
} else {
    $Results.Failed += "Free.xml"
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
    Write-Host "`nNote: You can re-run this script to retry failed downloads." -ForegroundColor Yellow
    exit 1
} else {
    Write-Host "`n=== Setup Complete ===" -ForegroundColor Green
    Write-Host "All files have been downloaded and configured successfully!" -ForegroundColor Green
    exit 0
}

