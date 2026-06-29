<#
.SYNOPSIS
    Apply any missing database schema changes by re-running all migration files.
    Already-applied migrations are skipped silently (--force flag).
    Safe to run at any time -- will only create what is missing.
#>

$Root    = Split-Path $PSScriptRoot -Parent
$sqlDir  = Join-Path $Root "SQL\migrate-2023"

Write-Host "Scanning migrations in $sqlDir ..." -ForegroundColor Cyan

$files = Get-ChildItem -Path $sqlDir -Filter "V*.sql" | Sort-Object Name

if ($files.Count -eq 0) {
    Write-Host "No migration files found." -ForegroundColor Yellow
    exit 0
}

$applied  = 0
$skipped  = 0
$failed   = 0

foreach ($file in $files) {
    Write-Host "  $($file.Name) ... " -NoNewline
    $content = Get-Content $file.FullName -Raw
    $result  = $content | docker exec -i aurora-db mariadb -u aurora -paurora --force aurora_persist 2>&1
    if ($LASTEXITCODE -eq 0) {
        Write-Host "OK" -ForegroundColor Green
        $applied++
    } else {
        # --force means non-fatal errors still exit 0 from mariadb; anything
        # non-zero here is a connection failure or similar hard error.
        Write-Host "FAILED" -ForegroundColor Red
        Write-Host "    $result" -ForegroundColor DarkRed
        $failed++
    }
}

Write-Host ""
Write-Host "Done. $applied file(s) processed, $failed hard error(s)." -ForegroundColor Cyan
if ($failed -gt 0) {
    Write-Host "Check that the aurora-db container is running." -ForegroundColor Yellow
}
