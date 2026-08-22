#
# build-dev.ps1 -- build the Debug configuration of Safe Exam Browser for Windows
#                 into DevEnvironment/build.
#
# This never builds Release and never installs anything into Program Files, so a
# production/examination build of SEB is unaffected by anything done here.
#
# Usage:
#   .\build-dev.ps1                    # build (incremental, x64 Debug)
#   .\build-dev.ps1 -Clean             # clean the dev build folder first
#   .\build-dev.ps1 -Quiet             # only print warnings and errors
#   .\build-dev.ps1 -Platform x86      # build 32-bit (x86) instead of x64
#   .\build-dev.ps1 -- <args...>       # pass extra arguments straight to MSBuild
#

[CmdletBinding()]
param(
    [switch]$Clean,
    [switch]$Quiet,
    [string]$Platform = "x64",
    [string]$Configuration = "Debug",
    [switch]$Help,
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$ExtraArgs
)

if ($Help -or ($args -contains "-h") -or ($args -contains "--help") -or ($args -contains "-?")) {
    Write-Host @"

Safe Exam Browser -- local development build script

Usage:
  .\build-dev.ps1                    Build Debug configuration (incremental)
  .\build-dev.ps1 -Clean             Clean the development build folder first
  .\build-dev.ps1 -Quiet             Minimal output
  .\build-dev.ps1 -Platform <x64|x86>
                                     Build specified platform (default: x64)
  .\build-dev.ps1 -- <args...>       Pass extra arguments straight to MSBuild
"@
    exit 0
}

# Handle --clean, --quiet, etc. passed in ExtraArgs/raw args
if ($ExtraArgs -contains "--clean") { $Clean = $true }
if ($ExtraArgs -contains "--quiet") { $Quiet = $true }

$commonScript = Join-Path $PSScriptRoot "seb-dev-common.ps1"
. $commonScript

# 1. Clean if requested
if ($Clean) {
    if (Test-Path $DEV_BUILD_DIR) {
        Write-Info "Removing $DEV_BUILD_DIR"
        Assert-Deletable $DEV_BUILD_DIR
        Remove-Item -Path $DEV_BUILD_DIR -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# 2. Check Solution
if (-not (Test-Path $SLN_PATH)) {
    Write-Failure "SafeExamBrowser solution not found at $SLN_PATH"
}

# 3. Locate MSBuild
$msbuild = Find-MSBuild
if (-not $msbuild) {
    Write-Failure @"
MSBuild.exe was not found.
Please install Visual Studio 2019/2022 (Community, Professional, or Enterprise) or Visual Studio Build Tools with .NET desktop build tools and the .NET Framework 4.8 targeting pack.
"@
}

Write-Info "Using MSBuild: $msbuild"

# 4. Restore NuGet packages
$nuget = Ensure-NuGet
if ($nuget -and (Test-Path $nuget)) {
    Write-Info "Restoring NuGet packages for SafeExamBrowser.sln..."
    $nugetArgs = @("restore", $SLN_PATH)
    if ($Quiet) { $nugetArgs += "-Verbosity"; $nugetArgs += "quiet" }
    & $nuget @nugetArgs
    if ($LASTEXITCODE -ne 0) {
        Write-WarningMsg "NuGet restore reported exit code $LASTEXITCODE; proceeding with build..."
    }
} else {
    Write-Info "Attempting MSBuild package restore..."
    & $msbuild $SLN_PATH /t:Restore /p:Configuration=$Configuration /p:Platform=$Platform /verbosity:minimal
}

# 5. Build
if (-not (Test-Path $DEV_APP_DIR)) {
    New-Item -ItemType Directory -Path $DEV_APP_DIR -Force | Out-Null
}

Write-Info "Building solution '$SLN_PATH' ($Platform $Configuration) into $DEV_APP_DIR"

$msBuildArguments = @(
    $SLN_PATH,
    "/p:Configuration=$Configuration",
    "/p:Platform=$Platform",
    "/p:OutDir=$DEV_APP_DIR\",
    "/property:langversion=latest"
)

if ($Quiet) {
    $msBuildArguments += "/verbosity:quiet"
} else {
    $msBuildArguments += "/verbosity:minimal"
}

if ($ExtraArgs -and $ExtraArgs.Count -gt 0) {
    $filteredArgs = $ExtraArgs | Where-Object { $_ -ne "--clean" -and $_ -ne "--quiet" -and $_ -ne "--" }
    if ($filteredArgs.Count -gt 0) {
        $msBuildArguments += $filteredArgs
    }
}

& $msbuild @msBuildArguments
$buildStatus = $LASTEXITCODE

if ($buildStatus -ne 0) {
    Write-Host ""
    Write-WarningMsg "The build failed (MSBuild exit code $buildStatus)."
    Write-Host @"
Common causes on a fresh checkout:
  * .NET Framework 4.8 Developer Pack / SDK is missing.
    Download from: https://dotnet.microsoft.com/download/dotnet-framework/net48
  * Missing Visual C++ 2015-2022 Redistributable (needed for CEF/Chromium components).
  * Missing NuGet packages: try running 'nuget restore SafeExamBrowser.sln'.
"@ -ForegroundColor DarkGray
    exit $buildStatus
}

# 6. Verify built application
if (-not (Test-Path $DEV_APP)) {
    $runtimeBin = Join-Path $REPO_ROOT "SafeExamBrowser.Runtime\bin\$Platform\$Configuration"
    $clientBin = Join-Path $REPO_ROOT "SafeExamBrowser.Client\bin\$Platform\$Configuration"

    if ((Test-Path $runtimeBin) -and (Test-Path (Join-Path $runtimeBin "SafeExamBrowser.exe"))) {
        Write-Info "Copying project build outputs to $DEV_APP_DIR..."
        Copy-Item -Path "$runtimeBin\*" -Destination $DEV_APP_DIR -Recurse -Force
        if (Test-Path $clientBin) {
            Copy-Item -Path "$clientBin\*" -Destination $DEV_APP_DIR -Recurse -Force
        }
    }
}

if (-not (Test-Path $DEV_APP)) {
    Write-Failure "Build reported success but $DEV_APP does not exist."
}

Write-Success "Built $DEV_APP"
Write-Host "    Launch it with: .\run-dev.ps1 (or run-dev.cmd)" -ForegroundColor White
