#
# register-seb-association.ps1 -- associates .seb files with the SEB development build
#                                in HKCU:\Software\Classes\.seb
#
# Usage:
#   .\register-seb-association.ps1               Register .seb file association for current user
#   .\register-seb-association.ps1 -Unregister   Remove .seb file association
#

[CmdletBinding()]
param(
    [switch]$Unregister,
    [switch]$Help
)

if ($Help) {
    Write-Host @"
Usage:
  .\register-seb-association.ps1               Associate .seb files with the development build
  .\register-seb-association.ps1 -Unregister   Remove custom .seb file association
"@
    exit 0
}

$commonScript = Join-Path $PSScriptRoot "seb-dev-common.ps1"
. $commonScript

$PROGID = "SafeExamBrowser.File.Dev"
$EXT_KEY = "HKCU:\Software\Classes\.seb"
$PROGID_KEY = "HKCU:\Software\Classes\$PROGID"

if ($Unregister) {
    Write-Info "Removing custom .seb file association..."
    if (Test-Path $EXT_KEY) {
        Remove-Item -Path $EXT_KEY -Recurse -Force -ErrorAction SilentlyContinue
    }
    if (Test-Path $PROGID_KEY) {
        Remove-Item -Path $PROGID_KEY -Recurse -Force -ErrorAction SilentlyContinue
    }
    Write-Success ".seb file association removed."
    exit 0
}

if (-not (Test-Path $DEV_APP)) {
    Write-Failure "Development build not found at: $DEV_APP. Build it first with .\build-dev.ps1"
}

# 1. Set .seb extension ProgID
if (-not (Test-Path $EXT_KEY)) {
    New-Item -Path $EXT_KEY -Force | Out-Null
}
Set-ItemProperty -Path $EXT_KEY -Name "(Default)" -Value $PROGID -Force

# 2. Set ProgID open command
$commandKey = "$PROGID_KEY\shell\open\command"
if (-not (Test-Path $commandKey)) {
    New-Item -Path $commandKey -Force | Out-Null
}
Set-ItemProperty -Path $PROGID_KEY -Name "(Default)" -Value "Safe Exam Browser Development Configuration" -Force
$openCmd = "`"$DEV_APP`" `"%1`""
Set-ItemProperty -Path $commandKey -Name "(Default)" -Value $openCmd -Force

Write-Success "Registered .seb file association for current user."
Write-Host "  Double-clicking any .seb file will now launch with: $DEV_APP" -ForegroundColor White
Write-Host "  To restore default: .\register-seb-association.ps1 -Unregister" -ForegroundColor DarkGray
