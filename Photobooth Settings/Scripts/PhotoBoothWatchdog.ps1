# PhotoBoothWatchdog.ps1  (PowerShell 5.1 compatible, minimal and robust)

# === Config ===
$ModeEnvVarNew = "BREEZE_MODE"
$ModeEnvVarOld = "BREEZE_MAINTENANCE"  # legacy: '1' maintenance, else normal
$ScriptDir     = Split-Path -Parent $MyInvocation.MyCommand.Path
$ModesPath     = Join-Path $ScriptDir "PhotoBoothModes.json"
$LogDir        = Join-Path $ScriptDir "logs"
$LogFile       = Join-Path $LogDir "PhotoBoothWatchdog.log"
$PollSeconds   = 5

# === Logging ===
function Ensure-LogDir {
    if (!(Test-Path $LogDir)) { New-Item -Path $LogDir -ItemType Directory -Force | Out-Null }
}
function Log([string]$msg) {
    Ensure-LogDir
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Add-Content -Path $LogFile -Value ("[{0}] {1}" -f $timestamp, $msg)
}

# === Modes ===
function Load-Modes {
    if (!(Test-Path $ModesPath)) { throw ("Modes file not found: {0}" -f $ModesPath) }
    try { return Get-Content $ModesPath -Raw | ConvertFrom-Json } catch { throw ("Failed to parse {0}: {1}" -f $ModesPath, $_.Exception.Message) }
}

function Pick-Mode {
    $mMach = [Environment]::GetEnvironmentVariable($ModeEnvVarNew,'Machine')
    $mUser = [Environment]::GetEnvironmentVariable($ModeEnvVarNew,'User')
    $mProc = [Environment]::GetEnvironmentVariable($ModeEnvVarNew,'Process')

    $picked = $mMach
    if (-not $picked) { $picked = $mUser }
    if (-not $picked) { $picked = $mProc }

    if (-not $picked) {
        $legacy = [Environment]::GetEnvironmentVariable($ModeEnvVarOld,'Machine')
        if (-not $legacy) { $legacy = [Environment]::GetEnvironmentVariable($ModeEnvVarOld,'User') }
        if (-not $legacy) { $legacy = [Environment]::GetEnvironmentVariable($ModeEnvVarOld,'Process') }
        if ($legacy -eq '1') { $picked = 'Maintenance' } else { $picked = 'Normal' }
    }

    if (-not $picked) { $picked = 'Normal' }

    Log ("Picked mode: " + $picked)
    return $picked
}

# === Process helpers ===
function Ensure-NotRunning([string]$processName) {
    Get-Process -Name $processName -ErrorAction SilentlyContinue | ForEach-Object {
        try { Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue; Log ("Stopped " + $processName + " PID " + $_.Id) } catch {}
    }
}

function To-ArgArray($val) {
    if ($null -eq $val) { return @() }
    if ($val -is [System.Array]) {
        $arr = @()
        foreach ($t in $val) { if ($null -ne $t) { $arr += [string]$t } }
        return $arr
    }
    $s = [string]$val
    if ([string]::IsNullOrWhiteSpace($s)) { return @() }
    return @($s)
}


function Ensure-Running([string]$exe, $procArgs) {
    if (!(Test-Path $exe)) { Log ("Missing exe: " + $exe); return }
    $procName = [System.IO.Path]::GetFileNameWithoutExtension($exe)
    $desired  = To-ArgArray $procArgs

    $existing = Get-Process -Name $procName -ErrorAction SilentlyContinue
    if ($existing) { return }

    try {
        if ($procName -ieq 'MDBPayment') {
            Log ("Starting " + $procName + " minimized")
            Start-Process -FilePath $exe -WindowStyle Minimized
        } else {
            if ($desired.Count -gt 0) {
                $quoted = @()
                foreach ($tok in $desired) {
                    if ($tok -match '\s') { $quoted += ('"'+$tok+'"') } else { $quoted += $tok }
                }
                $argLine = ($quoted -join ' ')
                Log ("Starting " + $procName + " with argLine: " + $argLine)
                Start-Process -FilePath $exe -ArgumentList $argLine
            } else {
                Log ("Starting " + $procName + " with no args")
                Start-Process -FilePath $exe
            }
        }
    } catch { Log ("Failed to start " + $procName + ": " + $_.Exception.Message) }
}
# === Main loop ===
$lastMode = $null
while ($true) {
    try {
        $modes = Load-Modes
        $modeName = Pick-Mode
        if (-not ($modes.psobject.Properties.Name -contains $modeName)) { Log ("Unknown mode " + $modeName + " -> using Normal"); $modeName = 'Normal' }
        $mode = $modes.$modeName

        if ($lastMode -ne $modeName) {
            # Stop everything we know about, then start what the new mode wants
            $allProcs = @()
            foreach ($p in $modes.psobject.Properties.Value) {
                if ($p.processes) { $allProcs += $p.processes.psobject.Properties.Name }
            }
            $allProcs = $allProcs | Select-Object -Unique
            if ($allProcs.Count -gt 0) { Log ("Stopping on mode change: " + ($allProcs -join ", ")) }
            foreach ($n in $allProcs) { Ensure-NotRunning $n }
            $lastMode = $modeName
        }

        if ($mode.suspend -eq $true) {
            # Nothing should run
            $allProcs = @()
            foreach ($p in $modes.psobject.Properties.Value) { if ($p.processes) { $allProcs += $p.processes.psobject.Properties.Name } }
            $allProcs = $allProcs | Select-Object -Unique
            foreach ($n in $allProcs) { Ensure-NotRunning $n }
        } else {
            # Start all processes defined for this mode with their args
            foreach ($prop in $mode.processes.psobject.Properties) {
                $exe  = $prop.Value.exe
                $parg = $prop.Value.args
                Ensure-Running -exe $exe -procArgs $parg
            }
            # Stop anything else known that is not listed
            $allowed = @()
            if ($mode.processes) { $allowed += $mode.processes.psobject.Properties.Name }
            $allowed = $allowed | Select-Object -Unique
            $allKnown = @()
            foreach ($p in $modes.psobject.Properties.Value) { if ($p.processes) { $allKnown += $p.processes.psobject.Properties.Name } }
            $allKnown = $allKnown | Select-Object -Unique
            $others = $allKnown | Where-Object { -not ($allowed -contains $_) }
            foreach ($n in $others) { Ensure-NotRunning $n }
        }
    } catch { Log ("Loop error: " + $_.Exception.Message) }

    Start-Sleep -Seconds $PollSeconds
}
