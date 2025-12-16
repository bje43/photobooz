<#  Clean & upload CSVs to GCS with per-booth folders and persistent UUID filenames.
    Finds a sibling folder named "Marketing" next to Scripts\.
    Reads booth id from a sibling JSON named "settings.json" located next to Scripts\ and Marketing\.
    Handles headerless input rows exactly like your examples.
    Skips gracefully when an input is missing.
    Stores UUID JSON + log next to this script. Schedule with Task Scheduler if desired.

    IMPORTANT:
      - Bucket must use fine-grained ACLs (Uniform bucket-level access OFF).
      - Easiest path: set the bucket's *Default object ACL* to Public (Reader)
        so new uploads are public without sending x-goog-acl.
#>

param(
  [string]$SourceFolder  # optional override for the Marketing folder; if omitted we auto-discover ..\Marketing
)

# ── Script-local storage & logging ──────────────────────────────────────────────
Set-Location -Path $PSScriptRoot
$UuidStoreDir = $PSScriptRoot
$LogFile = Join-Path $PSScriptRoot "csv-sync.log"
Start-Transcript -Path $LogFile -Append | Out-Null

try {
  # ── CONFIG (YOUR VALUES) ─────────────────────────────────────────────────────
  # Bucket + HMAC (Interoperability) credentials
  $Bucket      = "photobooz-marketing"
  $GcsAccessId = "GOOG1E2MXYNIMFBZPLSHLBBBECNBITTD3AOHHL2SLUYXY67KUUC4CM3ZY4RCN"
  $GcsSecret   = "rculchxPDFS/nzXDT5x9dCff4KQPpf98vn9Bb06V"

  # File discovery patterns (optional: adjust if your filenames differ)
  $EmailCsvPatterns = @("emails.csv")
  $TextCsvPatterns  = @("texts.csv")

    # Ensure HttpClient types exist (WinPS 5.1 sometimes needs this)
    if (-not ("System.Net.Http.HttpClient" -as [type])) {
      Add-Type -AssemblyName System.Net.Http
    }


  # ── Sibling discovery (Marketing + settings.json) ────────────────────────────
  function Get-BaseDir {
    # parent of Scripts\
    return (Split-Path $PSScriptRoot -Parent)
  }

  function Find-MarketingFolder {
    param([string]$explicit)
    if ($explicit) {
      if (Test-Path $explicit -PathType Container) { return (Resolve-Path $explicit).Path }
      throw "SourceFolder override not found: $explicit"
    }
    $base = Get-BaseDir
    $target = Join-Path $base "Marketing"
    if (-not (Test-Path $target -PathType Container)) {
      throw "No 'Marketing' folder found next to '$PSScriptRoot'. Expected a sibling at '$target'."
    }
    Write-Host "Selected Marketing folder: $target"
    return (Resolve-Path $target).Path
  }

  function Get-SettingsPath {
    $base = Get-BaseDir
    $settingsPath = Join-Path $base "settings.json"
    if (-not (Test-Path $settingsPath -PathType Leaf)) {
      throw "Required settings file not found. Expected: '$settingsPath'."
    }
    return (Resolve-Path $settingsPath).Path
  }

  # ── JSON loading & boothId extraction (from sibling settings.json) ───────────
  function Load-JsonFile([string]$path) {
    try {
      $raw = Get-Content -LiteralPath $path -Raw -ErrorAction Stop
      if ([string]::IsNullOrWhiteSpace($raw)) { throw "Settings file is empty: $path" }
      return ($raw | ConvertFrom-Json -ErrorAction Stop)
    } catch {
      throw "Failed to parse JSON at '$path': $($_.Exception.Message)"
    }
  }

  function Resolve-BoothId([string]$settingsPath) {
    $js = Load-JsonFile $settingsPath

    # Accept several key names for robustness
    $keys = @("boothId","booth_id","booth")
    foreach ($k in $keys) {
      if ($js.PSObject.Properties.Name -contains $k) {
        $val = [string]$js.$k
        if (-not [string]::IsNullOrWhiteSpace($val)) {
          Write-Host "Booth id loaded from '$settingsPath' key '$k': $val"
          return $val
        }
      }
    }
    throw "Settings file '$settingsPath' is missing a booth id. Expected a key named one of: boothId, booth_id, booth."
  }

  # ── UUID cache helpers ───────────────────────────────────────────────────────
  function Load-Uuids([string]$storeDir, [string]$booth) {
    New-Item -ItemType Directory -Force -Path $storeDir | Out-Null
    $path = Join-Path $storeDir ("booth-{0}-uuids.json" -f $booth)
    if (Test-Path $path) {
      try { return (Get-Content $path -Raw | ConvertFrom-Json) } catch { }
    }
    return ([pscustomobject]@{})
  }

  function Save-Uuids($uuids, [string]$storeDir, [string]$booth) {
    $path = Join-Path $storeDir ("booth-{0}-uuids.json" -f $booth)
    $uuids | ConvertTo-Json | Set-Content -Path $path -Encoding UTF8
  }

  function Ensure-Uuid($uuidsRef, [string]$key) {
    if (-not ($uuidsRef.PSObject.Properties.Name -contains $key) -or [string]::IsNullOrWhiteSpace($uuidsRef.$key)) {
      $uuidsRef | Add-Member -NotePropertyName $key -NotePropertyValue ([guid]::NewGuid().ToString("N")) -Force
    }
  }

  # ── Normalizers ──────────────────────────────────────────────────────────────
  function Normalize-Email([string]$s) {
    if ([string]::IsNullOrWhiteSpace($s)) { return $null }
    $s.Trim().ToLower()
  }
  function Normalize-Phone([string]$s) {
    if ([string]::IsNullOrWhiteSpace($s)) { return $null }
    $digits = ($s -replace '\D','')
    if ($digits.Length -eq 10) { return "+1$digits" }
    elseif ($digits.Length -eq 11 -and $digits.StartsWith('1')) { return "+$digits" }
    else { return $digits }
  }

  # TEXT rows:  YYYYMMDD,HHMMSS,MMS:6233303893,1,C:\Photos\...\file.jpg
  function Load-TextRows([string]$csvPath) {
    if (-not (Test-Path $csvPath)) { throw "CSV not found: $csvPath" }
    $lines = Get-Content -LiteralPath $csvPath -ErrorAction Stop
    $out = New-Object System.Collections.Generic.List[object]
    foreach ($line in $lines) {
      if ([string]::IsNullOrWhiteSpace($line)) { continue }
      $parts = $line -split ',', 5
      if ($parts.Count -lt 3) { continue }
      $rawPhone = $parts[2].Trim()
      $rawPhone = ($rawPhone -replace '^(?i)(mms|sms):','')
      $phone = Normalize-Phone $rawPhone
      if ($phone) {
        $out.Add([pscustomobject]@{ email=$null; phone=$phone; source="text" }) | Out-Null
      }
    }
    return $out
  }

  # EMAIL rows: YYYYMMDD,HHMMSS,email@domain.com,1,C:\Photos\...\file.jpg
  function Load-EmailRows([string]$csvPath) {
    if (-not (Test-Path $csvPath)) { throw "CSV not found: $csvPath" }
    $lines = Get-Content -LiteralPath $csvPath -ErrorAction Stop
    $out = New-Object System.Collections.Generic.List[object]
    foreach ($line in $lines) {
      if ([string]::IsNullOrWhiteSpace($line)) { continue }
      $parts = $line -split ',', 5
      if ($parts.Count -lt 3) { continue }
      $email = Normalize-Email $parts[2]
      if ($email) {
        $out.Add([pscustomobject]@{ email=$email; phone=$null; source="email" }) | Out-Null
      }
    }
    return $out
  }

  # De-dupe: keep first by email and by phone
  function Deduplicate-Contacts([object[]]$rows) {
    $seenE = New-Object 'System.Collections.Generic.HashSet[string]'
    $seenP = New-Object 'System.Collections.Generic.HashSet[string]'
    foreach ($it in $rows) {
      $keep = $false
      if ($it.email -and -not $seenE.Contains($it.email)) { $seenE.Add($it.email) | Out-Null; $keep=$true }
      if ($it.phone -and -not $seenP.Contains($it.phone)) { $seenP.Add($it.phone) | Out-Null; $keep=$true }
      if ($keep) { $it }
    }
  }

  # ── Signing helpers (XML API v2, minimal) ────────────────────────────────────
  function Get-HmacSha1Base64([string]$secret, [string]$stringToSign) {
    $stringToSign = $stringToSign -replace "`r",""
    $keyBytes  = [Text.Encoding]::UTF8.GetBytes($secret)
    $dataBytes = [Text.Encoding]::UTF8.GetBytes($stringToSign)
    $hmac = New-Object System.Security.Cryptography.HMACSHA1
    try {
      $hmac.Key = $keyBytes
      $hash = $hmac.ComputeHash($dataBytes)
      [Convert]::ToBase64String($hash)
    } finally { $hmac.Dispose() }
  }

  function Upload-GcsPublic {
  param(
    [Parameter(Mandatory)][string]$Bucket,        # e.g., photobooz-marketing
    [Parameter(Mandatory)][string]$ObjectName,    # e.g., booths/ID/combined/<uuid>.csv
    [Parameter(Mandatory)][string]$LocalPath,
    [Parameter(Mandatory)][string]$AccessId,      # GOOG...
    [Parameter(Mandatory)][string]$Secret,        # HMAC secret
    [string]$ContentType = "text/csv"
  )

  if (-not (Test-Path -LiteralPath $LocalPath -PathType Leaf)) {
    throw "Upload-GcsPublic: Local file not found: $LocalPath"
  }

  # ---- Normalize object name strictly (no leading slash, no pre-encoding, no whitespace) ----
  $ObjectName = ($ObjectName -replace '\\','/').Trim()
  $ObjectName = $ObjectName -replace '^/+',''
  if ($ObjectName -match '%[0-9A-Fa-f]{2}') {
    throw "ObjectName appears pre-URL-encoded. Provide the raw path (unescaped): '$ObjectName'"
  }
  if ([string]::IsNullOrWhiteSpace($ObjectName)) { throw "Empty ObjectName after normalization." }

  $fileInfo = Get-Item -LiteralPath $LocalPath
  $fileLen  = [int64]$fileInfo.Length

  # ---- Compute Content-MD5 (Base64) and include it in both header & signature ----
  $md5 = [System.Security.Cryptography.MD5]::Create()
  try {
    $fsHash = [System.IO.File]::OpenRead($LocalPath)
    try { $hashBytes = $md5.ComputeHash($fsHash) } finally { $fsHash.Dispose() }
  } finally { $md5.Dispose() }
  $contentMd5B64 = [Convert]::ToBase64String($hashBytes)

  # ---- Build signature (Signature V2) ----
  $now     = [DateTimeOffset]::UtcNow
  $dateRfc = $now.ToString("R", [Globalization.CultureInfo]::InvariantCulture)  # e.g., Mon, 22 Sep 2025 17:00:00 GMT
  $verb    = "PUT"
  $resource= "/$Bucket/$ObjectName"
  $LF      = "`n"

  # VERB \n Content-MD5 \n Content-Type \n Date \n CanonicalizedResource
  $stringToSign = $verb + $LF + $contentMd5B64 + $LF + $ContentType + $LF + $dateRfc + $LF + $resource
  # Use UTF8, LF-only
  $keyBytes  = [Text.Encoding]::UTF8.GetBytes($Secret)
  $dataBytes = [Text.Encoding]::UTF8.GetBytes(($stringToSign -replace "`r",""))
  $hmac      = New-Object System.Security.Cryptography.HMACSHA1
  try {
    $hmac.Key = $keyBytes
    $sigBytes = $hmac.ComputeHash($dataBytes)
  } finally { $hmac.Dispose() }
  $signature  = [Convert]::ToBase64String($sigBytes)
  $authHeader = "AWS {0}:{1}" -f $AccessId, $signature

  # ---- Build request (no auto-redirects; set exact headers) ----
  [System.Net.ServicePointManager]::Expect100Continue = $false
  [System.Net.ServicePointManager]::SecurityProtocol  = [System.Net.SecurityProtocolType]::Tls12

  $escaped = (($ObjectName -split '/') | ForEach-Object { [System.Uri]::EscapeDataString($_) }) -join '/'
  $url     = "https://storage.googleapis.com/$Bucket/$escaped"

  $req = [System.Net.HttpWebRequest]::Create($url)
  $req.AllowAutoRedirect = $false
  $req.Method        = "PUT"
  $req.KeepAlive     = $false
  $req.SendChunked   = $false
  $req.ContentType   = $ContentType
  $req.ContentLength = $fileLen

  # Set headers that affect the signature EXACTLY as signed
  $req.Date = $now.UtcDateTime
  $req.Headers["Authorization"] = $authHeader
  $req.Headers["Content-MD5"]   = $contentMd5B64
  $req.Headers["Cache-Control"] = "no-store, no-cache, must-revalidate, max-age=0"

  # Stream the file
  $fs = [System.IO.File]::OpenRead($LocalPath)
  try {
    $out = $req.GetRequestStream()
    try { $fs.CopyTo($out) } finally { $out.Dispose() }
  } finally {
    $fs.Dispose()
  }

  try {
    $resp = [System.Net.HttpWebResponse]$req.GetResponse()
    try { return [int]$resp.StatusCode } finally { $resp.Close() }
  } catch [System.Net.WebException] {
    $body = ""
    if ($_.Exception.Response) {
      $sr = New-Object System.IO.StreamReader($_.Exception.Response.GetResponseStream())
      $body = $sr.ReadToEnd()
      $sr.Dispose()
      $_.Exception.Response.Close()
    }
    # Helpful debug: show our exact string-to-sign and its bytes.
    $bytesHex = ($dataBytes | ForEach-Object { $_.ToString("X2") }) -join " "
    $dbg = @"
--- GCS PUT failed ---
Status: $($_.Exception.Status)
Message: $($_.Exception.Message)

URL: $url
Resource (signed): $resource
Auth: $authHeader

Content-Type (signed & sent): $ContentType
Content-MD5 (signed & sent):  $contentMd5B64
Date (signed & sent):         $dateRfc

StringToSign:
$stringToSign

StringToSign (hex):
$bytesHex

Response body:
$body
"@
    throw $dbg
  }
}

  # ── MAIN ────────────────────────────────────────────────────────────────────
  $marketingFolder = Find-MarketingFolder -explicit $SourceFolder
  $settingsPath    = Get-SettingsPath
  $booth           = Resolve-BoothId -settingsPath $settingsPath
  $src             = $marketingFolder

  Write-Host "Booth: $booth | Marketing Folder: $src | Settings: $settingsPath"

  # Resolve inputs (optional; skip if missing)
  function Find-OptionalCsv($folder, $patterns) {
    foreach ($pat in $patterns) {
      $f = Get-ChildItem -Path $folder -File -Filter $pat -ErrorAction SilentlyContinue | Select-Object -First 1
      if ($f) { return $f.FullName }
    }
    return $null
  }

  $EmailCsv = Find-OptionalCsv -folder $src -patterns $EmailCsvPatterns
  $TextCsv  = Find-OptionalCsv -folder $src -patterns $TextCsvPatterns

  if (-not $EmailCsv -and -not $TextCsv) {
    Write-Host "No source CSVs found yet (email/text). Skipping this run gracefully."
    return
  }

  # Clean & export whichever inputs exist
  $outputs = @()
  $OutDir = Join-Path $env:TEMP "booth-$booth-output"
  New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

  if ($EmailCsv) {
    $emailRows  = Load-EmailRows $EmailCsv
    Write-Host "Parsed $($emailRows.Count) email rows from: $EmailCsv"
    $cleanEmail = Deduplicate-Contacts $emailRows
    Write-Host "After de-dup: $($cleanEmail.Count) email contacts"
    $OutEmail   = Join-Path $OutDir "cleaned_email.csv"
    $cleanEmail | Select email,phone | Export-Csv $OutEmail -NoTypeInformation -Encoding UTF8
    $outputs += [pscustomobject]@{ Key="cleaned_email"; Local=$OutEmail; Subfolder="cleaned_1" }
    Write-Host "Prepared: $OutEmail"
  } else {
    Write-Host "Email CSV not found; skipping email output."
  }

  if ($TextCsv) {
    $textRows   = Load-TextRows $TextCsv
    Write-Host "Parsed $($textRows.Count) text rows from: $TextCsv"
    $cleanText  = Deduplicate-Contacts $textRows
    Write-Host "After de-dup: $($cleanText.Count) text contacts"
    $OutText    = Join-Path $OutDir "cleaned_text.csv"
    $cleanText | Select email,phone | Export-Csv $OutText -NoTypeInformation -Encoding UTF8
    $outputs += [pscustomobject]@{ Key="cleaned_text"; Local=$OutText; Subfolder="cleaned_2" }
    Write-Host "Prepared: $OutText"
  } else {
    Write-Host "Text/Phone CSV not found; skipping text output."
  }

  if ($EmailCsv -or $TextCsv) {
    $combined = @()
    if ($EmailCsv) { $combined += $cleanEmail }
    if ($TextCsv)  { $combined += $cleanText }
    $OutCombined = Join-Path $OutDir "combined_cleaned.csv"
    $combined | Select email,phone,source | Export-Csv $OutCombined -NoTypeInformation -Encoding UTF8
    $outputs += [pscustomobject]@{ Key="combined"; Local=$OutCombined; Subfolder="combined" }
    Write-Host "Prepared: $OutCombined"
  }

  if ($outputs.Count -eq 0) {
    Write-Host "Nothing to upload this run."
    return
  }

  # UUIDs per existing output only (persist next to the script)
  $uuids = Load-Uuids -storeDir $UuidStoreDir -booth $booth
  foreach ($o in $outputs) { Ensure-Uuid -uuidsRef $uuids -key $o.Key }
  Save-Uuids -uuids $uuids -storeDir $UuidStoreDir -booth $booth

  # Upload each output; build public URLs
  $publicUrls = @()
  foreach ($o in $outputs) {
    $uuid = $uuids.$($o.Key)
    $obj  = "booths/$booth/$($o.Subfolder)/$uuid.csv"
    $code = Upload-GcsPublic -Bucket $Bucket -ObjectName $obj -LocalPath $o.Local -AccessId $GcsAccessId -Secret $GcsSecret
    if ($code -notin 200,201) { throw "Upload failed ($code) for $($o.Local)" }
    $publicUrls += "https://storage.googleapis.com/$Bucket/$obj"
  }

  "`nPublic URLs (share once, never expire):"
  $publicUrls | ForEach-Object { $_ }

  "`nRotate links by deleting UUID cache then rerun:"
  "  $(Join-Path $UuidStoreDir ("booth-{0}-uuids.json" -f $booth))"

} finally {
  Stop-Transcript | Out-Null
}
