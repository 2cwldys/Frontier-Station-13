<#
.SYNOPSIS
    Apply any missing schema changes to the CENTRAL (cross-server) database by
    re-running all migration files in SQL\migrate-central\.
    Already-applied migrations are skipped silently (--force flag).
    Safe to run at any time -- will only create what is missing.

.NOTES
    This is the central-DB counterpart to db_update.ps1, which applies
    SQL\migrate-2023\ against this server's own LOCAL database instead --
    the two are separate schemas on separate connections and neither script
    touches the other's migration folder.

    Unlike db_update.ps1 (which shells into the local aurora-db Docker
    container directly, since this server owns and runs it), the central
    database is often hosted elsewhere -- so this connects over the network
    with a plain mysql/mariadb CLI client instead. (If you're hosting it
    locally via db_central_setup.ps1, this still works the same way, just
    connecting to localhost:13306.)

    Uses config\central_dbconfig_admin.txt -- the ADMIN-tier login, NOT
    config\central_dbconfig.txt (the per-server RUNTIME login SScentraldb
    itself reads, centraldb.dm). Schema changes need real DDL rights
    (CREATE/ALTER/...), which the runtime login deliberately does NOT have
    -- see central_dbconfig_admin.txt's own header for why the two must stay
    separate. Requires a mysql or mariadb client binary on PATH.
#>

$Root      = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$sqlDir    = Join-Path $Root "SQL\migrate-central"
$configPath = Join-Path $Root "config\central_dbconfig_admin.txt"

if (-not (Test-Path $configPath)) {
    Write-Host "config\central_dbconfig_admin.txt not found -- run db_central_setup.ps1, or copy it from config\example\central_dbconfig_admin.txt and fill in the central database's admin credentials yourself." -ForegroundColor Yellow
    exit 1
}

# Same tiny "KEY value" format GetDBConfig() (centraldb.dm) reads at runtime --
# deliberately re-parsed here rather than shared code, since this is a
# standalone PowerShell script with no access to the DM config loader.
$dbConfig = @{
    address  = "localhost"
    port     = "3306"
    database = "aurora_central"
    login    = ""
    password = ""
}
foreach ($line in Get-Content $configPath) {
    $t = $line.Trim()
    if ($t.Length -eq 0 -or $t.StartsWith("#")) { continue }
    $parts = $t -split '\s+', 2
    if ($parts.Count -lt 2) { continue }
    $key = $parts[0].ToLower()
    if ($dbConfig.ContainsKey($key)) {
        $dbConfig[$key] = $parts[1]
    }
}

if (-not $dbConfig.login -or -not $dbConfig.password) {
    Write-Host "config\central_dbconfig_admin.txt is missing LOGIN/PASSWORD -- fill those in first." -ForegroundColor Yellow
    exit 1
}

$client = Get-Command mariadb -ErrorAction SilentlyContinue
if (-not $client) { $client = Get-Command mysql -ErrorAction SilentlyContinue }
if (-not $client) {
    Write-Host "No 'mariadb' or 'mysql' client found on PATH -- install one to apply central migrations from this machine." -ForegroundColor Yellow
    exit 1
}

Write-Host "Scanning central migrations in $sqlDir ..." -ForegroundColor Cyan
Write-Host "Target: $($dbConfig.address):$($dbConfig.port)/$($dbConfig.database) via $($client.Name)" -ForegroundColor DarkGray

if (-not (Test-Path $sqlDir)) {
    Write-Host "No SQL\migrate-central\ directory found." -ForegroundColor Yellow
    exit 0
}

$files = Get-ChildItem -Path $sqlDir -Filter "V*.sql" | Sort-Object Name

if ($files.Count -eq 0) {
    Write-Host "No migration files found." -ForegroundColor Yellow
    exit 0
}

$applied = 0
$failed  = 0

foreach ($file in $files) {
    Write-Host "  $($file.Name) ... " -NoNewline
    $content = Get-Content $file.FullName -Raw
    $result = $content | & $client.Source `
        -h $dbConfig.address -P $dbConfig.port `
        -u $dbConfig.login "-p$($dbConfig.password)" `
        --force $dbConfig.database 2>&1
    if ($LASTEXITCODE -eq 0) {
        Write-Host "OK" -ForegroundColor Green
        $applied++
    } else {
        # --force means non-fatal SQL errors still exit 0; anything non-zero
        # here is a connection failure or similarly hard error.
        Write-Host "FAILED" -ForegroundColor Red
        Write-Host "    $result" -ForegroundColor DarkRed
        $failed++
    }
}

Write-Host ""
Write-Host "Done. $applied file(s) processed, $failed hard error(s)." -ForegroundColor Cyan
if ($failed -gt 0) {
    Write-Host "Check that the central database is reachable and the credentials in config\central_dbconfig_admin.txt are correct." -ForegroundColor Yellow
}
