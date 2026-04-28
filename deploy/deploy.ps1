#requires -Version 5.1
<#
Deploys an extracted artifact folder to one of the local pilot environments.
Stops the env's scheduled task, swaps files, restarts the task, then health-checks.

Usage (from a workflow step):
    pwsh -File ./deploy/deploy.ps1 -Environment dev -ArtifactPath ./extracted

Targets: C:\pilot-deployments\{dev,test,stage,prod}
Each env runs on its own port:  dev=5001, test=5002, stage=5003, prod=5004

Prerequisite: scheduled tasks rms-pilot-app-{dev,test,stage,prod} registered
(see C:\rms-pilot\setup-app-tasks.ps1).
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
$task    = "rms-pilot-app-$Environment"

if (-not (Test-Path $ArtifactPath)) {
    throw "Artifact path '$ArtifactPath' does not exist."
}

Write-Host "Deploying $Environment from '$ArtifactPath' to '$target' (port $port, task $task)"

# 1. Stop the task if it's running so the DLL is no longer locked
$existing = Get-ScheduledTask -TaskName $task -ErrorAction SilentlyContinue
if ($existing) {
    if ($existing.State -eq 'Running') {
        Write-Host "Stopping task $task..."
        Stop-ScheduledTask -TaskName $task
        # Give the dotnet process a moment to release file handles
        $deadline = (Get-Date).AddSeconds(15)
        while ((Get-Date) -lt $deadline) {
            $running = (Get-ScheduledTask -TaskName $task).State -eq 'Running'
            $portHeld = [bool](Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction SilentlyContinue)
            if (-not $running -and -not $portHeld) { break }
            Start-Sleep -Milliseconds 500
        }
        # Belt-and-braces: kill anything still holding the port
        $stuck = Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction SilentlyContinue
        if ($stuck) {
            Write-Host "Forcing PID $($stuck[0].OwningProcess) off port $port"
            Stop-Process -Id $stuck[0].OwningProcess -Force -ErrorAction SilentlyContinue
            Start-Sleep -Seconds 1
        }
    } else {
        Write-Host "Task $task already $($existing.State); nothing to stop"
    }
} else {
    Write-Warning "Scheduled task $task not registered. Deploy will proceed but the app won't auto-start. Run setup-app-tasks.ps1 (admin) once."
}

# 2. Swap files
if (Test-Path $target) {
    Get-ChildItem -Path $target -Force | Remove-Item -Recurse -Force
} else {
    New-Item -ItemType Directory -Path $target -Force | Out-Null
}
Copy-Item -Path (Join-Path $ArtifactPath '*') -Destination $target -Recurse -Force

# 3. Marker
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

# 4. Start the task back up (if it exists)
if ($existing) {
    Write-Host "Starting task $task..."
    Start-ScheduledTask -TaskName $task

    # 5. Health check
    $healthy = $false
    $deadline = (Get-Date).AddSeconds(30)
    while ((Get-Date) -lt $deadline) {
        try {
            $r = Invoke-WebRequest -Uri "http://localhost:$port/" -UseBasicParsing -TimeoutSec 3
            if ($r.StatusCode -eq 200) { $healthy = $true; break }
        } catch { }
        Start-Sleep -Milliseconds 750
    }
    if ($healthy) {
        Write-Host "Health: HTTP 200 on port $port"
    } else {
        Write-Host "Health check failed. Recent app log:"
        $log = Join-Path $target 'app.log'
        if (Test-Path $log) { Get-Content $log -Tail 40 | ForEach-Object { Write-Host "  $_" } }
        throw "App did not return 200 on port $port within 30s"
    }
}

Write-Host "Deployed $assemblyVersion to $Environment (port $port)"
