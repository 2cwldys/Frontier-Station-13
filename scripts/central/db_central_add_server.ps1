<#
.SYNOPSIS
    Authorizes a new server against the central (cross-server) database:
    creates it a dedicated login, scoped to DATA access only, and prints the
    config\central_dbconfig.txt block to hand to whoever runs that server.

.DESCRIPTION
    Run this ONCE per server you want to authorize. Each server gets its own
    login rather than sharing one -- that is what makes
    db_central_remove_server.ps1 able to cut off a single server later
    without touching anyone else's access.

    The login this creates is DELIBERATELY LIMITED to
    SELECT/INSERT/UPDATE/DELETE -- no CREATE, ALTER, DROP, or GRANT OPTION.
    A game server's own runtime connection (SScentraldb, centraldb.dm) never
    needs to touch the schema, only the rows in it; keeping that true at the
    database level means a compromised or buggy game server can corrupt
    DATA at worst, never the structure everyone else's data lives in.
    Schema changes stay the admin login's job alone (db_central_update.ps1).

    Connects using config\central_dbconfig_admin.txt -- the ADMIN tier, not
    the per-server runtime file this script is busy creating logins for.
    See that file's own header for why the two must never be the same
    credential.

.PARAMETER ServerId
    Identity for the new server -- should match what that server will set as
    CENTRAL_SERVER_ID in its own config.txt (config/configuration.dm reads
    that value when it holds a presence lock). Restricted to
    letters/digits/hyphen/underscore, since it is interpolated directly into
    CREATE USER/GRANT statements and this keeps that always safe without
    needing SQL-string escaping.

.PARAMETER Password
    Password for the new login. Omit to have one generated (recommended --
    printed once, not stored anywhere by this script).

.PARAMETER SourceIP
    Restricts the login to connections from this IP (or a MariaDB host
    pattern like '203.0.113.%'). Defaults to '%' -- any IP -- same as
    before this parameter existed. Scoping it to the server's real IP means
    a leaked password alone isn't enough to connect; MariaDB refuses the
    login unless the connection also originates from this address. Needs
    that server to have a stable IP -- skip this for servers on dynamic/
    residential connections, or re-run this script if their IP changes.

.PARAMETER WhatIf
    Print the SQL and the resulting config block without actually creating
    anything.

.EXAMPLE
    .\db_central_add_server.ps1 -ServerId frontier-alpha
    .\db_central_add_server.ps1 -ServerId frontier-beta -WhatIf
    .\db_central_add_server.ps1 -ServerId frontier-gamma -SourceIP 203.0.113.7
#>

param(
    [Parameter(Mandatory = $true)]
    [string]$ServerId,

    [string]$Password,

    [string]$SourceIP = '%',

    [switch]$WhatIf
)

$Root = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$configPath = Join-Path $Root "config\central_dbconfig_admin.txt"

if ($ServerId -notmatch '^[A-Za-z0-9_-]+$') {
    Write-Host "ServerId must be letters, digits, hyphens, or underscores only -- got '$ServerId'." -ForegroundColor Yellow
    exit 1
}

if ($SourceIP -notmatch '^[A-Za-z0-9.:%-]+$') {
    Write-Host "SourceIP must be an IP, host pattern (e.g. 203.0.113.%), or '%' -- got '$SourceIP'." -ForegroundColor Yellow
    exit 1
}

if (-not (Test-Path $configPath)) {
    Write-Host "config\central_dbconfig_admin.txt not found -- run db_central_setup.ps1, or copy it from config\example\central_dbconfig_admin.txt and fill in the central database's admin credentials yourself." -ForegroundColor Yellow
    exit 1
}

# Same tiny "KEY value" format GetDBConfig() (centraldb.dm) reads at runtime,
# re-parsed here since this is a standalone script with no access to the DM
# config loader -- same approach db_central_update.ps1 already uses.
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
    Write-Host "No 'mariadb' or 'mysql' client found on PATH." -ForegroundColor Yellow
    exit 1
}

if (-not $Password) {
    # Alphanumeric only, deliberately -- this password is about to be passed
    # on a command line to the mysql/mariadb client via -p, and keeping it to
    # a safe charset avoids any quoting hazard there entirely rather than
    # trying to escape one.
    $chars = 'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnpqrstuvwxyz23456789'
    $bytes = New-Object byte[] 32
    [System.Security.Cryptography.RandomNumberGenerator]::Fill($bytes)
    $Password = -join ($bytes | ForEach-Object { $chars[$_ % $chars.Length] })
}

$sql = @"
CREATE USER IF NOT EXISTS '$ServerId'@'$SourceIP' IDENTIFIED BY '$Password';
GRANT SELECT, INSERT, UPDATE, DELETE ON ``$($dbConfig.database)``.* TO '$ServerId'@'$SourceIP';
FLUSH PRIVILEGES;
"@

Write-Host "Target: $($dbConfig.address):$($dbConfig.port)/$($dbConfig.database) via $($client.Name)" -ForegroundColor DarkGray
if ($SourceIP -eq '%') {
    Write-Host "SourceIP not set -- this login will be accepted from any IP. Pass -SourceIP <their IP> to restrict it." -ForegroundColor DarkYellow
}
Write-Host ""
Write-Host "SQL to run:" -ForegroundColor Cyan
Write-Host $sql -ForegroundColor DarkGray
Write-Host ""

if ($WhatIf) {
    Write-Host "-WhatIf: nothing created." -ForegroundColor Cyan
} else {
    $result = $sql | & $client.Source `
        -h $dbConfig.address -P $dbConfig.port `
        -u $dbConfig.login "-p$($dbConfig.password)" 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Host "FAILED:" -ForegroundColor Red
        Write-Host "  $result" -ForegroundColor DarkRed
        exit 1
    }
    Write-Host "Created '$ServerId'@'$SourceIP' with data-only access to $($dbConfig.database)." -ForegroundColor Green
}

Write-Host ""
Write-Host "Hand this to whoever runs that server -- goes in THEIR config\central_dbconfig.txt" -ForegroundColor Cyan
Write-Host "(the runtime file, not this admin one) -- and set CENTRAL_SERVER_ID $ServerId /" -ForegroundColor Cyan
Write-Host "CENTRAL_SQL_ENABLED in their config.txt:" -ForegroundColor Cyan
Write-Host ""
Write-Host "ADDRESS $($dbConfig.address)"
Write-Host "PORT $($dbConfig.port)"
Write-Host "DATABASE $($dbConfig.database)"
Write-Host "LOGIN $ServerId"
Write-Host "PASSWORD $Password"
