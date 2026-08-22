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
    Write-Info "Unregistering 'sebdev' and 'sebdevs' protocol handlers from HKCU:\Software\Classes..."
    
    $keys = @(
        "HKCU:\Software\Classes\sebdev",
        "HKCU:\Software\Classes\sebdevs"
    )
    foreach ($k in $keys) {
        if (Test-Path $k) {
            Remove-Item -Path $k -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    if (Test-Path $HANDLER_SCRIPT) {
        Remove-Item -Path $HANDLER_SCRIPT -Force -ErrorAction SilentlyContinue
    }

    Write-Success "Protocol handlers removed. sebdev:// and sebdevs:// links no longer resolve on this PC."
    exit 0
}

# --- 2. Prompt confirmation --------------------------------------------------
if (-not $Yes) {
    Write-Host ""
    Write-Host "This will register custom URL protocol handlers for your user account:" -ForegroundColor Cyan
    Write-Host "  Register: sebdev://  and  sebdevs://   (in HKCU:\Software\Classes)"
    Write-Host "  Target  : $HANDLER_SCRIPT"
    Write-Host ""
    Write-Host "Not affected: " -NoNewline -ForegroundColor Green
    Write-Host "seb:// and sebs:// keep opening the installed Safe Exam Browser."
    Write-Host "No administrator rights required. No system files touched."
    Write-Host ""
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
# SEBDevHandler.ps1 -- generated URL protocol handler for sebdev:// and sebdevs://
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
$schemes = @("sebdev", "sebdevs")
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

Write-Success "Registered 'sebdev://' and 'sebdevs://' protocol handlers in HKCU:\Software\Classes."
Write-Host ""
Write-Host "  Test it:   Start-Process `"$DEV_DIR\seb-test-page.html`" and click the button" -ForegroundColor White
Write-Host "  Verify:    .\check-last-run.ps1" -ForegroundColor White
Write-Host "  Log:       $HANDLER_LOG" -ForegroundColor White
Write-Host "  Remove:    .\register-url-handler.ps1 -Unregister" -ForegroundColor White
Write-Host ""
