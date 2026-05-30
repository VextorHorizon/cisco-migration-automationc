<#
.SYNOPSIS
    Automates the Cisco Secure Client + Umbrella + ISE migration described in the
    manual install PDF. Runs locally on a client machine against an already-copied
    migration folder.

.DESCRIPTION
    Three phases:
      1. LOOK    (Preflight) - read-only. Finds every required file, checks admin
                 rights. Reports GREEN (safe) or RED (stop). Changes NOTHING.
      2. INSTALL - only runs if LOOK was GREEN. Imports cert, installs the 5 MSIs
                 in dependency order, drops the 2 config files. Stops on first fail.
      3. CHECK   - verifies cert/products/service/config/Umbrella folders, prints a
                 PASS/FAIL scorecard, opens the Umbrella Policy Checker and prints
                 this PC's hostname so you can confirm cloud registration.

    Idempotent: safe to re-run. Already-installed parts are skipped.
    Every run writes a timestamped log to C:\ProgramData\CiscoMigration\logs.

.PARAMETER MigrationRoot
    Root folder to search. Default = the folder this script lives in.
    Files are found by pattern anywhere beneath this folder (any subfolder, any
    version number) - so the exact layout does not matter.

.PARAMETER PreflightOnly
    Run phase 1 only (LOOK). Read-only, installs nothing. Use this to test on any
    machine safely.

.PARAMETER DryRun
    Preview the install. Runs LOOK, then prints every action it WOULD take (cert
    import, each msiexec command, each file copy) but executes NONE of it. Read-only.
    Use this on a real client to see exactly what would happen, touching nothing.

.PARAMETER NoBrowser
    Skip auto-opening the Umbrella Policy Checker at the end.

.NOTES
    Run as Administrator. Use Run-Install.cmd / Run-Preflight.cmd for one-click.
#>
#Requires -Version 5.1
[CmdletBinding()]
param(
    [string]$MigrationRoot = $PSScriptRoot,
    [switch]$PreflightOnly,
    [switch]$DryRun,
    [switch]$NoBrowser
)

$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
$CiscoBase   = Join-Path $env:ProgramData 'Cisco\Cisco AnyConnect Secure Mobility Client'
$UmbrellaDir = Join-Path $CiscoBase 'Umbrella'
$IseDir      = Join-Path $CiscoBase 'ISE Posture'
$LogDir      = Join-Path $env:ProgramData 'CiscoMigration\logs'
$Stamp       = Get-Date -Format 'yyyyMMdd_HHmmss'
$LogFile     = Join-Path $LogDir "install_$Stamp.log"
$PolicyCheckerUrl = 'https://policy-debug.checkumbrella.com/'

# MSI install order: core-vpn FIRST (others depend on it), dart LAST.
# Found by name substring, so the version number is irrelevant.
$MsiSpec = @(
    @{ Key = 'core-vpn';      FilePattern = '*core-vpn*predeploy*.msi';      DisplayName = 'Cisco Secure Client - AnyConnect VPN';    VerifyLike = '*AnyConnect VPN*'  }
    @{ Key = 'umbrella';      FilePattern = '*umbrella*predeploy*.msi';      DisplayName = 'Cisco Secure Client - Umbrella';          VerifyLike = '*Umbrella*'        }
    @{ Key = 'iseposture';    FilePattern = '*iseposture*predeploy*.msi';    DisplayName = 'Cisco Secure Client - ISE Posture';       VerifyLike = '*ISE Posture*'     }
    @{ Key = 'isecompliance'; FilePattern = '*isecompliance*predeploy*.msi'; DisplayName = 'Cisco Secure Client - ISE Compliance';    VerifyLike = '*ISE Compliance*'  }
    @{ Key = 'dart';          FilePattern = '*dart*predeploy*.msi';          DisplayName = 'Cisco Secure Client - DART';              VerifyLike = '*Reporting Tool*'  }
)

# Config files to drop after install: <found-by-name> -> <destination folder>
$ConfigSpec = @(
    @{ FileName = 'OrgInfo.json';       Dest = $UmbrellaDir }
    @{ FileName = 'ISEPostureCFG.xml';  Dest = $IseDir }
)

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
function Write-Log {
    param(
        [string]$Message,
        [ValidateSet('INFO','OK','WARN','ERROR','STEP')]$Level = 'INFO'
    )
    $line = ('[{0}][{1}] {2}' -f (Get-Date -Format 'HH:mm:ss'), $Level, $Message)
    Add-Content -Path $LogFile -Value $line
    $color = switch ($Level) { 'OK' {'Green'} 'WARN' {'Yellow'} 'ERROR' {'Red'} 'STEP' {'Cyan'} default {'Gray'} }
    Write-Host $line -ForegroundColor $color
}

function Test-Admin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    (New-Object Security.Principal.WindowsPrincipal($id)).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

# Recursively find files under $MigrationRoot whose name matches a wildcard.
function Find-MigrationFile {
    param([string]$NameLike)
    Get-ChildItem -Path $MigrationRoot -Recurse -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -like $NameLike }
}

# True if a product with a matching ARP DisplayName is already installed.
function Test-ProductInstalled {
    param([string]$DisplayNameLike)
    $keys = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )
    foreach ($k in $keys) {
        $hit = Get-ItemProperty $k -ErrorAction SilentlyContinue |
            Where-Object { $_.DisplayName -like $DisplayNameLike }
        if ($hit) { return $true }
    }
    return $false
}

function Get-CertThumbprint {
    param([string]$Path)
    $c = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2($Path)
    $c.Thumbprint
}

function Install-Msi {
    param([string]$Path, [string]$Tag)
    $msiLog = Join-Path $LogDir ("msi_{0}_{1}.log" -f $Tag, $Stamp)
    $msiArgs = "/package `"$Path`" /quiet /norestart /lvx* `"$msiLog`""
    Write-Log "Installing $Tag : $(Split-Path $Path -Leaf)" 'STEP'
    $p = Start-Process -FilePath 'msiexec.exe' -ArgumentList $msiArgs -Wait -PassThru
    return $p.ExitCode
}

# ---------------------------------------------------------------------------
# PHASE 1 - LOOK (read-only). Returns $true if safe to install.
# Populates script-scope $Discovered with the resolved file paths.
# ---------------------------------------------------------------------------
function Invoke-Preflight {
    Write-Log '===== PHASE 1: LOOK (read-only) =====' 'STEP'
    $script:Discovered = @{}
    $ok = $true

    # Admin
    if (Test-Admin) { Write-Log 'Administrator rights: yes' 'OK' }
    else            { Write-Log 'Administrator rights: NO - must run as admin' 'ERROR'; $ok = $false }

    if (-not (Test-Path $MigrationRoot)) {
        Write-Log "Migration folder not found: $MigrationRoot" 'ERROR'
        return $false
    }
    Write-Log "Searching under: $MigrationRoot"

    # Single-match resolver: 0 = missing, 2+ = ambiguous. Both block install.
    function Resolve-One {
        param([string]$Label, [string]$Key, [System.IO.FileInfo[]]$Matches)
        if (-not $Matches -or $Matches.Count -eq 0) {
            Write-Log "$Label : MISSING" 'ERROR'
            $script:_pfOk = $false
        }
        elseif ($Matches.Count -gt 1) {
            Write-Log "$Label : $($Matches.Count) matches - ambiguous, fix the folder:" 'ERROR'
            $Matches | ForEach-Object { Write-Log "    $($_.FullName)" 'ERROR' }
            $script:_pfOk = $false
        }
        else {
            Write-Log "$Label : $($Matches[0].FullName)" 'OK'
            $script:Discovered[$Key] = $Matches[0].FullName
        }
    }

    $script:_pfOk = $true

    # Certificate (*.cer / *.crt)
    $certs = @(Find-MigrationFile '*.cer') + @(Find-MigrationFile '*.crt')
    Resolve-One 'Certificate' 'cert' $certs

    # The 5 MSIs
    foreach ($m in $MsiSpec) {
        Resolve-One ("MSI [$($m.Key)]") $m.Key (Find-MigrationFile $m.FilePattern)
    }

    # The 2 config files
    foreach ($c in $ConfigSpec) {
        Resolve-One ("Config [$($c.FileName)]") $c.FileName (Find-MigrationFile $c.FileName)
    }

    $ok = $ok -and $script:_pfOk

    if ($ok) { Write-Log 'RESULT: GREEN - all pieces present, safe to install.' 'OK' }
    else     { Write-Log 'RESULT: RED - stop. Fix the items above. Nothing was installed.' 'ERROR' }
    return $ok
}

# ---------------------------------------------------------------------------
# PHASE 2 - INSTALL. Throws on any hard failure.
# ---------------------------------------------------------------------------
function Invoke-Install {
    Write-Log '===== PHASE 2: INSTALL =====' 'STEP'

    # 2.1 Certificate -> Trusted Root (idempotent)
    $certPath = $script:Discovered['cert']
    if ($DryRun) {
        Write-Log "WOULD import certificate to Trusted Root: $certPath" 'STEP'
    }
    else {
        $thumb = Get-CertThumbprint $certPath
        if (Test-Path "Cert:\LocalMachine\Root\$thumb") {
            Write-Log "Certificate already in Trusted Root ($thumb) - skip" 'OK'
        }
        else {
            Import-Certificate -FilePath $certPath -CertStoreLocation 'Cert:\LocalMachine\Root' | Out-Null
            Write-Log "Certificate imported to Trusted Root ($thumb)" 'OK'
        }
    }

    # 2.2 MSIs in order (idempotent)
    foreach ($m in $MsiSpec) {
        if (Test-ProductInstalled $m.VerifyLike) {
            Write-Log "$($m.Key) already installed - skip" 'OK'
            continue
        }
        if ($DryRun) {
            Write-Log "WOULD run: msiexec /package `"$($script:Discovered[$m.Key])`" /quiet /norestart /lvx* <log>" 'STEP'
            continue
        }
        $code = Install-Msi -Path $script:Discovered[$m.Key] -Tag $m.Key
        if ($code -eq 0 -or $code -eq 3010) {
            Write-Log "$($m.Key) installed (exit $code)" 'OK'
        }
        else {
            throw "MSI '$($m.Key)' FAILED with exit code $code. See msi_$($m.Key)_$Stamp.log. Stopping - machine not left half-configured silently."
        }
    }

    # 2.3 Config files
    foreach ($c in $ConfigSpec) {
        if ($DryRun) {
            Write-Log "WOULD copy $($c.FileName) -> $($c.Dest)" 'STEP'
            continue
        }
        if (-not (Test-Path $c.Dest)) { New-Item -ItemType Directory -Path $c.Dest -Force | Out-Null }
        Copy-Item -Path $script:Discovered[$c.FileName] -Destination $c.Dest -Force
        Write-Log "Copied $($c.FileName) -> $($c.Dest)" 'OK'
    }

    if ($DryRun) { Write-Log 'DRY RUN preview complete - nothing was executed.' 'OK' }
    else { Write-Log 'Install phase complete.' 'OK' }
}

# ---------------------------------------------------------------------------
# PHASE 3 - CHECK. Prints scorecard. Returns $true if all hard checks pass.
# ---------------------------------------------------------------------------
function Invoke-Check {
    Write-Log '===== PHASE 3: CHECK =====' 'STEP'
    $allPass = $true

    # Cert present
    $thumb = Get-CertThumbprint $script:Discovered['cert']
    if (Test-Path "Cert:\LocalMachine\Root\$thumb") { Write-Log 'Cert in Trusted Root            : PASS' 'OK' }
    else { Write-Log 'Cert in Trusted Root            : FAIL' 'ERROR'; $allPass = $false }

    # Products installed
    foreach ($m in $MsiSpec) {
        if (Test-ProductInstalled $m.VerifyLike) { Write-Log ("Product {0,-15}: PASS" -f $m.Key) 'OK' }
        else { Write-Log ("Product {0,-15}: FAIL" -f $m.Key) 'ERROR'; $allPass = $false }
    }

    # Service present
    $svc = Get-Service -ErrorAction SilentlyContinue |
        Where-Object { $_.DisplayName -like 'Cisco Secure Client*' -or $_.DisplayName -like 'Cisco AnyConnect*' }
    if ($svc) { Write-Log "Cisco service present           : PASS ($($svc[0].DisplayName))" 'OK' }
    else { Write-Log 'Cisco service present           : FAIL' 'ERROR'; $allPass = $false }

    # Config files in place
    foreach ($c in $ConfigSpec) {
        $dst = Join-Path $c.Dest $c.FileName
        if (Test-Path $dst) { Write-Log ("Config {0,-18}: PASS" -f $c.FileName) 'OK' }
        else { Write-Log ("Config {0,-18}: FAIL" -f $c.FileName) 'ERROR'; $allPass = $false }
    }

    # Umbrella data + SWG folders (timing-dependent - retry up to 30s, warn only)
    $dataOk = $false
    for ($i = 0; $i -lt 6; $i++) {
        if ((Test-Path (Join-Path $UmbrellaDir 'data')) -and (Test-Path (Join-Path $UmbrellaDir 'SWG'))) { $dataOk = $true; break }
        Start-Sleep -Seconds 5
    }
    if ($dataOk) { Write-Log 'Umbrella data + SWG folders     : PASS' 'OK' }
    else { Write-Log 'Umbrella data + SWG folders     : NOT YET - may need a reboot, then re-check (not a hard fail)' 'WARN' }

    Write-Host ''
    if ($allPass) { Write-Log 'SCORECARD: PASS (installed & configured).' 'OK' }
    else { Write-Log 'SCORECARD: FAIL - see items above and the log.' 'ERROR' }

    # Real-world proof (Layer 3) - tee up the manual check from PDF step 8
    Write-Host ''
    Write-Log '----- FINAL PROOF (do this now) -----' 'STEP'
    Write-Log "This PC hostname: $env:COMPUTERNAME" 'OK'
    Write-Log 'In the Policy Checker page that opens, look at "Roaming Info" -> "RC Name".' 'INFO'
    Write-Log 'It MUST show the hostname above. That = Umbrella cloud registered this device.' 'INFO'
    if (-not $NoBrowser) {
        try { Start-Process $PolicyCheckerUrl; Write-Log "Opened: $PolicyCheckerUrl" 'OK' }
        catch { Write-Log "Could not open browser. Go manually to: $PolicyCheckerUrl" 'WARN' }
    }
    return $allPass
}

# ---------------------------------------------------------------------------
# MAIN
# ---------------------------------------------------------------------------
New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
Write-Log "Cisco migration installer started. Log: $LogFile" 'STEP'

try {
    $green = Invoke-Preflight

    if ($PreflightOnly) {
        Write-Log 'PreflightOnly: stopping after LOOK. Nothing installed.' 'INFO'
        exit ([int](-not $green))   # 0 if green, 1 if red
    }

    if ($DryRun) {
        # Preview needs all files found; admin not required (read-only).
        if ($script:Discovered.Keys.Count -ge 8) {
            Write-Log '===== DRY RUN: previewing install actions (executing NOTHING) =====' 'STEP'
            Invoke-Install
            exit 0
        }
        Write-Log 'DRY RUN: cannot preview - required files missing (see RED above).' 'ERROR'
        exit 1
    }

    if (-not $green) {
        Write-Log 'Aborting before install because LOOK was RED.' 'ERROR'
        exit 1
    }

    Invoke-Install
    $pass = Invoke-Check
    exit ([int](-not $pass) * 2)    # 0 = all pass, 2 = installed but verify failed
}
catch {
    Write-Log "FATAL: $($_.Exception.Message)" 'ERROR'
    Write-Log 'Stopped. Read the log above. Machine was not left in a guessed state.' 'ERROR'
    exit 1
}
