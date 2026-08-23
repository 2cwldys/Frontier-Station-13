<#
.SYNOPSIS
    Dumps a shard's LOCAL database to a timestamped, portable SQL file --
    same shape as scripts/db_backup.ps1 for the main server, just scoped to
    one shard's own aurora-shard-<ShardId>-db container. Keeps the 7 most
    recent backups per shard and deletes older ones automatically.

.DESCRIPTION
    The resulting .sql file is a plain mysqldump -- nothing shard-specific
    baked into it, so it can be handed to another server/shard and applied
    with a normal `docker exec -i <container> mariadb -u aurora -paurora
    aurora_persist < backup_....sql` (or restored into a fresh shard's own
    database the same way db_central_update.ps1 applies migrations).
    Central data (characters/admins/etc.) is never in this file at all --
    it only ever touches the shard's LOCAL database, same separation as
    everywhere else in this system.

.PARAMETER ShardId
    The shard to back up.

.EXAMPLE
    .\db_central_backup_shard.ps1 -ShardId frontier-shard-1
#>

param(
    [Parameter(Mandatory = $true)]
    [string]$ShardId
)

if ($ShardId -notmatch '^[A-Za-z0-9_-]+$') {
    Write-Host "ShardId must be letters, digits, hyphens, or underscores only -- got '$ShardId'." -ForegroundColor Yellow
    exit 1
}

$Root = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$BackupDir = Join-Path $Root "backups\shards\$ShardId"
if (-not (Test-Path $BackupDir)) {
    New-Item -ItemType Directory -Force -Path $BackupDir | Out-Null
}

$DbContainer = "aurora-shard-$ShardId-db"

$found = docker ps -a --filter "name=^/$DbContainer`$" --format "{{.Names}}" 2>&1
if ($found -ne $DbContainer) {
    Write-Host "No such shard database container '$DbContainer' -- does shard '$ShardId' exist? (db_central_list_shards.ps1)" -ForegroundColor Red
    exit 1
}

$Timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
$OutFile   = Join-Path $BackupDir "backup_$Timestamp.sql"

Write-Output "Backing up shard '$ShardId' ($DbContainer) to $OutFile ..."

# Same two-gate readiness check as db_backup.ps1, for the same reasons --
# see that script's own comment for why they're checked separately.
$MaxWaitSeconds = 10
$PollSeconds = 2

$Waited = 0
$DaemonReady = $false
while ($Waited -lt $MaxWaitSeconds) {
    docker info 2>$null | Out-Null
    if ($LASTEXITCODE -eq 0) { $DaemonReady = $true; break }
    Start-Sleep -Seconds $PollSeconds
    $Waited += $PollSeconds
}
if (-not $DaemonReady) {
    Write-Error "Backup failed: Docker daemon did not respond within ${MaxWaitSeconds}s."
    exit 1
}

$Waited = 0
$DbReady = $false
while ($Waited -lt $MaxWaitSeconds) {
    docker exec $DbContainer mysqladmin ping -u aurora -paurora --silent 2>$null | Out-Null
    if ($LASTEXITCODE -eq 0) { $DbReady = $true; break }
    Start-Sleep -Seconds $PollSeconds
    $Waited += $PollSeconds
}
if (-not $DbReady) {
    Write-Error "Backup failed: $DbContainer didn't answer a ping within ${MaxWaitSeconds}s -- check 'docker logs $DbContainer'."
    exit 1
}

docker exec $DbContainer mysqldump --single-transaction -u aurora -paurora aurora_persist | Out-File -FilePath $OutFile -Encoding UTF8

if ($LASTEXITCODE -ne 0) {
    Write-Error "Backup failed. mysqldump exited non-zero even though $DbContainer answered a ping."
    exit 1
}

$Size = [math]::Round((Get-Item $OutFile).Length / 1KB, 1)
Write-Output "Backup complete: $OutFile ($Size KB)"

$Backups = Get-ChildItem -Path $BackupDir -Filter "backup_*.sql" |
           Sort-Object LastWriteTime -Descending

if ($Backups.Count -gt 7) {
    $ToDelete = $Backups | Select-Object -Skip 7
    foreach ($f in $ToDelete) {
        Remove-Item $f.FullName -Force
        Write-Output "Removed old backup: $($f.Name)"
    }
}

Write-Output "Backups retained for '$ShardId': $(($Backups | Select-Object -First 7).Count)/7"
