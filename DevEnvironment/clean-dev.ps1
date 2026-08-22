#
# clean-dev.ps1 -- remove everything this development environment generated.
#
# Deletes only DevEnvironment/build (the Debug build, NuGet cache and throwaway session configs).
# Nothing outside DevEnvironment/ is touched, and because the development configuration is
# never persisted, there is no SEB client setting to undo.
#
# Usage:
#   .\clean-dev.ps1
#

[CmdletBinding()]
param(
    [switch]$Help
)

if ($Help -or ($args -contains "-h") -or ($args -contains "--help") -or ($args -contains "-?")) {
    Write-Host @"
clean-dev.ps1 -- clean development build outputs

Usage:
  .\clean-dev.ps1
"@
    exit 0
}

$commonScript = Join-Path $PSScriptRoot "seb-dev-common.ps1"
. $commonScript

if (-not (Test-Path $DEV_BUILD_DIR)) {
    Write-Success "Nothing to clean -- $DEV_BUILD_DIR does not exist."
    exit 0
}

# Safety check: refuse to delete anything that is not inside DevEnvironment
Assert-Deletable $DEV_BUILD_DIR

Write-Info "Removing $DEV_BUILD_DIR"
Remove-Item -Path $DEV_BUILD_DIR -Recurse -Force -ErrorAction SilentlyContinue

Write-Success "Development build folder removed."
