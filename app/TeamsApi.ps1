# ============================================================================
#  Sortinghat - Microsoft Teams layer
#
#  Every call into the MicrosoftTeams module goes through here, so the rules
#  Microsoft enforces (a person must be in the team before they can be in one
#  of its private channels; the last owner of a private channel cannot be
#  removed; writes are eventually consistent) live in one place.
# ============================================================================

$script:ShAccount    = $null
$script:ShTenantId   = $null
$script:ShConnected  = $false

function Get-ShErrorText {
    <#
      The Teams cmdlets wrap their real failure in an AggregateException, whose
      own Message is the useless "One or more errors occurred." Walk the whole
      tree so the log shows what actually went wrong.
    #>
    param($ErrorRecord)

    $messages = @()
    $seen = @{}
    $queue = New-Object System.Collections.Queue
    if ($ErrorRecord -and $ErrorRecord.Exception) { $queue.Enqueue($ErrorRecord.Exception) }

    $guard = 0
    while ($queue.Count -gt 0 -and $guard -lt 16) {
        $guard++
        $ex = $queue.Dequeue()
        if ($null -eq $ex) { continue }

        if ($ex -is [System.AggregateException]) {
            foreach ($inner in $ex.InnerExceptions) { if ($inner) { $queue.Enqueue($inner) } }
        } else {
            $m = [string]$ex.Message
            if ($m -and -not $seen.ContainsKey($m)) { $seen[$m] = $true; $messages += $m }
        }
        if ($ex.InnerException) { $queue.Enqueue($ex.InnerException) }
    }

    $msg = ($messages -join ' -> ')
    if ([string]::IsNullOrWhiteSpace($msg)) { $msg = "$ErrorRecord" }
    $msg = ($msg -replace '\s+', ' ').Trim()
    if ($msg.Length -gt 600) { $msg = $msg.Substring(0, 600) + '...' }
    return $msg
}

function Test-ShThrottleError {
    <# Worth waiting several times for: Teams is busy, not wrong. #>
    param([string]$Message)
    if ([string]::IsNullOrWhiteSpace($Message)) { return $false }
    $m = $Message.ToLowerInvariant()
    foreach ($needle in @('429', 'throttl', 'too many requests', 'timed out', 'timeout',
                          'service unavailable', '503', 'temporarily', 'try again')) {
        if ($m.Contains($needle)) { return $true }
    }
    return $false
}

function Test-ShNotReadyError {
    <#
      A channel created seconds ago is not always visible yet, so one short
      retry is worth it. Beyond that it usually means a mistyped address, and
      making a lecturer wait 30 seconds per typo is not worth it.
    #>
    param([string]$Message)
    if ([string]::IsNullOrWhiteSpace($Message)) { return $false }
    $m = $Message.ToLowerInvariant()
    foreach ($needle in @('not found', 'does not exist', 'could not be found', 'no such')) {
        if ($m.Contains($needle)) { return $true }
    }
    return $false
}

function Test-ShAlreadyDoneError {
    param([string]$Message)
    if ([string]::IsNullOrWhiteSpace($Message)) { return $false }
    $m = $Message.ToLowerInvariant()
    foreach ($needle in @('already exist', 'already a member', 'already added', 'already present',
                          'conflict', 'duplicate', 'name is already in use', 'displayname already')) {
        if ($m.Contains($needle)) { return $true }
    }
    return $false
}

function Get-ShUserField {
    param($Object, [string[]]$Names)
    foreach ($n in $Names) {
        $value = $null
        try { $value = $Object.$n } catch { $value = $null }
        if ($value -and -not [string]::IsNullOrWhiteSpace([string]$value)) { return [string]$value }
    }
    return ''
}

# ---------------------------------------------------------------------------
#  Connection
# ---------------------------------------------------------------------------

function Get-ShConnection {
    return @{
        connected = [bool]$script:ShConnected
        account   = $script:ShAccount
        tenantId  = $script:ShTenantId
    }
}

function Invoke-ShConnect {
    Write-Host ''
    if ($script:ShForceDeviceCode) {
        Write-Host '  Sign in with the device code printed below.' -ForegroundColor Cyan
    } else {
        Write-Host '  A Microsoft sign-in window is opening.' -ForegroundColor Cyan
        Write-Host '  If you cannot see it, check behind this window or on the taskbar.' -ForegroundColor DarkGray
    }
    Write-Host ''

    if ($script:ShForceDeviceCode) {
        $context = Connect-MicrosoftTeams -UseDeviceAuthentication -ErrorAction Stop
    } else {
        try {
            $context = Connect-MicrosoftTeams -ErrorAction Stop
        } catch {
            # Off Windows there is no Web Account Manager, and the browser control
            # does not always come up. The device code flow is the documented
            # fallback, and it prints its instructions in this window.
            if ($script:ShIsWindows) { throw }
            Write-Host ''
            Write-Host '  The sign-in window did not work. Falling back to a device code.' -ForegroundColor Yellow
            Write-Host '  Follow the instructions printed here, then return to your browser.' -ForegroundColor Yellow
            Write-Host ''
            $context = Connect-MicrosoftTeams -UseDeviceAuthentication -ErrorAction Stop
        }
    }

    $account = ''
    if ($context) {
        $account = Get-ShUserField -Object $context.Account -Names @('Id', 'Name', 'UserPrincipalName')
        if (-not $account) { $account = [string]$context.Account }
        if ($context.Tenant) {
            $script:ShTenantId = Get-ShUserField -Object $context.Tenant -Names @('Id', 'TenantId')
        }
    }
    if (-not $account) { $account = 'signed in' }

    $script:ShAccount = $account
    $script:ShConnected = $true

    Write-Host "  Signed in as $account" -ForegroundColor Green
    return Get-ShConnection
}

function Invoke-ShDisconnect {
    try { Disconnect-MicrosoftTeams -ErrorAction SilentlyContinue } catch { }
    $script:ShAccount = $null
    $script:ShTenantId = $null
    $script:ShConnected = $false
    return Get-ShConnection
}

# ---------------------------------------------------------------------------
#  Reading the tenant
# ---------------------------------------------------------------------------

function Get-ShTeams {
    if (-not $script:ShConnected) { throw 'Not signed in yet.' }

    $teams = @()
    $raw = @(Get-Team -User $script:ShAccount -ErrorAction Stop)
    foreach ($t in $raw) {
        $teams += @{
            groupId     = [string]$t.GroupId
            displayName = [string]$t.DisplayName
            description = [string]$t.Description
            visibility  = [string]$t.Visibility
            archived    = [bool]$t.Archived
        }
    }
    return @($teams | Sort-Object { $_.displayName })
}

function Get-ShTeamSnapshot {
    param([Parameter(Mandatory = $true)][string]$GroupId)
    if (-not $script:ShConnected) { throw 'Not signed in yet.' }

    $members = @()
    foreach ($u in @(Get-TeamUser -GroupId $GroupId -ErrorAction Stop)) {
        $upn = Get-ShUserField -Object $u -Names @('User', 'UPN', 'UserPrincipalName', 'Email')
        if (-not $upn) { continue }
        $members += @{
            upn    = $upn
            userId = (Get-ShUserField -Object $u -Names @('UserId', 'Id'))
            name   = (Get-ShUserField -Object $u -Names @('Name', 'DisplayName'))
            role   = (Get-ShUserField -Object $u -Names @('Role'))
        }
    }

    $channels = @()
    foreach ($c in @(Get-TeamChannel -GroupId $GroupId -ErrorAction Stop)) {
        $type = Get-ShUserField -Object $c -Names @('MembershipType')
        if (-not $type) { $type = 'Standard' }
        $channels += @{
            id             = (Get-ShUserField -Object $c -Names @('Id'))
            displayName    = [string]$c.DisplayName
            description    = [string]$c.Description
            membershipType = $type
        }
    }

    $isOwner = $false
    foreach ($m in $members) {
        if ($m.role -and $m.role.ToLowerInvariant() -eq 'owner' -and
            $m.upn.ToLowerInvariant() -eq ([string]$script:ShAccount).ToLowerInvariant()) { $isOwner = $true }
    }

    return @{
        groupId  = $GroupId
        members  = @($members)
        channels = @($channels | Sort-Object { $_.displayName })
        youAreOwner = $isOwner
    }
}

function Test-ShChannelExists {
    <#
      Teams reports a duplicate channel name as a bare BadRequest from its
      templates backend, with no usable text, and it sometimes returns an error
      for a create that in fact succeeded. Asking what is actually there beats
      reading the error message either way.
    #>
    param(
        [Parameter(Mandatory = $true)][string]$GroupId,
        [Parameter(Mandatory = $true)][string]$DisplayName
    )
    try {
        foreach ($c in @(Get-TeamChannel -GroupId $GroupId -ErrorAction Stop)) {
            if ([string]$c.DisplayName -eq $DisplayName) { return $true }
        }
    } catch { }
    return $false
}

function Get-ShChannelMembers {
    param(
        [Parameter(Mandatory = $true)][string]$GroupId,
        [Parameter(Mandatory = $true)][string]$ChannelName
    )
    if (-not $script:ShConnected) { throw 'Not signed in yet.' }

    $people = @()
    foreach ($u in @(Get-TeamChannelUser -GroupId $GroupId -DisplayName $ChannelName -ErrorAction Stop)) {
        $upn = Get-ShUserField -Object $u -Names @('User', 'UPN', 'UserPrincipalName', 'Email')
        if (-not $upn) { continue }
        $people += @{
            upn  = $upn
            name = (Get-ShUserField -Object $u -Names @('Name', 'DisplayName'))
            role = (Get-ShUserField -Object $u -Names @('Role'))
        }
    }
    return @($people)
}

# ---------------------------------------------------------------------------
#  Writing - one operation at a time, so the UI can show honest progress
# ---------------------------------------------------------------------------

function Invoke-ShTeamsWrite {
    <# Runs a single write with retries for throttling and provisioning lag. #>
    param(
        [Parameter(Mandatory = $true)][scriptblock]$Action,
        [int]$MaxAttempts = 4
    )

    $attempt = 0
    while ($true) {
        $attempt++
        try {
            & $Action | Out-Null
            return @{ ok = $true; message = '' }
        } catch {
            $text = Get-ShErrorText -ErrorRecord $_

            if (Test-ShAlreadyDoneError -Message $text) {
                return @{ ok = $true; message = 'Already in place - nothing to change.'; skipped = $true }
            }
            if ($attempt -lt $MaxAttempts -and (Test-ShThrottleError -Message $text)) {
                Start-Sleep -Seconds ([Math]::Min(12, 2 * $attempt))
                continue
            }
            if ($attempt -lt 2 -and (Test-ShNotReadyError -Message $text)) {
                Start-Sleep -Seconds 3
                continue
            }
            return @{ ok = $false; message = $text }
        }
    }
}

function Invoke-ShOperation {
    <#
      $Op is the plan item produced by the browser:
        type        createChannel | addTeamUser | addChannelUser | removeChannelUser | setChannelOwner
        groupId     team to act on
        channel     channel display name (not needed for addTeamUser)
        user        UPN
        description optional, channel creation only
    #>
    param([Parameter(Mandatory = $true)]$Op)

    if (-not $script:ShConnected) { throw 'Not signed in yet.' }

    $groupId = [string]$Op.groupId
    $channel = [string]$Op.channel
    $user    = [string]$Op.user
    $type    = [string]$Op.type

    switch ($type) {

        'createChannel' {
            $description = ''
            if ($Op.PSObject.Properties.Name -contains 'description' -and $Op.description) {
                $description = [string]$Op.description
            }
            $created = Invoke-ShTeamsWrite -Action {
                $newChannelArgs = @{
                    GroupId        = $groupId
                    DisplayName    = $channel
                    MembershipType = 'Private'
                    Owner          = $script:ShAccount
                    ErrorAction    = 'Stop'
                }
                if ($description) { $newChannelArgs['Description'] = $description }
                New-TeamChannel @newChannelArgs
            }
            if ($created.ok) { return $created }

            # Did it work anyway, or is the channel already there?
            Start-Sleep -Seconds 2
            if (Test-ShChannelExists -GroupId $groupId -DisplayName $channel) {
                return @{
                    ok      = $true
                    message = "The channel is there - Teams reported an error but the channel exists."
                    skipped = $true
                }
            }

            $created.message = $created.message +
                ' Teams keeps the name of a deleted channel reserved for good, so if "' +
                $channel + '" ever existed in this team, pick a different name.'
            return $created
        }

        'addTeamUser' {
            return Invoke-ShTeamsWrite -Action {
                Add-TeamUser -GroupId $groupId -User $user -ErrorAction Stop
            }
        }

        'addChannelUser' {
            return Invoke-ShTeamsWrite -Action {
                Add-TeamChannelUser -GroupId $groupId -DisplayName $channel -User $user -ErrorAction Stop
            }
        }

        'setChannelOwner' {
            return Invoke-ShTeamsWrite -Action {
                Add-TeamChannelUser -GroupId $groupId -DisplayName $channel -User $user -Role Owner -ErrorAction Stop
            }
        }

        'removeChannelUser' {
            return Invoke-ShTeamsWrite -Action {
                Remove-TeamChannelUser -GroupId $groupId -DisplayName $channel -User $user -ErrorAction Stop
            }
        }

        default { return @{ ok = $false; message = "Unknown operation '$type'." } }
    }
}
