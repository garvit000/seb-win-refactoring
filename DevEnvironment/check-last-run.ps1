#
# check-last-run.ps1 -- did the click actually run our Windows development flow?
#
# "Safe Exam Browser opened" is not proof: an installed production SEB opening
# normally looks similar. This walks the whole chain and reports each link:
#
#   1. Protocol Handler  Are sebdev:// and sebdevs:// registered in HKCU:\Software\Classes?
#   2. Handler Log       Did a click reach it (build\url-handler.log)?
#   3. run-dev.ps1       Did it launch cleanly?
#   4. SEB Process       Which binary is running (development build vs installed)?
#   5. Configuration     Which .seb did SEB load (from SEB's own runtime log)?
#   6. Dev Mode State    Is the session actually unlocked (KioskMode.None, app switching)?
#
# Read-only: inspects registry, logs, and processes without changing anything.
#
# Usage:
#   .\check-last-run.ps1
#

$commonScript = Join-Path $PSScriptRoot "seb-dev-common.ps1"
. $commonScript

$HANDLER_SCRIPT = Join-Path $DEV_BUILD_DIR "SEBDevHandler.ps1"
$HANDLER_LOG    = Join-Path $DEV_BUILD_DIR "url-handler.log"
$localAppData   = [Environment]::GetFolderPath([Environment+SpecialFolder]::LocalApplicationData)
$SEB_LOG_DIR    = Join-Path $localAppData "SafeExamBrowser\Logs"

function Print-Pass($msg, $detail = "") {
    Write-Host "  ok  " -NoNewline -ForegroundColor Green
    Write-Host $msg -ForegroundColor White
    if ($detail) { Write-Host "        $detail" -ForegroundColor DarkGray }
}

function Print-Miss($msg, $detail = "") {
    Write-Host "  no  " -NoNewline -ForegroundColor Red
    Write-Host $msg -ForegroundColor Yellow
    if ($detail) { Write-Host "        $detail" -ForegroundColor DarkGray }
}

function Print-Skip($msg, $detail = "") {
    Write-Host "   -  " -NoNewline -ForegroundColor Yellow
    Write-Host $msg -ForegroundColor DarkGray
    if ($detail) { Write-Host "        $detail" -ForegroundColor DarkGray }
}

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " SEB Development Launch -- Chain Verification Check" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host ""

# --- 1. Protocol Handler Registration ----------------------------------------
$sebdevKey = "HKCU:\Software\Classes\sebdev\shell\open\command"
$sebdevsKey = "HKCU:\Software\Classes\sebdevs\shell\open\command"
$isRegistered = (Test-Path $sebdevKey) -and (Test-Path $sebdevsKey)

if ($isRegistered) {
    Print-Pass "protocol handler  registered in HKCU:\Software\Classes (claims: sebdev, sebdevs)"
} else {
    Print-Miss "protocol handler  not registered -- run .\register-url-handler.ps1" "until then, clicking sebdev:// links in a browser will do nothing"
}

# --- 2 & 3. Handler Log ------------------------------------------------------
if ((Test-Path $HANDLER_LOG) -and ((Get-Item $HANDLER_LOG).Length -gt 0)) {
    $lines = Get-Content $HANDLER_LOG -ErrorAction SilentlyContinue
    $lastReceived = ($lines | Where-Object { $_ -match "received:" } | Select-Object -Last 1)
    $lastTarget   = ($lines | Where-Object { $_ -match "target:" } | Select-Object -Last 1)
    $lastResult   = ($lines | Where-Object { $_ -match "result:" } | Select-Object -Last 1)

    if ($lastReceived) {
        Print-Pass "handler ran       $lastReceived" ($lastTarget)
    } else {
        Print-Miss "handler ran       log exists but records no click"
    }

    if ($lastResult) {
        if ($lastResult -match "FAILED") {
            Print-Miss "run-dev.ps1       $lastResult"
        } else {
            Print-Pass "run-dev.ps1       $lastResult"
        }
    } else {
        Print-Skip "run-dev.ps1       no result recorded yet"
    }
} else {
    Print-Miss "handler ran       no clicks recorded ($HANDLER_LOG empty or missing)" "A click never reached the helper. Ensure handler is registered and link used sebdev://"
}

# --- 4. Which SEB is running -------------------------------------------------
$sebProcesses = Get-Process -Name "SafeExamBrowser" -ErrorAction SilentlyContinue
if ($sebProcesses) {
    $procPath = $sebProcesses[0].Path
    if ($procPath -and ($procPath -like "*$DEV_BUILD_DIR*")) {
        Print-Pass "SEB running       development build ($DEV_BUILD_DIR)"
    } elseif ($procPath -and ($procPath -like "*Program Files*")) {
        Print-Skip "SEB running       the INSTALLED SEB in Program Files, not your dev build"
    } else {
        Print-Pass "SEB running       $procPath"
    }
} else {
    Print-Skip "SEB running       not running right now"
}

# --- 5 & 6. SEB Runtime Log --------------------------------------------------
if (Test-Path $SEB_LOG_DIR) {
    $latestLogFile = Get-ChildItem -Path $SEB_LOG_DIR -Filter "*_Runtime.log" -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending | Select-Object -First 1

    if ($latestLogFile) {
        $logContent = Get-Content $latestLogFile.FullName -ErrorAction SilentlyContinue
        
        # Check config load
        $configLine = ($logContent | Where-Object { $_ -match "Loading configuration from" -or $_ -match "SEBDevelopment" } | Select-Object -Last 1)
        if ($configLine) {
            if ($configLine -match "SEBDevelopment") {
                Print-Pass "config            development configuration was applied"
            } else {
                Print-Miss "config            SEB loaded a different configuration" $configLine
            }
        } else {
            Print-Skip "config            no configuration load found in latest runtime log"
        }

        # Check kiosk mode status
        $kioskNone = ($logContent | Where-Object { $_ -match "KioskMode.None" -or $_ -match "createNewDesktop: False" -or $_ -match "killExplorerShell: False" } | Select-Object -Last 1)
        $kioskActive = ($logContent | Where-Object { $_ -match "Applying kiosk mode 'CreateNewDesktop'" -or $_ -match "Applying kiosk mode 'DisableExplorerShell'" } | Select-Object -Last 1)

        if ($kioskActive) {
            Print-Miss "dev mode          session was LOCKED DOWN (kiosk active)" "The development configuration did not take effect."
        } else {
            Print-Pass "dev mode          unlocked session (kiosk restrictions relaxed, app switching allowed)" "Taskbar, Alt-Tab, and developer console active."
        }

        Write-Host ""
        Write-Host "  Latest SEB log: $($latestLogFile.FullName)" -ForegroundColor DarkGray
    } else {
        Print-Skip "config            no SEB runtime logs found in $SEB_LOG_DIR"
    }
} else {
    Print-Skip "config            log directory $SEB_LOG_DIR does not exist"
}

Write-Host ""
