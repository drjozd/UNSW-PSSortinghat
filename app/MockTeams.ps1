# ============================================================================
#  Sortinghat - practice mode
#
#  Defines stand-ins for the MicrosoftTeams cmdlets backed by an in-memory
#  fake tenant. PowerShell resolves functions before cmdlets, so loading this
#  file shadows the real module and nothing can reach Microsoft 365.
#
#  Used by  .\Start-Sortinghat.ps1 -Mock  for rehearsal, demos and tests.
# ============================================================================

$script:MockDomain = 'ad.unsw.edu.au'
$script:MockMe = 'g.ibello@ad.unsw.edu.au'
$script:MockLatencyMs = 80

function New-MockStudent {
    param([string]$Zid, [string]$First, [string]$Last)
    return [PSCustomObject]@{
        User   = "$Zid@$script:MockDomain"
        UPN    = "$Zid@$script:MockDomain"
        UserId = [guid]::NewGuid().ToString()
        Name   = "$First $Last"
        Role   = 'Member'
    }
}

$script:MockRoster = @(
    @('z5100101','Amara','Okafor'),   @('z5100102','Ben','Lindqvist'),
    @('z5100103','Chiara','Rossi'),   @('z5100104','Daniel','Nguyen'),
    @('z5100105','Esther','Mwangi'),  @('z5100106','Farid','Haddad'),
    @('z5100107','Grace','Tan'),      @('z5100108','Hugo','Martins'),
    @('z5100109','Ines','Duarte'),    @('z5100110','Jonas','Weber'),
    @('z5100111','Keiko','Watanabe'), @('z5100112','Liam','O Sullivan'),
    @('z5100113','Mira','Kaur'),      @('z5100114','Nikolai','Petrov'),
    @('z5100115','Olu','Adeyemi'),    @('z5100116','Priya','Ramesh'),
    @('z5100117','Quentin','Blanc'),  @('z5100118','Rania','Zahra'),
    @('z5100119','Sofia','Vargas'),   @('z5100120','Tomas','Novak'),
    @('z5100121','Uma','Bhatt'),      @('z5100122','Viktor','Larsen'),
    @('z5100123','Wei','Zhang'),      @('z5100124','Yara','Haddad')
)

$script:MockTeams = @{
    '11111111-1111-1111-1111-111111111111' = @{
        DisplayName = 'INFS5885 T3 2026 - Business in the Digital Age'
        Description = 'Teaching team and students'
        Visibility  = 'Private'
        Archived    = $false
    }
    '22222222-2222-2222-2222-222222222222' = @{
        DisplayName = 'INFS5885 T3 2026 - STAFF'
        Description = 'Staff only'
        Visibility  = 'Private'
        Archived    = $false
    }
}

$script:MockMembers = @{}
$script:MockChannels = @{}
$script:MockChannelMembers = @{}

function Initialize-MockTenant {
    $main = '11111111-1111-1111-1111-111111111111'
    $staff = '22222222-2222-2222-2222-222222222222'

    $people = @([PSCustomObject]@{
        User = $script:MockMe; UPN = $script:MockMe
        UserId = [guid]::NewGuid().ToString(); Name = 'Giuseppe Ibello'; Role = 'Owner'
    })
    foreach ($s in $script:MockRoster) { $people += (New-MockStudent -Zid $s[0] -First $s[1] -Last $s[2]) }
    # Two students are on the class list but not yet in the team
    $script:MockMembers[$main] = @($people | Select-Object -First ($people.Count - 2))
    $script:MockMembers[$staff] = @($people[0])

    $script:MockChannels[$main] = @(
        [PSCustomObject]@{ Id = 'ch-general'; DisplayName = 'General';     Description = '';                 MembershipType = 'Standard' }
        [PSCustomObject]@{ Id = 'ch-grp1';    DisplayName = 'Group 1';     Description = 'Assignment group'; MembershipType = 'Private' }
        [PSCustomObject]@{ Id = 'ch-grp2';    DisplayName = 'Group 2';     Description = 'Assignment group'; MembershipType = 'Private' }
        [PSCustomObject]@{ Id = 'ch-tutors';  DisplayName = 'Tutors only'; Description = 'Marking chat';     MembershipType = 'Private' }
    )
    $script:MockChannels[$staff] = @(
        [PSCustomObject]@{ Id = 'ch-sgeneral'; DisplayName = 'General'; Description = ''; MembershipType = 'Standard' }
    )

    $me = [PSCustomObject]@{ User = $script:MockMe; UPN = $script:MockMe; Name = 'Giuseppe Ibello'; Role = 'Owner' }
    $script:MockChannelMembers["$main|Group 1"] = @($me) + @($script:MockMembers[$main] | Select-Object -Skip 1 -First 4)
    $script:MockChannelMembers["$main|Group 2"] = @($me) + @($script:MockMembers[$main] | Select-Object -Skip 5 -First 3)
    $script:MockChannelMembers["$main|Tutors only"] = @($me)
}
Initialize-MockTenant

function Get-MockKey { param([string]$GroupId, [string]$DisplayName) return "$GroupId|$DisplayName" }

function Connect-MicrosoftTeams {
    [CmdletBinding()] param()
    Start-Sleep -Milliseconds 400
    return [PSCustomObject]@{
        Account = [PSCustomObject]@{ Id = $script:MockMe }
        Tenant  = [PSCustomObject]@{ Id = '00000000-0000-0000-0000-0000000000aa' }
    }
}

function Disconnect-MicrosoftTeams { [CmdletBinding()] param() }

function Get-Team {
    [CmdletBinding()]
    param([string]$GroupId, [string]$User, [Nullable[bool]]$Archived, [string]$Visibility,
          [string]$DisplayName, [string]$MailNickName, [int]$NumberOfThreads)
    foreach ($id in $script:MockTeams.Keys) {
        if ($GroupId -and $id -ne $GroupId) { continue }
        $t = $script:MockTeams[$id]
        [PSCustomObject]@{
            GroupId = $id; DisplayName = $t.DisplayName; Description = $t.Description
            Visibility = $t.Visibility; Archived = $t.Archived
        }
    }
}

function Get-TeamUser {
    [CmdletBinding()] param([Parameter(Mandatory = $true)][string]$GroupId, [string]$Role)
    if (-not $script:MockMembers.ContainsKey($GroupId)) { throw "Team '$GroupId' was not found." }
    $list = $script:MockMembers[$GroupId]
    if ($Role) { $list = @($list | Where-Object { $_.Role -eq $Role }) }
    return $list
}

function Get-TeamChannel {
    [CmdletBinding()] param([Parameter(Mandatory = $true)][string]$GroupId, [string]$MembershipType)
    if (-not $script:MockChannels.ContainsKey($GroupId)) { throw "Team '$GroupId' was not found." }
    $list = $script:MockChannels[$GroupId]
    if ($MembershipType) { $list = @($list | Where-Object { $_.MembershipType -eq $MembershipType }) }
    return $list
}

function Get-TeamChannelUser {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$GroupId,
          [Parameter(Mandatory = $true)][string]$DisplayName, [string]$Role)
    $key = Get-MockKey -GroupId $GroupId -DisplayName $DisplayName
    if (-not $script:MockChannelMembers.ContainsKey($key)) { return @() }
    $list = $script:MockChannelMembers[$key]
    if ($Role) { $list = @($list | Where-Object { $_.Role -eq $Role }) }
    return $list
}

function New-TeamChannel {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$GroupId,
          [Parameter(Mandatory = $true)][string]$DisplayName,
          [string]$Description, [string]$MembershipType = 'Standard', [string]$Owner)
    Start-Sleep -Milliseconds $script:MockLatencyMs
    if (-not $script:MockChannels.ContainsKey($GroupId)) { throw "Team '$GroupId' was not found." }
    foreach ($c in $script:MockChannels[$GroupId]) {
        if ($c.DisplayName -eq $DisplayName) { throw "A channel with that name is already in use." }
    }
    $channel = [PSCustomObject]@{
        Id = "ch-" + [guid]::NewGuid().ToString().Substring(0, 8)
        DisplayName = $DisplayName; Description = $Description; MembershipType = $MembershipType
    }
    $script:MockChannels[$GroupId] = @($script:MockChannels[$GroupId]) + @($channel)
    if ($MembershipType -eq 'Private') {
        $ownerUpn = $Owner
        if (-not $ownerUpn) { $ownerUpn = $script:MockMe }
        $script:MockChannelMembers[(Get-MockKey -GroupId $GroupId -DisplayName $DisplayName)] =
            @([PSCustomObject]@{ User = $ownerUpn; UPN = $ownerUpn; Name = 'Channel owner'; Role = 'Owner' })
    }
    return $channel
}

function Add-TeamUser {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$GroupId,
          [Parameter(Mandatory = $true)][string]$User, [string]$Role)
    Start-Sleep -Milliseconds $script:MockLatencyMs
    if (-not $script:MockMembers.ContainsKey($GroupId)) { throw "Team '$GroupId' was not found." }
    foreach ($m in $script:MockMembers[$GroupId]) {
        if ($m.User -eq $User) { throw "User is already a member of this team." }
    }
    $script:MockMembers[$GroupId] = @($script:MockMembers[$GroupId]) + @([PSCustomObject]@{
        User = $User; UPN = $User; UserId = [guid]::NewGuid().ToString(); Name = $User; Role = 'Member'
    })
}

function Add-TeamChannelUser {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$GroupId,
          [Parameter(Mandatory = $true)][string]$DisplayName,
          [Parameter(Mandatory = $true)][string]$User, [string]$Role, [string]$TenantId)
    Start-Sleep -Milliseconds $script:MockLatencyMs

    $inTeam = $false
    foreach ($m in @($script:MockMembers[$GroupId])) { if ($m.User -eq $User) { $inTeam = $true } }
    if (-not $inTeam) { throw "User must first be a member of the team before being added to a private channel." }

    $key = Get-MockKey -GroupId $GroupId -DisplayName $DisplayName
    if (-not $script:MockChannelMembers.ContainsKey($key)) { $script:MockChannelMembers[$key] = @() }

    foreach ($m in $script:MockChannelMembers[$key]) {
        if ($m.User -eq $User) {
            if ($Role -eq 'Owner') { $m.Role = 'Owner'; return }
            throw "User is already a member of this channel."
        }
    }
    if ($Role -eq 'Owner') { throw "User must first be a member of the channel before being made an owner." }

    $name = $User
    foreach ($m in @($script:MockMembers[$GroupId])) { if ($m.User -eq $User) { $name = $m.Name } }
    $script:MockChannelMembers[$key] = @($script:MockChannelMembers[$key]) +
        @([PSCustomObject]@{ User = $User; UPN = $User; Name = $name; Role = 'Member' })
}

function Remove-TeamChannelUser {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$GroupId,
          [Parameter(Mandatory = $true)][string]$DisplayName,
          [Parameter(Mandatory = $true)][string]$User, [string]$Role)
    Start-Sleep -Milliseconds $script:MockLatencyMs

    $key = Get-MockKey -GroupId $GroupId -DisplayName $DisplayName
    if (-not $script:MockChannelMembers.ContainsKey($key)) { throw "Channel '$DisplayName' was not found." }

    $target = $null
    foreach ($m in $script:MockChannelMembers[$key]) { if ($m.User -eq $User) { $target = $m } }
    if (-not $target) { throw "User is not a member of this channel." }

    if ($target.Role -eq 'Owner') {
        $owners = @($script:MockChannelMembers[$key] | Where-Object { $_.Role -eq 'Owner' })
        if ($owners.Count -le 1) { throw "The last owner of a private channel cannot be removed." }
    }
    $script:MockChannelMembers[$key] = @($script:MockChannelMembers[$key] | Where-Object { $_.User -ne $User })
}
