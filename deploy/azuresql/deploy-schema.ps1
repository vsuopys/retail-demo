<#
.SYNOPSIS
    Deploys the retail-demo Azure SQL OLTP source schema in order.

.DESCRIPTION
    Runs schema/01..06 against the target Azure SQL database. Scripts are
    idempotent, so re-running is safe. Uses Azure AD interactive auth by
    default; pass -SqlUser / -SqlPassword for SQL authentication.

.EXAMPLE
    ./deploy-schema.ps1 -ServerName myserver.database.windows.net -DatabaseName retaildb

.EXAMPLE
    ./deploy-schema.ps1 -ServerName myserver.database.windows.net -DatabaseName retaildb `
        -SqlUser sqladmin -SqlPassword (Read-Host -AsSecureString 'Password')
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)] [string] $ServerName,
    [Parameter(Mandatory = $true)] [string] $DatabaseName,
    [string] $SqlUser,
    [System.Security.SecureString] $SqlPassword
)

$ErrorActionPreference = 'Stop'
$scriptDir = Join-Path $PSScriptRoot 'schema'
$files = Get-ChildItem -Path $scriptDir -Filter '*.sql' | Sort-Object Name

if (-not (Get-Command sqlcmd -ErrorAction SilentlyContinue)) {
    throw "sqlcmd not found. Install the SQL command-line tools (go-sqlcmd) and retry."
}

$authArgs = @()
if ($SqlUser) {
    $plain = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto(
        [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($SqlPassword))
    $authArgs = @('-U', $SqlUser, '-P', $plain)
}
else {
    # Azure AD interactive (browser) auth
    $authArgs = @('-G', '--authentication-method', 'ActiveDirectoryInteractive')
}

foreach ($f in $files) {
    Write-Host "==> $($f.Name)" -ForegroundColor Cyan
    & sqlcmd -S $ServerName -d $DatabaseName @authArgs -b -I -i $f.FullName
    if ($LASTEXITCODE -ne 0) {
        throw "Deployment failed on $($f.Name) (exit $LASTEXITCODE)."
    }
}

Write-Host 'Schema deployment complete.' -ForegroundColor Green
