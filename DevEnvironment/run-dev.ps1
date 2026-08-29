#
# run-dev.ps1 -- launch the Debug build of Safe Exam Browser with the local
#              development configuration (DevEnvironment\SEBDevelopment.seb)
#              or a custom exam .seb file in a relaxed developer session.
#
# The configuration is handed to SEB as a normal .seb file, exactly the way a
# double-clicked config would be. Because it declares sebConfigPurpose = 0
# ("starting exam"), SEB applies it to in-memory session settings and never
# writes it to %APPDATA% or %PROGRAMDATA% -- the developer's persistent SEB client
# settings, and therefore every normal/examination launch, are left untouched.
#
# Usage:
#   .\run-dev.ps1                             # launch with default dev config
#   .\run-dev.ps1 -Url http://localhost:3000   # override only the start URL
#   .\run-dev.ps1 -Fullscreen                 # test fullscreen browser view mode
#   .\run-dev.ps1 -Config path\to\exam.seb    # use a specific exam .seb configuration
#   .\run-dev.ps1 -PrintConfig                # show effective settings, don't launch
#   .\run-dev.ps1 -App "C:\...\SafeExamBrowser.exe"
#                                             # load the dev config into an SEB build other
#                                             # than DevEnvironment\build -- useful to try the
#                                             # development configuration against an installed SEB.
#
# Quit the session with Ctrl-Q, Alt-F4, or the Quit button.
#

[CmdletBinding()]
param(
    [string]$Url,
    [switch]$Fullscreen,
    [string]$Config,
    [string]$App,
    [switch]$PrintConfig,
    [switch]$Help,
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$ExtraArgs
)

if ($Help -or ($args -contains "-h") -or ($args -contains "--help") -or ($args -contains "-?")) {
    Write-Host @"
Safe Exam Browser -- local development session runner

Usage:
  .\run-dev.ps1                              Launch with default dev config
  .\run-dev.ps1 -Url <url>                   Override start URL
  .\run-dev.ps1 -Fullscreen                  Use fullscreen browser mode
  .\run-dev.ps1 -Config <path>               Use different development config (.seb file)
  .\run-dev.ps1 -App <path>                  Use specific SEB executable
  .\run-dev.ps1 -PrintConfig                 Show effective settings, don't launch

Options also accept POSIX-style flags:
  --url <url>, --fullscreen, --config <path>, --app <path>, --print-config, --help
"@
    exit 0
}

# Support POSIX-style CLI flags (--url, --fullscreen, etc.) and positional arguments
for ($i = 0; $i -lt $ExtraArgs.Count; $i++) {
    switch ($ExtraArgs[$i]) {
        "--url" {
            if ($i + 1 -lt $ExtraArgs.Count) {
                $Url = $ExtraArgs[++$i]
            }
        }
        "--fullscreen" {
            $Fullscreen = $true
        }
        "--config" {
            if ($i + 1 -lt $ExtraArgs.Count) {
                $Config = $ExtraArgs[++$i]
            }
        }
        "--app" {
            if ($i + 1 -lt $ExtraArgs.Count) {
                $App = $ExtraArgs[++$i]
            }
        }
        "--print-config" {
            $PrintConfig = $true
        }
    }
}

if (-not $Config -and -not $Url -and $ExtraArgs -and $ExtraArgs.Count -gt 0) {
    $firstArg = $ExtraArgs[0].Trim('"', ' ')
    if ($firstArg.EndsWith(".seb", [System.StringComparison]::OrdinalIgnoreCase) -or (Test-Path $firstArg)) {
        $Config = $firstArg
    } elseif ($firstArg -match "^(https?|sebs?|sebdevs?)://") {
        $Url = $firstArg
    }
}

# Convert custom URL schemes to standard HTTP/HTTPS
if ($Url) {
    if ($Url.StartsWith("sebdevs://", [System.StringComparison]::OrdinalIgnoreCase)) {
        $Url = "https://" + $Url.Substring(10)
    } elseif ($Url.StartsWith("sebdev://", [System.StringComparison]::OrdinalIgnoreCase)) {
        $Url = "http://" + $Url.Substring(9)
    } elseif ($Url.StartsWith("sebs://", [System.StringComparison]::OrdinalIgnoreCase)) {
        $Url = "https://" + $Url.Substring(7)
    } elseif ($Url.StartsWith("seb://", [System.StringComparison]::OrdinalIgnoreCase)) {
        $Url = "http://" + $Url.Substring(6)
    }
}

$commonScript = Join-Path $PSScriptRoot "seb-dev-common.ps1"
. $commonScript

# If a remote .seb URL was passed, download it as the configuration
if ($Url -and ($Url -match "\.seb(\?.*)?$" -or $Url -match "/exams/")) {
    $sessionDir = Join-Path $DEV_BUILD_DIR "session"
    if (-not (Test-Path $sessionDir)) {
        New-Item -ItemType Directory -Path $sessionDir -Force | Out-Null
    }
    $downloadedSeb = Join-Path $sessionDir "remote-exam.seb"
    Write-Info "Downloading exam configuration from: $Url"
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 -bor [Net.SecurityProtocolType]::Tls13
        Invoke-WebRequest -Uri $Url -OutFile $downloadedSeb -UseBasicParsing
        $Config = $downloadedSeb
        $Url = $null
    } catch {
        Write-WarningMsg "Could not download '$Url' directly via PowerShell ($($_.Exception.Message)). Passing URL to SEB engine."
    }
}

$configSrc = if ($Config) { (Resolve-Path $Config).Path } else { $DEV_CONFIG }

# --- Checks ------------------------------------------------------------------

if (-not (Test-Path $configSrc)) {
    Write-Failure "Configuration file not found: $configSrc"
}

$launchApp = $DEV_APP
if (-not $PrintConfig) {
    if ($App) {
        if (-not (Test-Path $App)) {
            Write-Failure "Specified application executable not found: $App"
        }
        $launchApp = (Resolve-Path $App).Path
        Write-WarningMsg @"
Using an SEB build outside DevEnvironment: $launchApp
This exercises the development configuration, not the code in this source tree.
Source changes require a build -- see .\build-dev.ps1.
"@
    } else {
        if (-not (Test-Path $DEV_APP)) {
            Write-Failure @"
No development build found at:
  $DEV_APP
Build it first:
  .\build-dev.ps1 (or build-dev.cmd)
Or try the development configuration against an installed SEB:
  .\run-dev.ps1 -App `"C:\Program Files\SafeExamBrowser\SafeExamBrowser.exe`"
"@
        }
        Assert-DevAppPath $DEV_APP
        Assert-NoProductionSebRunning
    }
}

# Check if config is plain XML or encrypted binary
$isXmlConfig = $false
try {
    $firstBytes = [System.IO.File]::ReadAllBytes($configSrc)
    if ($firstBytes.Length -ge 4) {
        $firstStr = [System.Text.Encoding]::UTF8.GetString($firstBytes[0..[Math]::Min(10, $firstBytes.Length - 1)])
        if ($firstStr.Contains("<?xm") -or $firstStr.Contains("<plist")) {
            $isXmlConfig = $true
        }
    }
} catch {}

$effectiveConfigFile = $configSrc

if ($isXmlConfig) {
    # --- Build the effective session configuration -------------------------------
    $sessionDir = Join-Path $DEV_BUILD_DIR "session"
    if (-not (Test-Path $sessionDir)) {
        New-Item -ItemType Directory -Path $sessionDir -Force | Out-Null
    }

    $sessionConfig = Join-Path $sessionDir "SEBDevelopment-session.seb"
    [xml]$sessionXml = Get-SebConfigXml $configSrc

    $hasOverrides = $false

    $configPurpose = Get-SebConfigValue -ConfigXml $sessionXml -KeyName "sebConfigPurpose"
    if ($configPurpose -and $configPurpose -ne "0") {
        Write-WarningMsg "Configuration '$configSrc' has sebConfigPurpose = '$configPurpose'. Forcing sebConfigPurpose = 0 for session-only mode."
        Set-SebConfigValue -ConfigXml $sessionXml -KeyName "sebConfigPurpose" -TypeName "integer" -Value "0"
        $hasOverrides = $true
    }

    if ($Url) {
        Set-SebConfigValue -ConfigXml $sessionXml -KeyName "startURL" -TypeName "string" -Value $Url
        Write-Info "Start URL override: $Url"
        $hasOverrides = $true
    }

    if ($Fullscreen) {
        Set-SebConfigValue -ConfigXml $sessionXml -KeyName "browserViewMode" -TypeName "integer" -Value "1"
        Write-Info "Browser view mode: fullscreen"
        $hasOverrides = $true
    }

    if ($hasOverrides) {
        # Save the modified session config without BOM
        $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
        $xmlSettings = New-Object System.Xml.XmlWriterSettings
        $xmlSettings.Indent = $true
        $xmlSettings.Encoding = $utf8NoBom
        $writer = [System.Xml.XmlWriter]::Create($sessionConfig, $xmlSettings)
        $sessionXml.Save($writer)
        $writer.Close()
        $effectiveConfigFile = $sessionConfig
    }
} else {
    Write-Info "Using binary/encrypted .seb configuration: $configSrc"
}

if ($PrintConfig) {
    if ($isXmlConfig) {
        Write-Info "Effective development settings ($effectiveConfigFile):"
        Get-Content $effectiveConfigFile
    } else {
        Write-Info "Configuration is an encrypted binary .seb file ($configSrc)."
    }
    exit 0
}

# --- Launch ------------------------------------------------------------------

$localAppData = [Environment]::GetFolderPath([Environment+SpecialFolder]::LocalApplicationData)
$logsFolder = Join-Path $localAppData "SafeExamBrowser\Logs"

Write-Host ""
Write-Host "Safe Exam Browser -- local development session" -ForegroundColor Cyan
Write-Host "  App     : " -NoNewline; Write-Host $launchApp -ForegroundColor White
Write-Host "  Config  : " -NoNewline; Write-Host $configSrc -ForegroundColor White
if ($effectiveConfigFile -ne $configSrc) {
    Write-Host "  Session : " -NoNewline; Write-Host $effectiveConfigFile -ForegroundColor White
}
Write-Host "  Logs    : " -NoNewline; Write-Host $logsFolder -ForegroundColor White
Write-Host ""
Write-Host "  PROCTORED MODE: Full lockdown enforced." -ForegroundColor Red
Write-Host "    Alt+Tab, Win key, trackpad gestures, and app switching are BLOCKED." -ForegroundColor Yellow
Write-Host "    Press Shift+Alt+S to temporarily UNLOCK switching." -ForegroundColor Green
Write-Host "    Press Shift+Alt+L to RELOCK switching." -ForegroundColor Green
Write-Host "  Settings are session-only and are not written to persistent client config."
Write-Host "  Quit with Ctrl-Q, Alt-F4, or the Quit button."
Write-Host ""

# Enable relaxed lockdown environment flag for Debug builds so any .seb file runs windowed and unlocked
$env:SEB_DEV_RELAXED_LOCKDOWN = "1"
[Environment]::SetEnvironmentVariable("SEB_DEV_RELAXED_LOCKDOWN", "1", [EnvironmentVariableTarget]::Process)

# Disable Windows trackpad 3-finger and 4-finger gestures to prevent bypassing keyboard hooks.
# These gestures generate Win+Tab, Ctrl+Win+Left/Right etc. at the driver level which can bypass
# WH_KEYBOARD_LL hooks on some Windows 11 builds.
$touchpadRegPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\PrecisionTouchPad"
$savedThreeFinger = $null
$savedFourFinger = $null
try {
    if (Test-Path $touchpadRegPath) {
        $savedThreeFinger = (Get-ItemProperty $touchpadRegPath -Name "ThreeFingerSlideEnabled" -ErrorAction SilentlyContinue).ThreeFingerSlideEnabled
        $savedFourFinger  = (Get-ItemProperty $touchpadRegPath -Name "FourFingerSlideEnabled"  -ErrorAction SilentlyContinue).FourFingerSlideEnabled
        Set-ItemProperty $touchpadRegPath -Name "ThreeFingerSlideEnabled" -Value 0 -ErrorAction SilentlyContinue
        Set-ItemProperty $touchpadRegPath -Name "FourFingerSlideEnabled"  -Value 0 -ErrorAction SilentlyContinue
        Write-Info "Trackpad 3-finger and 4-finger gestures DISABLED for proctored mode."
    }
} catch {
    Write-WarningMsg "Could not disable trackpad gestures: $_"
}

Write-Info "Launching SafeExamBrowser (proctored lockdown mode)..."
$proc = Start-Process -FilePath $launchApp -ArgumentList "`"$effectiveConfigFile`"" -PassThru

Write-Success "Launched (PID $($proc.Id)). Waiting for SEB to exit..."

# Wait for the SEB process to exit, then restore trackpad gestures
$proc.WaitForExit()

try {
    if (Test-Path $touchpadRegPath) {
        if ($null -ne $savedThreeFinger) {
            Set-ItemProperty $touchpadRegPath -Name "ThreeFingerSlideEnabled" -Value $savedThreeFinger -ErrorAction SilentlyContinue
        } else {
            Set-ItemProperty $touchpadRegPath -Name "ThreeFingerSlideEnabled" -Value 1 -ErrorAction SilentlyContinue
        }
        if ($null -ne $savedFourFinger) {
            Set-ItemProperty $touchpadRegPath -Name "FourFingerSlideEnabled"  -Value $savedFourFinger  -ErrorAction SilentlyContinue
        } else {
            Set-ItemProperty $touchpadRegPath -Name "FourFingerSlideEnabled"  -Value 1 -ErrorAction SilentlyContinue
        }
        Write-Info "Trackpad gestures RESTORED."
    }
} catch {
    Write-WarningMsg "Could not restore trackpad gestures: $_"
}

Write-Success "SEB session ended."

