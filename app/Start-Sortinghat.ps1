<#
.SYNOPSIS
    Sortinghat - sort a class into Teams private channels by drag and drop.

.DESCRIPTION
    Starts a small web page on this computer only (nothing is published to the
    internet), signs you in to Microsoft Teams with your normal university
    login, and lets you drag students into private channels. Nothing is changed
    in Teams until you review the plan and press Apply.

.PARAMETER Port
    Fix the local port instead of letting Windows pick a free one.

.PARAMETER NoBrowser
    Start the server but do not open a browser (used for testing).

.PARAMETER Mock
    Run against a fake tenant instead of Microsoft Teams. Nothing real is
    touched. Useful for practising, demonstrating, or testing changes.

.PARAMETER DeviceCode
    Sign in with a device code shown in this window instead of a browser
    control. Useful on macOS, or anywhere the sign-in window will not appear.

.EXAMPLE
    .\Start-Sortinghat.ps1

.EXAMPLE
    .\Start-Sortinghat.ps1 -Mock
#>
[CmdletBinding()]
param(
    [int]$Port = 0,
    [switch]$NoBrowser,
    [switch]$Mock,
    [switch]$DeviceCode
)

$ErrorActionPreference = 'Stop'

$script:ShVersion = '1.1.0'

# The program lives in app\ ; reports and anything the lecturer should find go
# in the folder above it, next to the launchers.
$script:ShAppRoot = $PSScriptRoot
if (-not $script:ShAppRoot) { $script:ShAppRoot = (Get-Location).Path }
$script:ShRoot = Split-Path -Parent $script:ShAppRoot
if (-not $script:ShRoot) { $script:ShRoot = $script:ShAppRoot }
$script:ShMockMode = [bool]$Mock -or ($env:SORTINGHAT_MOCK -eq '1')
$script:ShTeamsModuleName = 'MicrosoftTeams'
$script:ShTeamsModuleVersion = ''
$script:ShForceDeviceCode = [bool]$DeviceCode

# $IsWindows only exists in PowerShell 6+. On Windows PowerShell 5.1 it is
# undefined, and that only ever runs on Windows anyway.
$script:ShIsWindows = $true
$script:ShIsMacOS = $false
if ($PSVersionTable.PSVersion.Major -ge 6) {
    $script:ShIsWindows = [bool]$IsWindows
    $script:ShIsMacOS = [bool]$IsMacOS
}
$script:ShPlatform = if ($script:ShIsMacOS) { 'macos' } elseif ($script:ShIsWindows) { 'windows' } else { 'linux' }

function Invoke-ShOpenExternal {
    <# Open a URL or folder in whatever the desktop uses. #>
    param([Parameter(Mandatory = $true)][string]$Target)
    try {
        # A native command that fails does not throw, so check the exit code too.
        if ($script:ShIsMacOS) {
            & /usr/bin/open $Target 2>$null | Out-Null
            return ($LASTEXITCODE -eq 0)
        }
        if (-not $script:ShIsWindows) {
            & xdg-open $Target 2>$null | Out-Null
            return ($LASTEXITCODE -eq 0)
        }
        Start-Process $Target | Out-Null
        return $true
    } catch {
        return $false
    }
}

function Write-ShBanner {
    Write-Host ''
    Write-Host '  ____             _   _                _           _   ' -ForegroundColor DarkCyan
    Write-Host ' / ___|  ___  _ __| |_(_)_ __   __ _  | |__   __ _| |_ ' -ForegroundColor DarkCyan
    Write-Host ' \___ \ / _ \|  __| __| |  _ \ / _  | |  _ \ / _  | __|' -ForegroundColor DarkCyan
    Write-Host '  ___) | (_) | |  | |_| | | | | (_| | | | | | (_| | |_ ' -ForegroundColor DarkCyan
    Write-Host ' |____/ \___/|_|   \__|_|_| |_|\__, | |_| |_|\__,_|\__|' -ForegroundColor DarkCyan
    Write-Host '                               |___/                   ' -ForegroundColor DarkCyan
    Write-Host "  Sort a class into Teams private channels   v$script:ShVersion" -ForegroundColor Gray
    Write-Host ''
}

function Assert-ShPowerShellVersion {
    $v = $PSVersionTable.PSVersion
    if ($script:ShIsWindows) {
        if ($v.Major -lt 5) {
            throw "Sortinghat needs Windows PowerShell 5.1 or later. This is version $v."
        }
    } else {
        # Microsoft supports the Teams module on PowerShell 7.2+ off Windows.
        if ($v.Major -lt 7 -or ($v.Major -eq 7 -and $v.Minor -lt 2)) {
            throw "On $($script:ShPlatform) the Microsoft Teams module needs PowerShell 7.2 or later. This is version $v. Install it with: brew install --cask powershell"
        }
    }
}

function Install-ShTeamsModuleIfNeeded {
    <# Returns the newest installed MicrosoftTeams module, installing it first if needed. #>
    $module = Get-Module -ListAvailable -Name MicrosoftTeams |
              Sort-Object Version -Descending | Select-Object -First 1
    if ($module) { return $module }

    Write-Host '  The Microsoft Teams PowerShell module is not installed yet.' -ForegroundColor Yellow
    Write-Host '  It installs under your own user account - no administrator rights needed.' -ForegroundColor DarkGray
    Write-Host ''
    $answer = Read-Host '  Install it now? (Y/N)'
    if ($answer -notmatch '^[Yy]') {
        throw 'Sortinghat cannot run without the MicrosoftTeams module.'
    }

    Write-Host '  Installing - this takes a couple of minutes the first time...' -ForegroundColor Cyan
    try {
        [Net.ServicePointManager]::SecurityProtocol =
            [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    } catch { }
    try { Get-PackageProvider -Name NuGet -ForceBootstrap -ErrorAction SilentlyContinue | Out-Null } catch { }

    Install-Module -Name MicrosoftTeams -Scope CurrentUser -Force -AllowClobber -ErrorAction Stop

    $module = Get-Module -ListAvailable -Name MicrosoftTeams |
              Sort-Object Version -Descending | Select-Object -First 1
    if (-not $module) { throw 'The module did not install. See README.md, "When something goes wrong".' }
    return $module
}

# ---------------------------------------------------------------------------

try {
    Clear-Host
} catch { }

Write-ShBanner
Assert-ShPowerShellVersion

. (Join-Path $script:ShAppRoot 'Server.ps1')
. (Join-Path $script:ShAppRoot 'TeamsApi.ps1')
. (Join-Path $script:ShAppRoot 'Api.ps1')

if ($script:ShMockMode) {
    Write-Host '  Practice mode: using a fake tenant. Nothing real will change.' -ForegroundColor Yellow
    . (Join-Path $script:ShAppRoot 'MockTeams.ps1')
    $script:ShTeamsModuleName = 'Practice mode (no real Teams connection)'
    $script:ShTeamsModuleVersion = 'mock'
} else {
    $teamsModule = Install-ShTeamsModuleIfNeeded
    Write-Host "  Loading the Microsoft Teams module (v$($teamsModule.Version))..." -ForegroundColor DarkGray
    Import-Module -Name MicrosoftTeams -MinimumVersion $teamsModule.Version -Global -ErrorAction Stop
    $script:ShTeamsModuleVersion = [string]$teamsModule.Version
}

$sessionKey = New-ShSessionKey
$uiRoot = Join-Path $script:ShAppRoot 'ui'

$onReady = {
    param([int]$boundPort)
    $url = "http://127.0.0.1:$boundPort/?k=$sessionKey"

    Write-Host ''
    Write-Host '  Sortinghat is running on this computer only.' -ForegroundColor Green
    Write-Host "  If the page does not open by itself, paste this into your browser:" -ForegroundColor DarkGray
    Write-Host "  $url" -ForegroundColor White
    Write-Host ''
    Write-Host '  Keep this window open while you work. Close it to stop Sortinghat.' -ForegroundColor DarkGray
    Write-Host ''

    if (-not $NoBrowser) {
        if (-not (Invoke-ShOpenExternal -Target $url)) {
            Write-Host '  Could not open your browser automatically - use the link above.' -ForegroundColor Yellow
        }
    }
}

try {
    Start-ShServer -UiRoot $uiRoot -SessionKey $sessionKey -OnReady $onReady -Port $Port
} finally {
    Write-Host ''
    Write-Host '  Sortinghat has stopped.' -ForegroundColor Gray
    if (-not $script:ShMockMode) {
        try { Disconnect-MicrosoftTeams -ErrorAction SilentlyContinue } catch { }
    }
}
