<#
.SYNOPSIS
    Enable (or refresh) the daily automatic DB backup schedule for an
    already-set-up database, without re-running the full db_setup.ps1 flow.

    Registers the same "AuroraDB_DailyBackup" Windows Scheduled Task
    db_setup.ps1 optionally offers during first-time setup -- runs
    db_backup.ps1 (dump + 7-backup rotation) daily at 04:00.

    Safe to re-run -- re-registering just replaces the existing task
    definition with an identical one.

.NOTES
    To turn auto-backups back off later:
        Unregister-ScheduledTask -TaskName "AuroraDB_DailyBackup" -Confirm:$false
#>

$ErrorActionPreference = "Stop"

$Root         = Split-Path $PSScriptRoot -Parent
$BackupScript = Join-Path $PSScriptRoot "db_backup.ps1"
$TaskName     = "AuroraDB_DailyBackup"

if (-not (Test-Path $BackupScript)) {
    Write-Error "db_backup.ps1 not found next to this script -- expected at $BackupScript."
    exit 1
}

$Existing = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
if ($Existing) {
    Write-Host "Scheduled task '$TaskName' already exists -- refreshing its definition." -ForegroundColor Yellow
} else {
    Write-Host "Registering scheduled task '$TaskName'..." -ForegroundColor Cyan
}

$TaskArg  = '-NonInteractive -File "' + $BackupScript + '"'
$Action   = New-ScheduledTaskAction -Execute "pwsh.exe" -Argument $TaskArg
$Trigger  = New-ScheduledTaskTrigger -Daily -At "04:00"
$Settings = New-ScheduledTaskSettingsSet -StartWhenAvailable
Register-ScheduledTask -TaskName $TaskName -Action $Action -Trigger $Trigger -Settings $Settings -RunLevel Highest -Force | Out-Null

Write-Host "Auto-backups enabled: '$TaskName' runs db_backup.ps1 daily at 04:00." -ForegroundColor Green
Write-Host "Backups land in: $(Join-Path $Root 'backups')" -ForegroundColor DarkGray
Write-Host "To disable later: Unregister-ScheduledTask -TaskName `"$TaskName`" -Confirm:`$false" -ForegroundColor DarkGray
