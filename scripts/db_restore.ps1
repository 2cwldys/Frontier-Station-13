<#
.SYNOPSIS
    Restore the Aurora database from a backup file.

    With no arguments, lists the backups\ rotation sorted by timestamp and lets
    you pick one. With -Path, restores from any .sql file you point it at --
    an archived dump, a copy pulled aside before a risky test, anything that
    isn't part of the 7-deep rotation.

.PARAMETER Path
    Full or relative path to a .sql dump to restore from. Skips the listing.

.EXAMPLE
    .\db_restore.ps1
    .\db_restore.ps1 -Path "D:\archive\pre_wipe_2026-08-10.sql"

.NOTES
    STOP the game server before restoring.
    The restore overwrites the current aurora_persist database entirely.
#>

param(
    [string]$Path
)

$Root      = Split-Path $PSScriptRoot -Parent
$BackupDir = Join-Path $Root "backups"

Write-Host ""
Write-Host "=== AURORA DATABASE RESTORE ===" -ForegroundColor Yellow
Write-Host ""

# $Selected is whatever we end up restoring from, however it was chosen. Both
# routes below converge on it so the confirmation, the warnings and the actual
# restore exist exactly once -- duplicating that tail into a second script is
# how the two would quietly drift apart.
$Selected = $null

if (-not [string]::IsNullOrWhiteSpace($Path)) {
    # --- Explicit file mode -------------------------------------------------
    if (-not (Test-Path -LiteralPath $Path)) {
        Write-Host "File not found: $Path" -ForegroundColor Red
        pause
        exit 1
    }

    $Selected = Get-Item -LiteralPath $Path

    if ($Selected.PSIsContainer) {
        Write-Host "That is a folder, not a .sql file: $Path" -ForegroundColor Red
        pause
        exit 1
    }

    if ($Selected.Length -eq 0) {
        # Piping an empty file into mariadb succeeds and silently changes
        # nothing, which reads as "restore complete" -- refuse instead.
        Write-Host "File is empty (0 bytes): $($Selected.FullName)" -ForegroundColor Red
        Write-Host "Refusing to restore -- this would appear to succeed while doing nothing." -ForegroundColor Yellow
        pause
        exit 1
    }

    # A valid dump can be named anything, so this is a warning and not a refusal.
    if ($Selected.Extension -ne ".sql") {
        Write-Host "Note: '$($Selected.Name)' does not end in .sql. Continuing anyway." -ForegroundColor Yellow
        Write-Host ""
    }
}
else {
    # --- Rotation listing mode (unchanged behaviour) ------------------------
    if (-not (Test-Path $BackupDir)) {
        Write-Host "No backups folder found at: $BackupDir" -ForegroundColor Red
        Write-Host "Run db_backup.bat first to create a backup." -ForegroundColor Yellow
        Write-Host "To restore a file from elsewhere, use: db_restore.ps1 -Path <file.sql>" -ForegroundColor Cyan
        pause
        exit 1
    }

    # List all backup files sorted newest first
    $Backups = Get-ChildItem -Path $BackupDir -Filter "backup_*.sql" |
               Sort-Object LastWriteTime -Descending

    if ($Backups.Count -eq 0) {
        Write-Host "No backup files found in: $BackupDir" -ForegroundColor Red
        Write-Host "Run db_backup.bat first to create a backup." -ForegroundColor Yellow
        Write-Host "To restore a file from elsewhere, use: db_restore.ps1 -Path <file.sql>" -ForegroundColor Cyan
        pause
        exit 1
    }

    Write-Host "Available backups (newest first):" -ForegroundColor Cyan
    Write-Host ""

    $i = 1
    foreach ($f in $Backups) {
        $SizeKB = [math]::Round($f.Length / 1KB, 1)
        $Age    = (Get-Date) - $f.LastWriteTime
        $AgeStr = if ($Age.TotalDays -ge 1) { "$([math]::Floor($Age.TotalDays))d ago" }
                  elseif ($Age.TotalHours -ge 1) { "$([math]::Floor($Age.TotalHours))h ago" }
                  else { "$([math]::Floor($Age.TotalMinutes))m ago" }

        Write-Host ("  [{0,2}]  {1}   {2,8} KB   ({3})" -f $i, $f.LastWriteTime.ToString("yyyy-MM-dd HH:mm:ss"), $SizeKB, $AgeStr)
        $i++
    }

    Write-Host ""
    Write-Host "  (or re-run with -Path <file.sql> to restore a file from elsewhere)" -ForegroundColor DarkGray
    Write-Host ""
    $Choice = Read-Host "Enter number to restore (or press Enter to cancel)"

    if ([string]::IsNullOrWhiteSpace($Choice)) {
        Write-Host "Cancelled." -ForegroundColor Green
        pause
        exit 0
    }

    $Index = $null
    if (-not [int]::TryParse($Choice.Trim(), [ref]$Index) -or $Index -lt 1 -or $Index -gt $Backups.Count) {
        Write-Host "Invalid selection." -ForegroundColor Red
        pause
        exit 1
    }

    $Selected = $Backups[$Index - 1]
}

# --- Shared tail: confirm and restore ---------------------------------------
Write-Host ""
Write-Host "Selected: $($Selected.Name)" -ForegroundColor Cyan
Write-Host "  Path:    $($Selected.FullName)" -ForegroundColor DarkGray
Write-Host "  Created: $($Selected.LastWriteTime)" -ForegroundColor DarkGray
Write-Host "  Size:    $([math]::Round($Selected.Length / 1KB, 1)) KB" -ForegroundColor DarkGray
Write-Host ""
Write-Host "WARNING: This will OVERWRITE the current aurora_persist database." -ForegroundColor Red
Write-Host "Make sure the game server is stopped before proceeding." -ForegroundColor Yellow
Write-Host ""

$Confirm = Read-Host "Type 'RESTORE' to confirm"
if ($Confirm -ne "RESTORE") {
    Write-Host "Cancelled." -ForegroundColor Green
    pause
    exit 0
}

Write-Host ""
Write-Host "Restoring from: $($Selected.Name) ..." -ForegroundColor Cyan

# Pipe the backup SQL file into the MariaDB container
Get-Content -LiteralPath $Selected.FullName -Raw | docker exec -i aurora-db mariadb -u aurora -paurora aurora_persist 2>&1

if ($LASTEXITCODE -ne 0) {
    Write-Host ""
    Write-Host "Restore FAILED. Is the aurora-db container running?" -ForegroundColor Red
    pause
    exit 1
}

Write-Host ""
Write-Host "Restore complete from: $($Selected.Name)" -ForegroundColor Green
Write-Host "Restart the game server to load the restored state." -ForegroundColor Cyan
pause
