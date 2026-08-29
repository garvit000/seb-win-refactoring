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

$commonScript = Join-Path $PSScriptRoot "seb-dev-common.ps1"
. $commonScript

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
Write-Host "  Development mode: kiosk restrictions are relaxed. Not an exam environment." -ForegroundColor Yellow
Write-Host "  Process and window switching (Alt-Tab, taskbar) remains available."
Write-Host "  Settings are session-only and are not written to persistent client config."
Write-Host "  Quit with Ctrl-Q, Alt-F4, or the Quit button."
Write-Host ""

# Enable relaxed lockdown environment flag for Debug builds so any .seb file runs windowed and unlocked
$env:SEB_DEV_RELAXED_LOCKDOWN = "1"
[Environment]::SetEnvironmentVariable("SEB_DEV_RELAXED_LOCKDOWN", "1", [EnvironmentVariableTarget]::Process)

Write-Info "Launching SafeExamBrowser (with relaxed development lockdown)..."
Start-Process -FilePath $launchApp -ArgumentList "`"$effectiveConfigFile`""

Write-Success "Launched. Attach Visual Studio / debugger via Debug -> Attach to Process -> SafeExamBrowser if needed."
