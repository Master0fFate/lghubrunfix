#requires -Version 5.1
[CmdletBinding(SupportsShouldProcess)]
param(
    [ValidateSet('Diagnose','Restart','InstallStartup','RemoveStartup')][string]$Action = 'Diagnose',
    [string]$InstallPath,
    [ValidateRange(5,300)][int]$TimeoutSeconds = 30
)
$ErrorActionPreference = 'Stop'
try {
    Import-Module (Join-Path $PSScriptRoot 'LGHubFix.psm1') -Force
    Invoke-LGHubFix @PSBoundParameters
} catch {
    Write-Error $_ -ErrorAction Continue
    exit 1
}
