#
# register-url-handler.ps1 -- registers sebdev:// and sebdevs:// protocol handlers
#                             for local SEB development on Windows.
#
# THIS SCRIPT CHANGES STATE ON THE MACHINE IT IS RUN ON (in HKCU:\Software\Classes).
# Specifically it:
#   1. Generates the handler script into DevEnvironment\build\SEBDevHandler.ps1
#   2. Declares the sebdev and sebdevs URL schemes in HKCU:\Software\Classes (per-user)
# It prompts for confirmation first unless -Yes is given.
#
# What it does NOT do:
#   * It never claims seb:// or sebs://. Real exam links keep opening the installed
#     Safe Exam Browser, and no system-wide default handler is changed.
#   * It never modifies HKLM or requires administrator privileges.
#   * Undo is simply running: .\register-url-handler.ps1 -Unregister
#
# Usage:
#   .\register-url-handler.ps1                     Build and register the handler
#   .\register-url-handler.ps1 -App "C:\...\SafeExamBrowser.exe"
#                                                  Bake in an external SEB executable
#   .\register-url-handler.ps1 -Yes                Skip the confirmation prompt
#   .\register-url-handler.ps1 -Unregister         Remove the protocol handler
#

[CmdletBinding()]
param(
    [string]$App = "",
    [switch]$Unregister,
    [switch]$Yes,
    [switch]$Help,
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$ExtraArgs
)

if ($Help -or ($args -contains "-h") -or ($args -contains "--help") -or ($args -contains "-?")) {
    Write-Host @"

Safe Exam Browser -- URL Scheme Protocol Handler Setup

Usage:
  .\register-url-handler.ps1               Build and register the handler (sebdev:// and sebdevs://)
  .\register-url-handler.ps1 -App <path>   Bake in a specific SEB executable to launch
  .\register-url-handler.ps1 -Yes          Skip confirmation prompt
  .\register-url-handler.ps1 -Unregister   Remove the handler from HKCU:\Software\Classes

Options also accept POSIX-style flags:
  --app <path>, --yes, --unregister, --help
"@
    exit 0
}

# Handle POSIX flags in ExtraArgs
if ($ExtraArgs -contains "--yes") { $Yes = $true }
if ($ExtraArgs -contains "--unregister") { $Unregister = $true }
for ($i = 0; $i -lt $ExtraArgs.Count; $i++) {
    if ($ExtraArgs[$i] -eq "--app" -and ($i + 1) -lt $ExtraArgs.Count) {
        $App = $ExtraArgs[$i + 1]
    }
}

$commonScript = Join-Path $PSScriptRoot "seb-dev-common.ps1"
. $commonScript

$HANDLER_SCRIPT = Join-Path $DEV_BUILD_DIR "SEBDevHandler.ps1"
$HANDLER_LOG    = Join-Path $DEV_BUILD_DIR "url-handler.log"
$RUN_DEV_SCRIPT = Join-Path $DEV_DIR "run-dev.ps1"

# --- 1. Unregister -----------------------------------------------------------
if ($Unregister) {
    Write-Info "Unregistering 'seb', 'sebs', 'sebdev', and 'sebdevs' protocol handlers and .seb association from HKCU:\Software\Classes..."
    
    $keys = @(
        "HKCU:\Software\Classes\seb",
        "HKCU:\Software\Classes\sebs",
        "HKCU:\Software\Classes\sebdev",
        "HKCU:\Software\Classes\sebdevs",
        "HKCU:\Software\Classes\.seb",
        "HKCU:\Software\Classes\SafeExamBrowser.File.Dev"
    )
    foreach ($k in $keys) {
        if (Test-Path $k) {
            Remove-Item -Path $k -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    if (Test-Path $HANDLER_SCRIPT) {
        Remove-Item -Path $HANDLER_SCRIPT -Force -ErrorAction SilentlyContinue
    }

    Write-Success "Protocol handlers and file associations removed."
    exit 0
}

# --- 2. Prompt confirmation --------------------------------------------------
if (-not $Yes) {
    Write-Host ""
    Write-Host "This will register custom URL protocol handlers and .seb file association for your user account:" -ForegroundColor Cyan
    Write-Host "  Register: seb://, sebs://, sebdev://, sebdevs:// and .seb files (in HKCU:\Software\Classes)"
    Write-Host "  Target  : $HANDLER_SCRIPT"
    Write-Host ""
    Write-Host "No administrator rights required. No system files touched."
    Write-Host "Undo at any time: .\register-url-handler.ps1 -Unregister" -ForegroundColor DarkGray
    Write-Host ""

    $reply = Read-Host "Continue? [y/N]"
    if ($reply -notmatch "^(y|yes)$") {
        Write-Info "Aborted. Nothing was registered."
        exit 0
    }
}

# --- 3. Generate Handler Script ----------------------------------------------
if (-not (Test-Path $DEV_BUILD_DIR)) {
    New-Item -ItemType Directory -Path $DEV_BUILD_DIR -Force | Out-Null
}

$extraAppArg = ""
if ($App) {
    if (-not (Test-Path $App)) {
        Write-Failure "Specified application executable not found: $App"
    }
    $extraAppArg = " -App `"$App`""
}

$handlerContent = @"
#
# SEBDevHandler.ps1 -- generated URL protocol handler for seb://, sebs://, sebdev://, sebdevs://
#
param([string]`$Url = "")

`$rawUrl = `$Url.Trim('"').Trim()
`$logFile = "$HANDLER_LOG"
`$runDevScript = "$RUN_DEV_SCRIPT"

function Convert-Scheme([string]`$u) {
    if (`$u.StartsWith("sebdevs://", [System.StringComparison]::OrdinalIgnoreCase)) {
        return "https://" + `$u.Substring(10)
    } elseif (`$u.StartsWith("sebdev://", [System.StringComparison]::OrdinalIgnoreCase)) {
        return "http://" + `$u.Substring(9)
    } elseif (`$u.StartsWith("sebs://", [System.StringComparison]::OrdinalIgnoreCase)) {
        return "https://" + `$u.Substring(7)
    } elseif (`$u.StartsWith("seb://", [System.StringComparison]::OrdinalIgnoreCase)) {
        return "http://" + `$u.Substring(6)
    }
    return `$u
}

`$targetUrl = Convert-Scheme `$rawUrl
`$timeStamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")

"`$timeStamp  received: `$rawUrl" | Out-File -FilePath `$logFile -Append -Encoding utf8
"`$timeStamp  target:   `$targetUrl" | Out-File -FilePath `$logFile -Append -Encoding utf8

try {
    `$runDevArgs = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", `$runDevScript, "-Url", `$targetUrl$extraAppArg)
    Start-Process powershell.exe -ArgumentList `$runDevArgs -WindowStyle Hidden
    "`$timeStamp  result:   run-dev.ps1 launched successfully" | Out-File -FilePath `$logFile -Append -Encoding utf8
} catch {
    `$err = `$_.Exception.Message
    "`$timeStamp  result:   run-dev.ps1 FAILED: `$err" | Out-File -FilePath `$logFile -Append -Encoding utf8
    [System.Windows.Forms.MessageBox]::Show("Failed to launch Safe Exam Browser local development session:`n`n`$err", "SEB Dev Launch Error", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
}
"@

Set-Content -Path $HANDLER_SCRIPT -Value $handlerContent -Encoding utf8
if (-not (Test-Path $HANDLER_LOG)) {
    New-Item -ItemType File -Path $HANDLER_LOG -Force | Out-Null
}

# --- 4. Register in HKCU:\Software\Classes ------------------------------------
$schemes = @("seb", "sebs", "sebdev", "sebdevs")
foreach ($scheme in $schemes) {
    $schemeKey = "HKCU:\Software\Classes\$scheme"
    $commandKey = "$schemeKey\shell\open\command"

    if (-not (Test-Path $schemeKey)) {
        New-Item -Path $schemeKey -Force | Out-Null
    }
    Set-ItemProperty -Path $schemeKey -Name "(Default)" -Value "URL:Safe Exam Browser Development Protocol ($scheme)" -Force
    Set-ItemProperty -Path $schemeKey -Name "URL Protocol" -Value "" -Force

    if (-not (Test-Path $commandKey)) {
        New-Item -Path $commandKey -Force | Out-Null
    }
    
    $cmdVal = "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$HANDLER_SCRIPT`" `"%1`""
    Set-ItemProperty -Path $commandKey -Name "(Default)" -Value $cmdVal -Force
}

# Register .seb file association pointing to the handler
$extKey = "HKCU:\Software\Classes\.seb"
$progId = "SafeExamBrowser.File.Dev"
$progIdKey = "HKCU:\Software\Classes\$progId"
$fileCmdKey = "$progIdKey\shell\open\command"

if (-not (Test-Path $extKey)) { New-Item -Path $extKey -Force | Out-Null }
Set-ItemProperty -Path $extKey -Name "(Default)" -Value $progId -Force

if (-not (Test-Path $progIdKey)) { New-Item -Path $progIdKey -Force | Out-Null }
Set-ItemProperty -Path $progIdKey -Name "(Default)" -Value "Safe Exam Browser Development Configuration" -Force

if (-not (Test-Path $fileCmdKey)) { New-Item -Path $fileCmdKey -Force | Out-Null }
$fileOpenCmd = "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$HANDLER_SCRIPT`" `"%1`""
Set-ItemProperty -Path $fileCmdKey -Name "(Default)" -Value $fileOpenCmd -Force

Write-Success "Registered 'seb://', 'sebs://', 'sebdev://', 'sebdevs://' and .seb file handlers in HKCU:\Software\Classes."
Write-Host ""
Write-Host "  Web Links: Clicking any seb:// or sebs:// link in your browser will open the dev environment!" -ForegroundColor White
Write-Host "  Files    : Double-clicking any .seb file in Windows Explorer will open the dev environment!" -ForegroundColor White
Write-Host "  Log      : $HANDLER_LOG" -ForegroundColor White
Write-Host "  Remove   : .\register-url-handler.ps1 -Unregister" -ForegroundColor DarkGray
Write-Host ""
Write-Host ""
