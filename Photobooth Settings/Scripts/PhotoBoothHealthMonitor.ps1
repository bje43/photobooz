# PhotoBoothHealthMonitor.ps1
# Monitors photobooth health and reports to API endpoint

# === Config ===
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$SettingsPath = Join-Path (Split-Path -Parent $ScriptDir) "settings.json"
$LogDir = Join-Path $ScriptDir "logs"
$LogFile = Join-Path $LogDir "PhotoBoothHealthMonitor.log"
$PollMinutes = 5
$PrinterNameContains = "hiti"  # Case-insensitive
$QueueStaleMinutes = 3  # Document in queue longer than this = jammed

# Make sure these are swapped out w/ prod values later
# Full URL to health endpoint, e.g. https://your-api.com/api/health/ping
$HealthEndpoint = "https://65699df3d829.ngrok-free.app/api/health/ping"  
$ApiKey = "DEVTOKEN"  # Set this to your API key (must match API_KEY in your server .env)


# === Logging ===
function Ensure-LogDir {
    if (!(Test-Path $LogDir)) { New-Item -Path $LogDir -ItemType Directory -Force | Out-Null }
}

function Log([string]$msg) {
    Ensure-LogDir
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMsg = "[{0}] {1}" -f $timestamp, $msg
    Add-Content -Path $LogFile -Value $logMsg
    Write-Host $logMsg
}

# === Timezone Conversion ===
function Convert-WindowsTimezoneToIANA {
    param([string]$WindowsTimezone)
    
    # Map Windows timezone IDs to IANA timezone identifiers
    $timezoneMap = @{
        'Eastern Standard Time' = 'America/New_York'
        'Central Standard Time' = 'America/Chicago'
        'Mountain Standard Time' = 'America/Denver'
        'Pacific Standard Time' = 'America/Los_Angeles'
        'Alaska Standard Time' = 'America/Anchorage'
        'Hawaiian Standard Time' = 'Pacific/Honolulu'
        'Atlantic Standard Time' = 'America/Halifax'
        'Newfoundland Standard Time' = 'America/St_Johns'
        'Central European Standard Time' = 'Europe/Berlin'
        'GMT Standard Time' = 'Europe/London'
        'W. Europe Standard Time' = 'Europe/Berlin'
        'Romance Standard Time' = 'Europe/Paris'
        'Russian Standard Time' = 'Europe/Moscow'
        'Tokyo Standard Time' = 'Asia/Tokyo'
        'China Standard Time' = 'Asia/Shanghai'
        'India Standard Time' = 'Asia/Kolkata'
        'AUS Eastern Standard Time' = 'Australia/Sydney'
        'Cen. Australia Standard Time' = 'Australia/Adelaide'
        'AUS Central Standard Time' = 'Australia/Darwin'
        'E. Australia Standard Time' = 'Australia/Brisbane'
        'W. Australia Standard Time' = 'Australia/Perth'
    }
    
    # If it's already an IANA timezone (contains '/'), return as-is
    if ($WindowsTimezone -match '/') {
        return $WindowsTimezone
    }
    
    # Convert Windows timezone to IANA
    if ($timezoneMap.ContainsKey($WindowsTimezone)) {
        return $timezoneMap[$WindowsTimezone]
    }
    
    # Default to UTC if unknown
    Log "WARNING: Unknown Windows timezone '$WindowsTimezone', defaulting to UTC"
    return 'UTC'
}

# === Settings ===
function Get-BoothId {
    if (!(Test-Path $SettingsPath)) {
        Log "WARNING: settings.json not found at $SettingsPath"
        return $null
    }
    try {
        $settings = Get-Content $SettingsPath -Raw | ConvertFrom-Json
        return $settings.boothId
    } catch {
        Log "ERROR: Failed to parse settings.json: $($_.Exception.Message)"
        return $null
    }
}

# === Printer Checks ===
function Get-PrinterStatus {
    $result = @{
        Connected = $false
        Jammed = $false
        PrinterName = $null
        QueueCount = 0
        OldestJobAgeMinutes = $null
    }

    try {
        # Find printer with "hiti" in name (case-insensitive)
        $printers = Get-Printer -ErrorAction SilentlyContinue | Where-Object {
            $_.Name -like "*$PrinterNameContains*"
        }

        if ($printers.Count -eq 0) {
            Log "No printer found with '$PrinterNameContains' in name"
            return $result
        }

        # Use the first matching printer
        $printer = $printers[0]
        $result.PrinterName = $printer.Name
        $result.Connected = $true

        Log "Found printer: $($printer.Name)"

        # Check print queue
        try {
            $allJobs = Get-PrintJob -PrinterName $printer.Name -ErrorAction SilentlyContinue
            
            # Handle case where Get-PrintJob returns a single object vs array
            if ($null -eq $allJobs) {
                $allJobs = @()
            } elseif ($allJobs -isnot [Array]) {
                $allJobs = @($allJobs)
            }
            
            Log "All print jobs: $($allJobs.Count) total"
            
            # Filter out completed/printed jobs (JobStatus 128 = printed/completed)
            # Only consider active jobs (queued, printing, paused, etc.)
            # JobStatus 8208 appears to be actively printing
            $activeJobs = $allJobs | Where-Object {
                $_.JobStatus -ne 128
            }
            
            $result.QueueCount = $activeJobs.Count
            Log "Active print jobs: $($activeJobs.Count) (excluding completed jobs)"

            if ($activeJobs.Count -gt 0) {
                $now = Get-Date
                $oldestJob = $activeJobs | Sort-Object SubmittedTime | Select-Object -First 1
                
                # Handle different SubmittedTime formats
                $submittedTime = $oldestJob.SubmittedTime
                if ($submittedTime -is [String] -and $submittedTime -match '\/Date\((\d+)\)\/') {
                    # Convert .NET JSON date format to DateTime
                    $timestamp = [long]$matches[1]
                    $submittedTime = [DateTimeOffset]::FromUnixTimeMilliseconds($timestamp).LocalDateTime
                }
                
                $age = ($now - $submittedTime).TotalMinutes
                $result.OldestJobAgeMinutes = [math]::Round($age, 2)

                Log "Oldest active job: Status=$($oldestJob.JobStatus), Age=$([math]::Round($age, 2)) minutes, Submitted=$submittedTime"

                if ($age -gt $QueueStaleMinutes) {
                    $result.Jammed = $true
                    Log "Printer appears jammed: oldest active job is $([math]::Round($age, 2)) minutes old (threshold: $QueueStaleMinutes minutes)"
                } else {
                    Log "Printer queue OK: $($activeJobs.Count) active job(s), oldest is $([math]::Round($age, 2)) minutes old"
                }
            } else {
                Log "Printer queue is empty (no active jobs)"
            }
        } catch {
            Log "WARNING: Could not check print queue: $($_.Exception.Message)"
            # If we can't check queue, assume not jammed but log warning
        }
    } catch {
        Log "ERROR checking printer: $($_.Exception.Message)"
    }

    return $result
}

# === Monitor Check ===
function Get-MonitorStatus {
    $result = @{
        Connected = $false
    }

    try {
        # Check via Screen class for connected displays
        $screenCount = [System.Windows.Forms.Screen]::AllScreens.Count
        
        # Check WMI for active monitors
        $wmiActive = Get-CimInstance -Namespace root\wmi -ClassName WmiMonitorBasicDisplayParams -ErrorAction SilentlyContinue |
                     Where-Object { $_.Active -eq $true }
        
        $activeMonitorCount = if ($wmiActive) { 
            if ($wmiActive -is [Array]) { $wmiActive.Count } else { 1 }
        } else { 
            0 
        }
        
        Log "Monitor check: Screen class reports $screenCount screen(s), WMI reports $activeMonitorCount active monitor(s)"
        
        # Consider monitor connected if we have at least one screen or one active WMI monitor
        if ($screenCount -gt 0 -or $activeMonitorCount -gt 0) {
            $result.Connected = $true
            Log "Monitor check: Monitor detected (connected and active)"
        } else {
            Log "Monitor check: No active displays detected"
        }
    } catch {
        Log "ERROR checking monitor: $($_.Exception.Message)"
        # Default to false if we can't determine
    }

    return $result
}

# === Mode Check ===
function Get-BoothMode {
    $mode = [Environment]::GetEnvironmentVariable("BREEZE_MODE", "Machine")
    if (-not $mode) { $mode = [Environment]::GetEnvironmentVariable("BREEZE_MODE", "User") }
    if (-not $mode) { $mode = [Environment]::GetEnvironmentVariable("BREEZE_MODE", "Process") }
    if (-not $mode) { $mode = "Unknown" }

    Log "Booth mode: $mode"
    return $mode
}

# === Health Status Summary ===
function Get-HealthStatus {
    $printer = Get-PrinterStatus
    $monitor = Get-MonitorStatus
    $mode = Get-BoothMode
    $boothId = Get-BoothId

    # Determine overall status
    $status = "healthy"
    $issues = @()

    if (-not $printer.Connected) {
        $status = "warning"
        $issues += "Printer not connected"
    } elseif ($printer.Jammed) {
        $status = "error"
        $issues += "Printer jammed (queue stale: $($printer.OldestJobAgeMinutes) minutes)"
    }

    if (-not $monitor.Connected) {
        if ($status -eq "healthy") { $status = "warning" }
        $issues += "Monitor not connected"
    }

    if ($mode -eq "Unknown") {
        if ($status -eq "healthy") { $status = "warning" }
        $issues += "Booth mode unknown"
    }

    $message = if ($issues.Count -gt 0) {
        $issues -join "; "
    } else {
        "All systems operational"
    }

    return @{
        Status = $status
        Message = $message
        Printer = $printer
        Monitor = $monitor
        Mode = $mode
        BoothId = $boothId
    }
}

# === Send Health Ping ===
function Send-HealthPing {
    param($healthData)

    if ([string]::IsNullOrWhiteSpace($HealthEndpoint)) {
        Log "ERROR: HealthEndpoint not configured. Set \$HealthEndpoint in the script."
        return $false
    }

    if ([string]::IsNullOrWhiteSpace($ApiKey)) {
        Log "ERROR: ApiKey not configured. Set \$ApiKey in the script."
        return $false
    }

    if (-not $healthData.BoothId) {
        Log "ERROR: BoothId not found in settings.json"
        return $false
    }

    try {
        # Convert Windows timezone ID to IANA timezone identifier
        $windowsTz = [System.TimeZoneInfo]::Local.Id
        $timezone = Convert-WindowsTimezoneToIANA -WindowsTimezone $windowsTz
        $timezoneOffset = [System.TimeZoneInfo]::Local.GetUtcOffset([DateTime]::UtcNow).TotalHours

        # Build payload matching HealthPingDto interface:
        # - boothId (required): string
        # - name (optional): string
        # - status (required): string
        # - message (optional): string
        # - metadata (optional): Record<string, any>
        $payload = @{
            boothId = $healthData.BoothId
            name = "Booth $($healthData.BoothId)"
            status = $healthData.Status
            message = $healthData.Message
            metadata = @{
                printer = @{
                    connected = $healthData.Printer.Connected
                    jammed = $healthData.Printer.Jammed
                    name = $healthData.Printer.PrinterName
                    queueCount = $healthData.Printer.QueueCount
                    oldestJobAgeMinutes = $healthData.Printer.OldestJobAgeMinutes
                }
                monitor = @{
                    connected = $healthData.Monitor.Connected
                }
                mode = $healthData.Mode
                timezone = $timezone
                timezoneOffset = $timezoneOffset
            }
        } | ConvertTo-Json -Depth 10 -Compress

        # Headers must include x-api-key for authentication
        $headers = @{
            "Content-Type" = "application/json"
            "x-api-key" = $ApiKey
        }

        Log "Sending health ping to $HealthEndpoint"
        Log "Payload: $payload"

        $response = Invoke-RestMethod -Uri $HealthEndpoint -Method Post -Body $payload -Headers $headers -ErrorAction Stop

        Log "Health ping sent successfully: $($response | ConvertTo-Json -Compress)"
        return $true
    } catch {
        Log "ERROR sending health ping: $($_.Exception.Message)"
        if ($_.Exception.Response) {
            try {
                $reader = New-Object System.IO.StreamReader($_.Exception.Response.GetResponseStream())
                $responseBody = $reader.ReadToEnd()
                Log "Response body: $responseBody"
            } catch {}
        }
        return $false
    }
}

# === Main Loop ===
function Start-HealthMonitor {
    Log "=== PhotoBooth Health Monitor Started ==="
    Log "Poll interval: $PollMinutes minutes"
    Log "Health endpoint: $(if ($HealthEndpoint) { $HealthEndpoint } else { 'NOT CONFIGURED' })"
    Log "Booth ID: $(Get-BoothId)"

    while ($true) {
        try {
            Log "--- Health Check Cycle ---"
            $health = Get-HealthStatus
            Send-HealthPing -healthData $health
        } catch {
            Log "ERROR in main loop: $($_.Exception.Message)"
        }

        $sleepSeconds = $PollMinutes * 60
        Log "Sleeping for $PollMinutes minutes..."
        Start-Sleep -Seconds $sleepSeconds
    }
}

# === Entry Point ===
# Add required assemblies for monitor check
try {
    Add-Type -AssemblyName System.Windows.Forms -ErrorAction SilentlyContinue
} catch {}

# Start monitoring
Start-HealthMonitor

