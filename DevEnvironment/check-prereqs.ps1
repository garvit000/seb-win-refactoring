#
# check-prereqs.ps1 -- checks if the required tools and SDKs are installed on this machine.
#

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " Safe Exam Browser (Windows) -- Prerequisite Check" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host ""

$allPassed = $true

# --- 1. .NET Framework 4.8 Runtime ---
Write-Host "1. .NET Framework 4.8+ Runtime: " -NoNewline
$release = 0
try {
    $netRuntime = Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\NET Framework Setup\NDP\v4\Full" -ErrorAction SilentlyContinue
    if ($netRuntime -and $netRuntime.Release) {
        $release = [int]$netRuntime.Release
    }
} catch {}

if ($release -ge 528040) {
    Write-Host "OK (Installed, Release $release)" -ForegroundColor Green
} else {
    Write-Host "MISSING / OUTDATED" -ForegroundColor Red
    Write-Host "   Download: https://dotnet.microsoft.com/download/dotnet-framework/net48" -ForegroundColor DarkGray
    $allPassed = $false
}

# --- 2. .NET Framework 4.8 Developer Pack / Targeting Pack ---
Write-Host "2. .NET Framework 4.8 Targeting Pack: " -NoNewline
$sdkPaths = @(
    "${env:ProgramFiles(x86)}\Reference Assemblies\Microsoft\Framework\.NETFramework\v4.8",
    "${env:ProgramFiles}\Reference Assemblies\Microsoft\Framework\.NETFramework\v4.8"
)
$sdkFound = $null
foreach ($p in $sdkPaths) {
    if (Test-Path $p) {
        $sdkFound = $p
        break
    }
}

if ($sdkFound) {
    Write-Host "OK (Found at $sdkFound)" -ForegroundColor Green
} else {
    Write-Host "MISSING" -ForegroundColor Red
    Write-Host "   Download the .NET Framework 4.8 Developer Pack from:" -ForegroundColor DarkGray
    Write-Host "   https://dotnet.microsoft.com/download/dotnet-framework/net48" -ForegroundColor Yellow
    $allPassed = $false
}

# --- 3. Visual Studio 2019/2022 / Build Tools with MSBuild 15+ ---
Write-Host "3. Visual Studio / MSBuild: " -NoNewline
$vswherePaths = @(
    "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe",
    "${env:ProgramFiles}\Microsoft Visual Studio\Installer\vswhere.exe"
)
$vswhereExe = $null
foreach ($vw in $vswherePaths) {
    if (Test-Path $vw) { $vswhereExe = $vw; break }
}

$vsFound = $false
$vsName = ""

if ($vswhereExe) {
    try {
        $vsList = & $vswhereExe -products * -requires Microsoft.Component.MSBuild -format json | ConvertFrom-Json
        if ($vsList -and $vsList.Count -gt 0) {
            $vsFound = $true
            $vsName = ($vsList | ForEach-Object { "$($_.displayName) ($($_.catalog.productDisplayVersion))" }) -join ", "
        }
    } catch {}
}

if ($vsFound) {
    Write-Host "OK ($vsName)" -ForegroundColor Green
} else {
    Write-Host "MISSING" -ForegroundColor Red
    Write-Host "   Install Visual Studio 2022 (Community) or Visual Studio Build Tools with" -ForegroundColor DarkGray
    Write-Host "   the '.NET desktop development' workload from:" -ForegroundColor DarkGray
    Write-Host "   https://visualstudio.microsoft.com/downloads/" -ForegroundColor Yellow
    $allPassed = $false
}

# --- 4. Visual C++ 2015-2022 Redistributable (x64) ---
Write-Host "4. Visual C++ 2015-2022 Redist (x64): " -NoNewline
$vcRedistInstalled = $false
$vcVersion = ""
try {
    $vcKey = Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\VisualStudio\14.0\VC\Runtimes\X64" -ErrorAction SilentlyContinue
    if ($vcKey -and $vcKey.Installed -eq 1) {
        $vcRedistInstalled = $true
        $vcVersion = $vcKey.Version
    }
} catch {}

if (-not $vcRedistInstalled) {
    try {
        $vcKey32 = Get-ItemProperty "HKLM:\SOFTWARE\WOW6432Node\Microsoft\VisualStudio\14.0\VC\Runtimes\X64" -ErrorAction SilentlyContinue
        if ($vcKey32 -and $vcKey32.Installed -eq 1) {
            $vcRedistInstalled = $true
            $vcVersion = $vcKey32.Version
        }
    } catch {}
}

if ($vcRedistInstalled) {
    Write-Host "OK (v$vcVersion)" -ForegroundColor Green
} else {
    Write-Host "MISSING (Required for Chromium/CefSharp)" -ForegroundColor Red
    Write-Host "   Download: https://learn.microsoft.com/en-us/cpp/windows/latest-supported-vc-redist" -ForegroundColor Yellow
    $allPassed = $false
}

Write-Host ""
if ($allPassed) {
    Write-Host "==> All prerequisites are installed! You are ready to run: .\build-dev.ps1" -ForegroundColor Green
} else {
    Write-Host "==> Some prerequisites are missing. Please install the items marked MISSING above." -ForegroundColor Yellow
}
Write-Host ""
