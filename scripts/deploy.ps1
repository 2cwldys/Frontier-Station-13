<#
.SYNOPSIS
    Pulls the deployment branch and recompiles if it has moved since the
    last successful compile. Never touches DreamDaemon itself -- restarting
    to pick up the new .dmb is a separate step (see DEPLOYMENT.md).

.PARAMETER DeployBranch
    Branch to track. Defaults to $env:DEPLOY_BRANCH, or "deployment".
#>
param(
    [string]$DeployBranch = $(if ($env:DEPLOY_BRANCH) { $env:DEPLOY_BRANCH } else { "deployment" })
)

$ErrorActionPreference = 'Stop'
$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$MarkerFile = Join-Path $PSScriptRoot '.last-deployed-commit'
$LogFile = Join-Path $PSScriptRoot 'deploy.log'

Push-Location $RepoRoot
try {
    "=== deploy.ps1 started $(Get-Date -Format o), branch=$DeployBranch ===" | Tee-Object -FilePath $LogFile -Append

    git fetch origin $DeployBranch 2>&1 | Tee-Object -FilePath $LogFile -Append
    git checkout -B $DeployBranch "origin/$DeployBranch" 2>&1 | Tee-Object -FilePath $LogFile -Append
    $Current = (git rev-parse HEAD).Trim()
    $LastDeployed = if (Test-Path $MarkerFile) { (Get-Content $MarkerFile -Raw).Trim() } else { "" }

    if ($Current -eq $LastDeployed) {
        "Already compiled at $Current, nothing to do." | Tee-Object -FilePath $LogFile -Append
        exit 0
    }

    "Compiling $Current (previously deployed: $(if ($LastDeployed) { $LastDeployed } else { 'none' }))..." | Tee-Object -FilePath $LogFile -Append
    & cmd /c "call `"tools\bootstrap\javascript.bat`" `"tools\build\build.ts`" 2>&1" | Tee-Object -FilePath $LogFile -Append
    if ($LASTEXITCODE -eq 0) {
        Set-Content -Path $MarkerFile -Value $Current
        "Compile succeeded -- $Current is ready. Restart DreamDaemon to go live (not done by this script)." | Tee-Object -FilePath $LogFile -Append
    } else {
        "Compile FAILED at $Current -- marker not updated, will retry next run." | Tee-Object -FilePath $LogFile -Append
        exit 1
    }
}
finally {
    Pop-Location
}
