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

# 4. Restore NuGet packages (both packages.config and PackageReference)
$nuget = Ensure-NuGet
if ($nuget -and (Test-Path $nuget)) {
    Write-Info "Restoring NuGet packages..."
    $nugetArgs = @("restore", $SLN_PATH)
    if ($Quiet) { $nugetArgs += "-Verbosity"; $nugetArgs += "quiet" }
    & $nuget @nugetArgs
}

# Restore PackageReference dependencies
Write-Info "Restoring MSBuild package references..."
$restoreVerbosity = if ($Quiet) { "quiet" } else { "minimal" }
& $msbuild $SLN_PATH /t:Restore /p:Configuration=$Configuration /p:Platform=$Platform /p:RestoreIgnoreFailedProjects=true /verbosity:$restoreVerbosity

# 5. Build Projects
if (-not (Test-Path $DEV_APP_DIR)) {
    New-Item -ItemType Directory -Path $DEV_APP_DIR -Force | Out-Null
}

$solutionDirArg = $REPO_ROOT
if (-not $solutionDirArg.EndsWith("\")) { $solutionDirArg += "\" }

$runtimeProj = Join-Path $REPO_ROOT "SafeExamBrowser.Runtime\SafeExamBrowser.Runtime.csproj"
$clientProj = Join-Path $REPO_ROOT "SafeExamBrowser.Client\SafeExamBrowser.Client.csproj"

Write-Info "Building SafeExamBrowser ($Platform $Configuration)..."

$verbosityFlag = if ($Quiet) { "/verbosity:quiet" } else { "/verbosity:minimal" }

# Build Client first (compiles browser & client components)
$clientArgs = @(
    $clientProj,
    "/p:Configuration=$Configuration",
    "/p:Platform=$Platform",
    "/p:SolutionDir=$solutionDirArg",
    "/property:langversion=latest",
    $verbosityFlag
)
if ($ExtraArgs -and $ExtraArgs.Count -gt 0) {
    $filtered = $ExtraArgs | Where-Object { $_ -ne "--clean" -and $_ -ne "--quiet" -and $_ -ne "--" }
    if ($filtered.Count -gt 0) { $clientArgs += $filtered }
}
& $msbuild @clientArgs
if ($LASTEXITCODE -ne 0) {
    Write-Failure "Client build failed with exit code $LASTEXITCODE"
}

# Build Runtime (compiles runtime controller & main application executable)
$runtimeArgs = @(
    $runtimeProj,
    "/p:Configuration=$Configuration",
    "/p:Platform=$Platform",
    "/p:SolutionDir=$solutionDirArg",
    "/property:langversion=latest",
    $verbosityFlag
)
if ($ExtraArgs -and $ExtraArgs.Count -gt 0) {
    $filtered = $ExtraArgs | Where-Object { $_ -ne "--clean" -and $_ -ne "--quiet" -and $_ -ne "--" }
    if ($filtered.Count -gt 0) { $runtimeArgs += $filtered }
}
& $msbuild @runtimeArgs
if ($LASTEXITCODE -ne 0) {
    Write-Failure "Runtime build failed with exit code $LASTEXITCODE"
}

# 6. Copy output binaries into DevEnvironment\build\Debug
$runtimeBin = Join-Path $REPO_ROOT "SafeExamBrowser.Runtime\bin\$Platform\$Configuration"
if (Test-Path $runtimeBin) {
    Write-Info "Staging application binaries into $DEV_APP_DIR..."
    Copy-Item -Path "$runtimeBin\*" -Destination $DEV_APP_DIR -Recurse -Force
}

# 7. Verify built application
if (-not (Test-Path $DEV_APP)) {
    Write-Failure "Build completed but $DEV_APP does not exist."
}

Write-Success "Built $DEV_APP"
Write-Host "    Launch it with: .\run-dev.ps1 (or run-dev.cmd)" -ForegroundColor White
