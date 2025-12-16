# Set-PhotoBoothMode.ps1
param(
    [string]$Mode,
    [switch]$List,
    [switch]$NoApplyNow  # if provided, do not kill processes immediately
)

$ErrorActionPreference = "Stop"
$EnvVarName = "BREEZE_MODE"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
${ModesPath}  = Join-Path $ScriptDir "PhotoBoothModes.json"

function Get-Modes() {
    if (!(Test-Path ${ModesPath})) {
        throw "Modes file not found: ${ModesPath}"
    }
    try {
        return Get-Content ${ModesPath} -Raw | ConvertFrom-Json
    } catch {
        throw "Failed to parse ${ModesPath}: $($_.Exception.Message)"
    }
}

function Show-Toast([string]$title, [string]$text) {
    try {
        Add-Type -AssemblyName System.Windows.Forms | Out-Null
        Add-Type -AssemblyName System.Drawing | Out-Null
        $notify = New-Object System.Windows.Forms.NotifyIcon
        $notify.Icon = [System.Drawing.SystemIcons]::Information
        $notify.Visible = $true
        $notify.BalloonTipTitle = $title
        $notify.BalloonTipText  = $text
        $notify.ShowBalloonTip(3000)
        Start-Sleep -Milliseconds 3200
        $notify.Dispose()
    } catch { }
}

# Get current mode or default to Normal
function Get-CurrentMode {
    $mMach = [Environment]::GetEnvironmentVariable($EnvVarName,'Machine')
    $mUser = [Environment]::GetEnvironmentVariable($EnvVarName,'User')
    $mProc = [Environment]::GetEnvironmentVariable($EnvVarName,'Process')
    $picked = $mMach
    if (-not $picked) { $picked = $mUser }
    if (-not $picked) { $picked = $mProc }
    if (-not $picked) { $picked = 'Normal' }
    return $picked
}

if ($List) {
    (Get-Modes).psobject.Properties.Name | Sort-Object | ForEach-Object { $_ }
    exit 0
}

# If no mode passed, show a simple GUI picker
if (-not $Mode) {
    Add-Type -AssemblyName System.Windows.Forms | Out-Null
    Add-Type -AssemblyName System.Drawing | Out-Null

    $modes = (Get-Modes).psobject.Properties.Name | Sort-Object
    if ($modes.Count -eq 0) {
        throw "No modes defined in ${ModesPath}"
    }

    $current = Get-CurrentMode

    $form = New-Object System.Windows.Forms.Form
    $form.Text = "Select PhotoBooth Mode"
    $form.Width = 380
    $form.Height = 160
    $form.StartPosition = "CenterScreen"

    $label = New-Object System.Windows.Forms.Label
    $label.Text = "Mode:"
    $label.Left = 10
    $label.Top  = 20
    $label.Width = 60
    $form.Controls.Add($label)

    $combo = New-Object System.Windows.Forms.ComboBox
    $combo.Left = 80
    $combo.Top  = 16
    $combo.Width = 270
    $combo.DropDownStyle = "DropDownList"
    [void]$combo.Items.AddRange($modes)
    $index = $modes.IndexOf($current)
    if ($index -ge 0) { $combo.SelectedIndex = $index } else { $combo.SelectedIndex = 0 }
    $form.Controls.Add($combo)

    $ok = New-Object System.Windows.Forms.Button
    $ok.Text  = "OK"
    $ok.Left  = 190
    $ok.Top   = 60
    $ok.Width = 75
    $ok.DialogResult = [System.Windows.Forms.DialogResult]::OK
    $form.AcceptButton = $ok
    $form.Controls.Add($ok)

    $cancel = New-Object System.Windows.Forms.Button
    $cancel.Text  = "Cancel"
    $cancel.Left  = 275
    $cancel.Top   = 60
    $cancel.Width = 75
    $cancel.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
    $form.CancelButton = $cancel
    $form.Controls.Add($cancel)

    $result = $form.ShowDialog()
    if ($result -ne [System.Windows.Forms.DialogResult]::OK) {
        Write-Host "Selection canceled."
        exit 1
    }
    $Mode = $combo.SelectedItem
}

# Validate mode exists
$m = Get-Modes
if (-not ($m.psobject.Properties.Name -contains $Mode)) {
    throw "Unknown mode '$Mode'. Use -List to see options."
}

# Persist at machine level so services and other users see it
& cmd /c setx $EnvVarName "$Mode" /M | Out-Null
[Environment]::SetEnvironmentVariable($EnvVarName, $Mode, 'Process') | Out-Null

# Apply now: stop all known processes so watchdog relaunches with correct args
if (-not $NoApplyNow) {
    $allProcs = @()
    foreach ($p in $m.psobject.Properties.Value) {
        if ($p.processes) { $allProcs += $p.processes.psobject.Properties.Name }
    }
    $allProcs = $allProcs | Select-Object -Unique
    foreach ($name in $allProcs) {
        Get-Process -Name $name -ErrorAction SilentlyContinue | ForEach-Object {
            try { Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue } catch {}
        }
    }
}

Show-Toast -title "PhotoBooth Mode" -text "Mode set to: $Mode"
Write-Host "Mode set to: $Mode"
exit 0
