<#
.SYNOPSIS
    Installs and registers the IIS Monitoring Windows Service with specific user, auto-start, and 300s recovery.
#>

[CmdletBinding()]
param (
    [string]$InstallPath = "C:\Services\CustomerSpikeIisMonitor",
    [string]$ServiceName = "CustomerSpikeIisMonitor",
    [string]$DisplayName = "Customer Spike IIS Website Monitor",
    [string]$Description = "Monitors IIS website status every 60 seconds. Logs HTTP status to file and stops on status <> 200 OK. Auto-recovers after 300s.",
    [string]$TargetUrl = "http://localhost/",
    [int]$CheckIntervalSeconds = 60,
    [string]$UserName = "SpikeIISUser",
    [string]$Password = "SenhaForte@2026!",
    [int]$RecoveryDelaySeconds = 300
)

# Run deploy-service.ps1 with forwarded arguments
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
& (Join-Path $scriptDir "deploy-service.ps1") `
    -InstallPath $InstallPath `
    -ServiceName $ServiceName `
    -DisplayName $DisplayName `
    -Description $Description `
    -TargetUrl $TargetUrl `
    -CheckIntervalSeconds $CheckIntervalSeconds `
    -UserName $UserName `
    -Password $Password `
    -RecoveryDelaySeconds $RecoveryDelaySeconds `
    -StartupType "Automatic"
