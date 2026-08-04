<#
.SYNOPSIS
    Disable the daily automatic DB backup schedule set up by
    db_schedule_backups.ps1 (or db_setup.ps1's own optional prompt).

    Removes the "AuroraDB_DailyBackup" Windows Scheduled Task. Does not
    touch any backups already made, or db_backup.ps1 itself -- you can
    still run that manually any time, this only stops the daily schedule.

.NOTES
    Safe to re-run -- if the task doesn't exist, this just reports that and
    exits cleanly instead of erroring.
#>

$ErrorActionPreference = "Stop"

$TaskName = "AuroraDB_DailyBackup"

$Existing = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
if (-not $Existing) {
    Write-Host "Scheduled task '$TaskName' isn't registered -- auto-backups are already disabled." -ForegroundColor Yellow
    exit 0
}

Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false

Write-Host "Auto-backups disabled: '$TaskName' has been removed." -ForegroundColor Green
Write-Host "Existing backups in backups\ are untouched, and db_backup.ps1 can still be run manually any time." -ForegroundColor DarkGray
Write-Host "To turn the daily schedule back on: scripts\db_schedule_backups.ps1" -ForegroundColor DarkGray
