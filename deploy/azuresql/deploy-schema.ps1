<#
.SYNOPSIS
    Deploys the retail-demo Azure SQL OLTP source schema in order.

.DESCRIPTION
    Runs schema/01..06 against the target Azure SQL database. Scripts are
    idempotent, so re-running is safe.

    Execution engine (auto-detected, override with -Engine):
      - sqlcmd        : the go-sqlcmd / ODBC command-line tool, if installed.
      - InvokeSqlcmd  : the SqlServer PowerShell module's Invoke-Sqlcmd cmdlet
                        (no external install required).

    Authentication:
      - Default is Azure AD. With sqlcmd this is interactive (browser). With
        Invoke-Sqlcmd an access token is acquired via Az.Accounts or the az CLI.
      - Pass -SqlUser / -SqlPassword to use SQL authentication instead.

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
    [System.Security.SecureString] $SqlPassword,
    [ValidateSet('Auto', 'sqlcmd', 'InvokeSqlcmd')] [string] $Engine = 'Auto'
)

$ErrorActionPreference = 'Stop'
$scriptDir = Join-Path $PSScriptRoot 'schema'
$files = Get-ChildItem -Path $scriptDir -Filter '*.sql' | Sort-Object Name

function Get-PlainPassword {
    param([System.Security.SecureString] $Secure)
    [System.Runtime.InteropServices.Marshal]::PtrToStringAuto(
        [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($Secure))
}

function Get-AadAccessToken {
    # Prefer Az.Accounts (if signed in), fall back to the az CLI.
    if (Get-Command Get-AzAccessToken -ErrorAction SilentlyContinue) {
        try {
            $t = Get-AzAccessToken -ResourceUrl 'https://database.windows.net/' -ErrorAction Stop
            if ($t.Token -is [System.Security.SecureString]) { return (Get-PlainPassword $t.Token) }
            return $t.Token
        }
        catch {
            Write-Verbose "Get-AzAccessToken failed ($($_.Exception.Message)); trying az CLI."
        }
    }
    if (Get-Command az -ErrorAction SilentlyContinue) {
        $token = az account get-access-token --resource https://database.windows.net/ --query accessToken -o tsv
        if ($LASTEXITCODE -eq 0 -and $token) { return $token.Trim() }
    }
    throw 'Could not acquire an Azure AD token. Install Az.Accounts or the az CLI and sign in, or use -SqlUser/-SqlPassword.'
}

# --- Resolve execution engine -------------------------------------------------
$haveSqlcmd = [bool](Get-Command sqlcmd -ErrorAction SilentlyContinue)
$haveInvoke = [bool](Get-Command Invoke-Sqlcmd -ErrorAction SilentlyContinue)

if ($Engine -eq 'Auto') {
    if ($haveSqlcmd) { $Engine = 'sqlcmd' }
    elseif ($haveInvoke) { $Engine = 'InvokeSqlcmd' }
    else { throw 'Neither sqlcmd nor Invoke-Sqlcmd is available. Install go-sqlcmd or the SqlServer PowerShell module.' }
}
elseif ($Engine -eq 'sqlcmd' -and -not $haveSqlcmd) {
    throw 'sqlcmd not found. Install the SQL command-line tools (go-sqlcmd) or use -Engine InvokeSqlcmd.'
}
elseif ($Engine -eq 'InvokeSqlcmd' -and -not $haveInvoke) {
    throw 'Invoke-Sqlcmd not found. Install the SqlServer PowerShell module or use -Engine sqlcmd.'
}

Write-Host "Engine: $Engine" -ForegroundColor DarkGray

# --- Deploy -------------------------------------------------------------------
if ($Engine -eq 'sqlcmd') {
    if ($SqlUser) {
        $authArgs = @('-U', $SqlUser, '-P', (Get-PlainPassword $SqlPassword))
    }
    else {
        # Azure AD interactive (browser) auth
        $authArgs = @('-G', '--authentication-method', 'ActiveDirectoryInteractive')
    }
    foreach ($f in $files) {
        Write-Host "==> $($f.Name)" -ForegroundColor Cyan
        & sqlcmd -S $ServerName -d $DatabaseName @authArgs -b -I -i $f.FullName
        if ($LASTEXITCODE -ne 0) { throw "Deployment failed on $($f.Name) (exit $LASTEXITCODE)." }
    }
}
else {
    # Invoke-Sqlcmd (SqlServer module) — no external tooling required.
    $common = @{
        ServerInstance = $ServerName
        Database       = $DatabaseName
        QueryTimeout   = 300
        AbortOnError   = $true
        ErrorAction    = 'Stop'
    }
    if ($SqlUser) {
        $common['Username'] = $SqlUser
        $common['Password'] = Get-PlainPassword $SqlPassword
    }
    else {
        $common['AccessToken'] = Get-AadAccessToken
    }
    foreach ($f in $files) {
        Write-Host "==> $($f.Name)" -ForegroundColor Cyan
        Invoke-Sqlcmd @common -InputFile $f.FullName
    }
}

Write-Host 'Schema deployment complete.' -ForegroundColor Green
