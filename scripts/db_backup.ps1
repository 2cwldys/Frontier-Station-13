<#
.SYNOPSIS
    Dump the Aurora database to a timestamped SQL file in the backups/ directory.
    Keeps the 7 most recent backups and deletes older ones automatically.

.NOTES
    Run before stopping the server or before applying major changes.
    The scheduled task created by db_setup.ps1 calls this script daily at 04:00.
#>

$Root      = Split-Path $PSScriptRoot -Parent
$BackupDir = Join-Path $Root "backups"

if (-not (Test-Path $BackupDir)) {
    New-Item -ItemType Directory -Path $BackupDir | Out-Null
}

$Timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
$OutFile   = Join-Path $BackupDir "backup_$Timestamp.sql"

Write-Host "Backing up Aurora DB to $OutFile ..." -ForegroundColor Cyan

# Run mysqldump inside the container, write output to file.
# --single-transaction: consistent InnoDB snapshot via MVCC instead of table
# read-locks, so a backup running mid-round doesn't block live game queries.
docker exec aurora-db mysqldump --single-transaction -u aurora -paurora aurora_persist | Out-File -FilePath $OutFile -Encoding UTF8

if ($LASTEXITCODE -ne 0) {
    Write-Error "Backup failed. Is the aurora-db container running?"
    exit 1
}

$Size = [math]::Round((Get-Item $OutFile).Length / 1KB, 1)
Write-Host "Backup complete: $OutFile ($Size KB)" -ForegroundColor Green

# Rotate: keep only the 7 most recent backups
$Backups = Get-ChildItem -Path $BackupDir -Filter "backup_*.sql" |
           Sort-Object LastWriteTime -Descending

if ($Backups.Count -gt 7) {
    $ToDelete = $Backups | Select-Object -Skip 7
    foreach ($f in $ToDelete) {
        Remove-Item $f.FullName -Force
        Write-Host "Removed old backup: $($f.Name)" -ForegroundColor DarkGray
    }
}

Write-Host "Backups retained: $(($Backups | Select-Object -First 7).Count)/7" -ForegroundColor DarkGray
