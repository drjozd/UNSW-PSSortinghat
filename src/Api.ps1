# ============================================================================
#  Sortinghat - JSON API
#
#  Every endpoint answers the same shape: { ok = $true, ... } on success,
#  { ok = $false; error = 'plain english' } on failure. The browser never sees
#  a PowerShell stack trace.
# ============================================================================

function Get-ShQueryValue {
    param($Query, [string]$Name, [string]$Default = '')
    if ($Query -and $Query.ContainsKey($Name)) { return [string]$Query[$Name] }
    return $Default
}

function Get-ShBodyValue {
    param($Body, [string]$Name, $Default = $null)
    if ($null -eq $Body) { return $Default }
    $prop = $Body.PSObject.Properties[$Name]
    if ($null -eq $prop) { return $Default }
    if ($null -eq $prop.Value) { return $Default }
    return $prop.Value
}

function Invoke-ShRoute {
    param(
        [string]$Method,
        [string]$Path,
        $Query,
        $Body
    )

    switch ("$Method $Path") {

        # -- housekeeping ----------------------------------------------------

        'GET /api/state' {
            $conn = Get-ShConnection
            return @{
                ok           = $true
                connected    = $conn.connected
                account      = $conn.account
                appVersion   = $script:ShVersion
                moduleName   = $script:ShTeamsModuleName
                moduleVersion= $script:ShTeamsModuleVersion
                mock         = [bool]$script:ShMockMode
            }
        }

        'POST /api/connect' {
            try {
                $conn = Invoke-ShConnect
                return @{ ok = $true; connected = $conn.connected; account = $conn.account }
            } catch {
                return @{ ok = $false; error = "Sign-in did not complete: $(Get-ShErrorText -ErrorRecord $_)" }
            }
        }

        'POST /api/disconnect' {
            $conn = Invoke-ShDisconnect
            return @{ ok = $true; connected = $conn.connected }
        }

        'POST /api/quit' {
            Stop-ShServer
            return @{ ok = $true }
        }

        # -- reading ---------------------------------------------------------

        'GET /api/teams' {
            try {
                return @{ ok = $true; teams = @(Get-ShTeams) }
            } catch {
                return @{ ok = $false; error = "Could not list your teams: $(Get-ShErrorText -ErrorRecord $_)" }
            }
        }

        'GET /api/team' {
            $groupId = Get-ShQueryValue -Query $Query -Name 'groupId'
            if (-not $groupId) { return @{ ok = $false; error = 'No team was specified.' } }
            try {
                $snapshot = Get-ShTeamSnapshot -GroupId $groupId
                return @{
                    ok          = $true
                    members     = @($snapshot.members)
                    channels    = @($snapshot.channels)
                    youAreOwner = $snapshot.youAreOwner
                }
            } catch {
                return @{ ok = $false; error = "Could not open that team: $(Get-ShErrorText -ErrorRecord $_)" }
            }
        }

        'GET /api/channel-members' {
            $groupId = Get-ShQueryValue -Query $Query -Name 'groupId'
            $channel = Get-ShQueryValue -Query $Query -Name 'channel'
            if (-not $groupId -or -not $channel) { return @{ ok = $false; error = 'Team or channel missing.' } }
            try {
                return @{ ok = $true; members = @(Get-ShChannelMembers -GroupId $groupId -ChannelName $channel) }
            } catch {
                return @{ ok = $false; error = "Could not read '$channel': $(Get-ShErrorText -ErrorRecord $_)" }
            }
        }

        # -- writing ---------------------------------------------------------

        'POST /api/op' {
            $op = Get-ShBodyValue -Body $Body -Name 'op'
            if ($null -eq $op) { return @{ ok = $false; error = 'No operation was sent.' } }
            try {
                $result = Invoke-ShOperation -Op $op
                return @{
                    ok      = [bool]$result.ok
                    message = [string]$result.message
                    skipped = [bool]$result.skipped
                }
            } catch {
                return @{ ok = $false; message = (Get-ShErrorText -ErrorRecord $_) }
            }
        }

        'POST /api/report' {
            try {
                $rows = @(Get-ShBodyValue -Body $Body -Name 'rows' -Default @())
                $label = [string](Get-ShBodyValue -Body $Body -Name 'label' -Default 'run')
                if ($rows.Count -eq 0) { return @{ ok = $false; error = 'There was nothing to report.' } }

                $safeLabel = ($label -replace '[^A-Za-z0-9\-_ ]', '').Trim()
                if (-not $safeLabel) { $safeLabel = 'run' }
                $safeLabel = $safeLabel -replace '\s+', '-'

                $folder = Join-Path $script:ShRoot 'reports'
                if (-not (Test-Path -LiteralPath $folder)) {
                    New-Item -ItemType Directory -Path $folder -Force | Out-Null
                }
                $file = Join-Path $folder ("sortinghat-{0}-{1}.csv" -f $safeLabel, (Get-Date -Format 'yyyyMMdd-HHmmss'))

                $records = foreach ($r in $rows) {
                    [PSCustomObject]@{
                        Time    = [string]$r.time
                        Action  = [string]$r.action
                        Channel = [string]$r.channel
                        Person  = [string]$r.person
                        Result  = [string]$r.result
                        Detail  = [string]$r.detail
                    }
                }
                $records | Export-Csv -LiteralPath $file -NoTypeInformation -Encoding UTF8

                return @{ ok = $true; path = $file }
            } catch {
                return @{ ok = $false; error = "Could not save the report: $(Get-ShErrorText -ErrorRecord $_)" }
            }
        }

        'POST /api/open-reports' {
            try {
                $folder = Join-Path $script:ShRoot 'reports'
                if (Test-Path -LiteralPath $folder) { Start-Process $folder | Out-Null }
                return @{ ok = $true }
            } catch {
                return @{ ok = $false; error = (Get-ShErrorText -ErrorRecord $_) }
            }
        }

        default {
            return @{ ok = $false; error = "Unknown request: $Method $Path" }
        }
    }
}
