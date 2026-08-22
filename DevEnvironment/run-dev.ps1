#
# run-dev.ps1 -- launch the Debug build of Safe Exam Browser with the local
#              development configuration (DevEnvironment\SEBDevelopment.seb).
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
#   .\run-dev.ps1 -Config path\to\other.seb    # use a different development config
#   .\run-dev.ps1 -PrintConfig                # show effective settings, don't launch
#
# Quit the session with Ctrl-Q, Alt-F4, or the Quit button.
#

[CmdletBinding()]
param(
    [string]$Url,
    [switch]$Fullscreen,
    [string]$Config,
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
  .\run-dev.ps1 -Config <path>               Use different development config
  .\run-dev.ps1 -PrintConfig                 Show effective settings, don't launch

Options also accept POSIX-style flags:
  --url <url>, --fullscreen, --config <path>, --print-config, --help
"@
    exit 0
}

# Support POSIX-style CLI flags (--url, --fullscreen, etc.)
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
        "--print-config" {
            $PrintConfig = $true
        }
    }
}

$commonScript = Join-Path $PSScriptRoot "seb-dev-common.ps1"
. $commonScript

$configSrc = if ($Config) { (Resolve-Path $Config).Path } else { $DEV_CONFIG }

# --- Checks ------------------------------------------------------------------

if (-not (Test-Path $configSrc)) {
    Write-Failure "Configuration file not found: $configSrc"
}

if (-not $PrintConfig) {
    if (-not (Test-Path $DEV_APP)) {
        Write-Failure @"
No development build found at:
  $DEV_APP
Build it first:
  .\build-dev.ps1 (or build-dev.cmd)
"@
    }
    Assert-DevAppPath $DEV_APP
    Assert-NoProductionSebRunning
}

# Guard rail: this script must never launch a configuration that would permanently
# reconfigure the SEB client. sebConfigPurpose must be 0 (sebConfigPurposeStartingExam / ConfigurationMode.Exam).
[xml]$configXml = Get-SebConfigXml $configSrc
$configPurpose = Get-SebConfigValue -ConfigXml $configXml -KeyName "sebConfigPurpose"

if ($configPurpose -ne "0") {
    Write-Failure @"
'$configSrc' has sebConfigPurpose = '$configPurpose'.
Only sebConfigPurpose = 0 (starting exam / session-only settings) is allowed here,
because any other value could write development settings into persistent SEB client
configuration in %APPDATA% or %PROGRAMDATA%.
"@
}

# Sanity check on kiosk mode: warn if kiosk restrictions would lock down the desktop
$createNewDesktop = Get-SebConfigValue -ConfigXml $configXml -KeyName "createNewDesktop"
$killExplorerShell = Get-SebConfigValue -ConfigXml $configXml -KeyName "killExplorerShell"
$appSwitching = Get-SebConfigValue -ConfigXml $configXml -KeyName "allowSwitchToApplications"

if ($createNewDesktop -eq "true" -or $killExplorerShell -eq "true" -or $appSwitching -eq "false") {
    Write-WarningMsg @"
'$configSrc' has kiosk restrictions enabled.
SEB may switch desktops or prevent app switching.
For standard development, set createNewDesktop=false, killExplorerShell=false, and allowSwitchToApplications=true.
"@
}

# --- Build the effective session configuration -------------------------------

$sessionDir = Join-Path $DEV_BUILD_DIR "session"
if (-not (Test-Path $sessionDir)) {
    New-Item -ItemType Directory -Path $sessionDir -Force | Out-Null
}

$sessionConfig = Join-Path $sessionDir "SEBDevelopment-session.seb"
[xml]$sessionXml = Get-SebConfigXml $configSrc

$hasOverrides = $false

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

$effectiveConfigFile = if ($hasOverrides) {
    # Save the modified session config
    $xmlSettings = New-Object System.Xml.XmlWriterSettings
    $xmlSettings.Indent = $true
    $xmlSettings.Encoding = [System.Text.Encoding]::UTF8
    $writer = [System.Xml.XmlWriter]::Create($sessionConfig, $xmlSettings)
    $sessionXml.Save($writer)
    $writer.Close()
    $sessionConfig
} else {
    $configSrc
}

if ($PrintConfig) {
    Write-Info "Effective development settings ($effectiveConfigFile):"
    Get-Content $effectiveConfigFile
    exit 0
}

# --- Launch ------------------------------------------------------------------

$localAppData = [Environment]::GetFolderPath([Environment+SpecialFolder]::LocalApplicationData)
$logsFolder = Join-Path $localAppData "SafeExamBrowser\Logs"

Write-Host ""
Write-Host "Safe Exam Browser -- local development session" -ForegroundColor Cyan
Write-Host "  App     : " -NoNewline; Write-Host $DEV_APP -ForegroundColor White
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

Write-Info "Launching SafeExamBrowser..."
Start-Process -FilePath $DEV_APP -ArgumentList "`"$effectiveConfigFile`""

Write-Success "Launched. Attach Visual Studio / debugger via Debug -> Attach to Process -> SafeExamBrowser if needed."
