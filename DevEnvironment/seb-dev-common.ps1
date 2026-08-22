#
# seb-dev-common.ps1 -- shared helpers for the SEB Windows local development environment.
#
# Sourced by build-dev.ps1, run-dev.ps1 and clean-dev.ps1. Not meant to be run directly.
# Everything this development environment produces stays inside DevEnvironment/;
# no file outside this folder is written or modified.
#

# --- Locations ---------------------------------------------------------------

$script:DEV_DIR = $PSScriptRoot
$script:REPO_ROOT = (Resolve-Path (Join-Path $script:DEV_DIR "..")).Path

# Everything we generate lives here, isolated from installed SEB instances
$script:DEV_BUILD_DIR = Join-Path $script:DEV_DIR "build"
$script:DEV_APP_DIR = Join-Path $script:DEV_BUILD_DIR "Debug"
$script:DEV_APP = Join-Path $script:DEV_APP_DIR "SafeExamBrowser.exe"
$script:DEV_CLIENT = Join-Path $script:DEV_APP_DIR "SafeExamBrowser.Client.exe"
$script:DEV_CONFIG = Join-Path $script:DEV_DIR "SEBDevelopment.seb"

$script:SLN_PATH = Join-Path $script:REPO_ROOT "SafeExamBrowser.sln"

# --- Output Helpers ----------------------------------------------------------

function Write-Info {
    param([string]$Message)
    Write-Host "==> " -ForegroundColor Cyan -NoNewline
    Write-Host $Message
}

function Write-Success {
    param([string]$Message)
    Write-Host "==> " -ForegroundColor Green -NoNewline
    Write-Host $Message
}

function Write-WarningMsg {
    param([string]$Message)
    Write-Host "Warning: " -ForegroundColor Yellow -NoNewline
    Write-Host $Message
}

function Write-Failure {
    param([string]$Message, [int]$ExitCode = 1)
    Write-Host "Error: " -ForegroundColor Red -NoNewline
    Write-Host $Message
    exit $ExitCode
}

# --- Tool Preconditions ------------------------------------------------------

function Find-VsWhere {
    $vswherePaths = @(
        "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe",
        "${env:ProgramFiles}\Microsoft Visual Studio\Installer\vswhere.exe"
    )
    foreach ($path in $vswherePaths) {
        if (Test-Path $path) {
            return $path
        }
    }
    $cmd = Get-Command "vswhere.exe" -ErrorAction SilentlyContinue
    if ($cmd) {
        return $cmd.Source
    }
    return $null
}

function Find-MSBuild {
    # 1. Try vswhere.exe
    $vswhere = Find-VsWhere
    if ($vswhere) {
        $msbuildPath = & $vswhere -latest -products * -requires Microsoft.Component.MSBuild -find "MSBuild\**\Bin\MSBuild.exe" | Select-Object -First 1
        if ($msbuildPath -and (Test-Path $msbuildPath)) {
            return $msbuildPath
        }
    }

    # 2. Check standard Visual Studio installation directories
    $knownLocations = @(
        "${env:ProgramFiles}\Microsoft Visual Studio\2022\Community\MSBuild\Current\Bin\MSBuild.exe",
        "${env:ProgramFiles}\Microsoft Visual Studio\2022\Professional\MSBuild\Current\Bin\MSBuild.exe",
        "${env:ProgramFiles}\Microsoft Visual Studio\2022\Enterprise\MSBuild\Current\Bin\MSBuild.exe",
        "${env:ProgramFiles}\Microsoft Visual Studio\2022\BuildTools\MSBuild\Current\Bin\MSBuild.exe",
        "${env:ProgramFiles(x86)}\Microsoft Visual Studio\2019\Community\MSBuild\Current\Bin\MSBuild.exe",
        "${env:ProgramFiles(x86)}\Microsoft Visual Studio\2019\Professional\MSBuild\Current\Bin\MSBuild.exe",
        "${env:ProgramFiles(x86)}\Microsoft Visual Studio\2019\Enterprise\MSBuild\Current\Bin\MSBuild.exe",
        "${env:ProgramFiles(x86)}\Microsoft Visual Studio\2019\BuildTools\MSBuild\Current\Bin\MSBuild.exe",
        "${env:ProgramFiles(x86)}\Microsoft Visual Studio\2017\Community\MSBuild\15.0\Bin\MSBuild.exe",
        "${env:ProgramFiles(x86)}\Microsoft Visual Studio\2017\Professional\MSBuild\15.0\Bin\MSBuild.exe",
        "${env:ProgramFiles(x86)}\Microsoft Visual Studio\2017\Enterprise\MSBuild\15.0\Bin\MSBuild.exe",
        "${env:ProgramFiles(x86)}\Microsoft Visual Studio\2017\BuildTools\MSBuild\15.0\Bin\MSBuild.exe"
    )

    foreach ($loc in $knownLocations) {
        if (Test-Path $loc) {
            return $loc
        }
    }

    # 3. Check PATH
    $cmd = Get-Command "msbuild.exe" -ErrorAction SilentlyContinue
    if ($cmd) {
        return $cmd.Source
    }

    # 4. Fallback to .NET Framework MSBuild
    $frameworkFallback = "C:\Windows\Microsoft.NET\Framework64\v4.0.30319\MSBuild.exe"
    if (Test-Path $frameworkFallback) {
        return $frameworkFallback
    }

    return $null
}

function Find-NuGet {
    # 1. Check PATH
    $cmd = Get-Command "nuget.exe" -ErrorAction SilentlyContinue
    if ($cmd) {
        return $cmd.Source
    }

    # 2. Check local tools / build folder
    $localNuget = Join-Path $script:DEV_BUILD_DIR "nuget.exe"
    if (Test-Path $localNuget) {
        return $localNuget
    }

    $repoNuget = Join-Path $script:REPO_ROOT "nuget.exe"
    if (Test-Path $repoNuget) {
        return $repoNuget
    }

    return $null
}

function Ensure-NuGet {
    $nuget = Find-NuGet
    if ($nuget) {
        return $nuget
    }

    # Automatically download nuget.exe into dev build directory
    if (-not (Test-Path $script:DEV_BUILD_DIR)) {
        New-Item -ItemType Directory -Path $script:DEV_BUILD_DIR -Force | Out-Null
    }

    $targetNuget = Join-Path $script:DEV_BUILD_DIR "nuget.exe"
    Write-Info "Downloading nuget.exe from dist.nuget.org..."

    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        $webClient = New-Object System.Net.WebClient
        $webClient.DownloadFile("https://dist.nuget.org/win-x86-commandline/latest/nuget.exe", $targetNuget)
        if (Test-Path $targetNuget) {
            Write-Success "Downloaded nuget.exe to $targetNuget"
            return $targetNuget
        }
    } catch {
        Write-WarningMsg "Failed to download nuget.exe automatically: $($_.Exception.Message)"
    }

    return $null
}

# --- Path Assertions and Safety Guards ---------------------------------------

function Assert-DevAppPath {
    param([string]$AppPath)
    $resolvedApp = [System.IO.Path]::GetFullPath($AppPath)
    $resolvedBuild = [System.IO.Path]::GetFullPath($script:DEV_BUILD_DIR)

    if (-not $resolvedApp.StartsWith($resolvedBuild, [System.StringComparison]::OrdinalIgnoreCase)) {
        Write-Failure "Refusing to operate on '$AppPath': the development scripts only touch builds inside $script:DEV_BUILD_DIR."
    }
}

function Assert-Deletable {
    param([string]$TargetDirectory)
    $resolvedTarget = [System.IO.Path]::GetFullPath($TargetDirectory)
    $resolvedDev = [System.IO.Path]::GetFullPath($script:DEV_DIR)

    if (-not $resolvedTarget.StartsWith($resolvedDev, [System.StringComparison]::OrdinalIgnoreCase) -or $resolvedTarget -eq $resolvedDev) {
        Write-Failure "Refusing to delete '$TargetDirectory': the development scripts only remove subpaths inside $script:DEV_DIR."
    }
}

function Assert-NoProductionSebRunning {
    $sebProcesses = Get-Process -Name "SafeExamBrowser*", "SebWindowsConfig*" -ErrorAction SilentlyContinue
    $offending = @()

    foreach ($proc in $sebProcesses) {
        try {
            $mainModulePath = $proc.MainModule.FileName
            if ($mainModulePath) {
                $progFiles = ${env:ProgramFiles}
                $progFilesX86 = ${env:ProgramFiles(x86)}
                if (($progFiles -and $mainModulePath.StartsWith($progFiles, [System.StringComparison]::OrdinalIgnoreCase)) -or
                    ($progFilesX86 -and $mainModulePath.StartsWith($progFilesX86, [System.StringComparison]::OrdinalIgnoreCase))) {
                    $offending += "$($proc.ProcessName) (PID $($proc.Id)) from '$mainModulePath'"
                }
            }
        } catch {
            # Ignore access denied on system process queries
        }
    }

    if ($offending.Count -gt 0) {
        $list = $offending -join "`n  "
        Write-Failure "A production Safe Exam Browser installed in Program Files is currently running:`n  $list`nQuit it before starting the development session."
    }
}

# --- XML Plist Configuration Helpers ----------------------------------------

function Get-SebConfigXml {
    param([string]$ConfigPath)
    [xml]$xml = Get-Content -Path $ConfigPath -Raw -Encoding UTF8
    return $xml
}

function Get-SebConfigValue {
    param(
        [xml]$ConfigXml,
        [string]$KeyName
    )
    $keyNode = $ConfigXml.SelectSingleNode("//dict/key[text()='$KeyName']")
    if ($null -eq $keyNode) {
        return $null
    }
    $valNode = $keyNode.NextSibling
    while ($valNode -and $valNode.NodeType -ne [System.Xml.XmlNodeType]::Element) {
        $valNode = $valNode.NextSibling
    }
    if ($null -eq $valNode) {
        return $null
    }

    switch ($valNode.Name) {
        "true"    { return "true" }
        "false"   { return "false" }
        "string"  { return $valNode.InnerText }
        "integer" { return $valNode.InnerText }
        default   { return $valNode.OuterXml }
    }
}

function Set-SebConfigValue {
    param(
        [xml]$ConfigXml,
        [string]$KeyName,
        [string]$TypeName, # string, integer, true, false
        [string]$Value = ""
    )
    $dictNode = $ConfigXml.SelectSingleNode("//dict")
    $keyNode = $ConfigXml.SelectSingleNode("//dict/key[text()='$KeyName']")

    if ($null -ne $keyNode) {
        $valNode = $keyNode.NextSibling
        while ($valNode -and $valNode.NodeType -ne [System.Xml.XmlNodeType]::Element) {
            $valNode = $valNode.NextSibling
        }
        if ($null -ne $valNode) {
            $newValNode = $ConfigXml.CreateElement($TypeName)
            if ($TypeName -eq "string" -or $TypeName -eq "integer") {
                $newValNode.InnerText = $Value
            }
            $dictNode.ReplaceChild($newValNode, $valNode) | Out-Null
        }
    } else {
        $newKeyNode = $ConfigXml.CreateElement("key")
        $newKeyNode.InnerText = $KeyName
        $newValNode = $ConfigXml.CreateElement($TypeName)
        if ($TypeName -eq "string" -or $TypeName -eq "integer") {
            $newValNode.InnerText = $Value
        }
        $dictNode.AppendChild($newKeyNode) | Out-Null
        $dictNode.AppendChild($newValNode) | Out-Null
    }
}
