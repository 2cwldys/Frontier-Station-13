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

Write-Output "Backing up Aurora DB to $OutFile ..."

# Two DIFFERENT things have to be ready, and `docker exec ... mysqldump`
# collapses both into one opaque exit code:
#
#  1. The Docker daemon itself has to be reachable. If it isn't (Docker
#     Desktop still starting after a reboot, its named pipe not up yet),
#     EVERY `docker` command fails the same way, including a ping -- so a
#     ping check alone can't tell this apart from case 2 below.
#  2. Even once the daemon answers and the container shows Running, MariaDB
#     INSIDE it may still be doing its own startup (InnoDB crash recovery is
#     the common cause after an unclean shutdown, e.g. a power outage) and
#     won't accept connections yet -- `docker exec` itself succeeds here,
#     it's the mysql client's connection that fails.
#
# Checked as two separate gates so a failure says which one it actually was,
# instead of both looking identical.
#
# Kept SHORT deliberately: world.shelleo() (the DM proc that runs this
# script) is a blocking OS call -- it freezes the ENTIRE game world, not
# just the backup, for as long as this script takes to return. Two gates at
# 60s each, doubled by persistence_backups.dm's own retry, could previously
# freeze the whole server for up to ~4 minutes on a bad night. The DM-side
# retry already waits a few seconds between attempts WITHOUT blocking the
# world (a real sleep(), not a shell() call) -- that's where "give it a
# moment and try again" belongs, not in here.
$MaxWaitSeconds = 10
$PollSeconds = 2

$Waited = 0
$DaemonReady = $false
while ($Waited -lt $MaxWaitSeconds) {
    docker info 2>$null | Out-Null
    if ($LASTEXITCODE -eq 0) {
        $DaemonReady = $true
        break
    }
    Start-Sleep -Seconds $PollSeconds
    $Waited += $PollSeconds
}
if (-not $DaemonReady) {
    Write-Error "Backup failed: Docker daemon did not respond within ${MaxWaitSeconds}s. Docker Desktop may still be starting (e.g. after a reboot) or may not be running at all."
    exit 1
}

$Waited = 0
$DbReady = $false
while ($Waited -lt $MaxWaitSeconds) {
    docker exec aurora-db mysqladmin ping -u aurora -paurora --silent 2>$null | Out-Null
    if ($LASTEXITCODE -eq 0) {
        $DbReady = $true
        break
    }
    Start-Sleep -Seconds $PollSeconds
    $Waited += $PollSeconds
}
if (-not $DbReady) {
    Write-Error "Backup failed: Docker is up but aurora-db didn't answer a ping within ${MaxWaitSeconds}s. MariaDB may still be recovering (e.g. after an unclean shutdown), or the container may be unhealthy -- check 'docker logs aurora-db'."
    exit 1
}

# Run mysqldump inside the container, write output to file.
# --single-transaction: consistent InnoDB snapshot via MVCC instead of table
# read-locks, so a backup running mid-round doesn't block live game queries.
docker exec aurora-db mysqldump --single-transaction -u aurora -paurora aurora_persist | Out-File -FilePath $OutFile -Encoding UTF8

if ($LASTEXITCODE -ne 0) {
    Write-Error "Backup failed. mysqldump exited non-zero even though aurora-db answered a ping -- check credentials/permissions."
    exit 1
}

$Size = [math]::Round((Get-Item $OutFile).Length / 1KB, 1)
Write-Output "Backup complete: $OutFile ($Size KB)"

# Rotate: keep only the 7 most recent backups
$Backups = Get-ChildItem -Path $BackupDir -Filter "backup_*.sql" |
           Sort-Object LastWriteTime -Descending

if ($Backups.Count -gt 7) {
    $ToDelete = $Backups | Select-Object -Skip 7
    foreach ($f in $ToDelete) {
        Remove-Item $f.FullName -Force
        Write-Output "Removed old backup: $($f.Name)"
    }
}

Write-Output "Backups retained: $(($Backups | Select-Object -First 7).Count)/7"
