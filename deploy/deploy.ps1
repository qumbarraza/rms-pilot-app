#requires -Version 5.1
<#
Deploys an extracted artifact folder to one of the local pilot environments.

Usage (from a workflow step):
    pwsh -File ./deploy/deploy.ps1 -Environment dev -ArtifactPath ./extracted

Targets: C:\pilot-deployments\{dev,test,stage,prod}
Each env runs on its own port:  dev=5001, test=5002, stage=5003, prod=5004
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('dev', 'test', 'stage', 'prod')]
    [string] $Environment,

    [Parameter(Mandatory = $true)]
    [string] $ArtifactPath
)

$ErrorActionPreference = 'Stop'

$portMap = @{ dev = 5001; test = 5002; stage = 5003; prod = 5004 }
$port    = $portMap[$Environment]
$target  = "C:\pilot-deployments\$Environment"

if (-not (Test-Path $ArtifactPath)) {
    throw "Artifact path '$ArtifactPath' does not exist."
}

Write-Host "Deploying $Environment from '$ArtifactPath' to '$target' (port $port)"

if (Test-Path $target) {
    Get-ChildItem -Path $target -Force | Remove-Item -Recurse -Force
} else {
    New-Item -ItemType Directory -Path $target -Force | Out-Null
}

Copy-Item -Path (Join-Path $ArtifactPath '*') -Destination $target -Recurse -Force

$assemblyVersion = 'unknown'
$dll = Join-Path $target 'RmsPilot.App.dll'
if (Test-Path $dll) {
    $assemblyVersion = (Get-Item $dll).VersionInfo.FileVersion
}

$marker = [ordered]@{
    environment      = $Environment
    port             = $port
    deployedAt       = (Get-Date).ToString('o')
    assemblyVersion  = $assemblyVersion
    artifactSource   = (Resolve-Path $ArtifactPath).Path
}
$marker | ConvertTo-Json | Out-File -FilePath (Join-Path $target '.deployed.json') -Encoding utf8

Write-Host "Deployed $assemblyVersion to $Environment (port $port)"
Write-Host "Run with:  `$env:PILOT_ENV='$Environment'; `$env:ASPNETCORE_URLS='http://localhost:$port'; dotnet '$target\RmsPilot.App.dll'"
