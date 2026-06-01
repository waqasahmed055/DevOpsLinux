<#
.SYNOPSIS
    Migrate LDAP POSIX identity (uidNumber/gidNumber) into Active Directory.

.DESCRIPTION
    Production-oriented script for Windows Server 2016 AD environments.

    Behavior:
      - Preflights duplicate UIDs/GIDs and bad group references
      - Creates missing groups first
      - Sets group gidNumber at creation time when possible
      - Sets user uidNumber/gidNumber and optional msSFU30NisDomain
      - Adds direct group membership for valid primary groups
      - Supports -WhatIf / -Confirm properly
      - Skips bad data instead of aborting the whole run

.NOTES
    Keep your existing hardcoded $groupMap and $userData blocks unchanged.
#>

[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
param(
    [string]$GroupOU = "",
    [string]$NisDomain = $null,
    [string]$Server = $null
)

Set-StrictMode -Version Latest
Import-Module ActiveDirectory -ErrorAction Stop

# Build common server splat once
$adServerParams = @{}
if (-not [string]::IsNullOrWhiteSpace($Server)) {
    $adServerParams.Server = $Server
}

function Write-Section {
    param([string]$Text)
    Write-Host "`n━━━━ $Text ━━━━`n" -ForegroundColor Cyan
}

function Get-GroupRecord {
    param(
        [Parameter(Mandatory)]
        [string]$GroupName
    )

    $params = @{
        Identity     = $GroupName
        Properties   = 'gidNumber'
        ErrorAction  = 'Stop'
    }
    foreach ($k in $adServerParams.Keys) { $params[$k] = $adServerParams[$k] }

    return Get-ADGroup @params
}

function Resolve-TargetPath {
    param([string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path)) {
        $domainParams = @{ ErrorAction = 'Stop' }
        foreach ($k in $adServerParams.Keys) { $domainParams[$k] = $adServerParams[$k] }

        return (Get-ADDomain @domainParams).UsersContainer
    }

    $objParams = @{
        Identity    = $Path
        ErrorAction = 'Stop'
    }
    foreach ($k in $adServerParams.Keys) { $objParams[$k] = $adServerParams[$k] }

    Get-ADObject @objParams | Out-Null
    return $Path
}

# ---------------------------------------------------------------------------
# Keep your existing hardcoded tables here
# ---------------------------------------------------------------------------
# $groupMap = ...
# $userData = ...
# ---------------------------------------------------------------------------

# Basic sanity check
if (-not $groupMap -or -not $userData) {
    throw "Both `$groupMap and `$userData must be populated before running the script."
}

$targetOU = Resolve-TargetPath -Path $GroupOU

# Tracking
$badUsers  = New-Object 'System.Collections.Generic.HashSet[string]'
$badGroups = New-Object 'System.Collections.Generic.HashSet[string]'

$usersUpdated  = 0
$usersSkipped  = 0
$usersFailed   = 0
$groupsCreated = 0
$groupsUpdated = 0
$groupsSkipped = 0
$groupsFailed  = 0
$membersAdded  = 0
$membersSkipped = 0

Write-Section "Pre-flight validation"

# Duplicate GIDs across distinct group names
$groupMap.GetEnumerator() |
    Group-Object Value |
    Where-Object { $_.Count -gt 1 } |
    ForEach-Object {
        $names = ($_.Group.Name -join ', ')
        Write-Warning "Duplicate GID $($_.Name) shared by: $names. Those groups will be skipped until corrected."
        $_.Group.Name | ForEach-Object { [void]$badGroups.Add($_) }
    }

# Duplicate UIDs across distinct users
$userData |
    Group-Object uid |
    Where-Object { $_.Count -gt 1 } |
    ForEach-Object {
        $names = ($_.Group.username -join ', ')
        Write-Warning "Duplicate UID $($_.Name) shared by: $names. Those users will be skipped until corrected."
        $_.Group.username | ForEach-Object { [void]$badUsers.Add($_) }
    }

# Invalid or missing primary group references
foreach ($u in $userData) {
    if ([string]::IsNullOrWhiteSpace($u.group) -or $u.group -eq '#N/A') {
        Write-Warning "User $($u.username) has no valid primary group ('$($u.group)'). Membership will be skipped."
        continue
    }

    if (-not $groupMap.ContainsKey($u.group)) {
        Write-Warning "User $($u.username) references undefined group '$($u.group)'. Membership will be skipped."
    }
}

Write-Host ("Loaded: {0} users, {1} group definitions." -f $userData.Count, $groupMap.Count) -ForegroundColor Gray

Write-Section "Phase 1: Groups"

foreach ($groupName in $groupMap.Keys) {
    if ($badGroups.Contains($groupName)) {
        Write-Host "Skipped (duplicate GID): $groupName" -ForegroundColor Yellow
        $groupsSkipped++
        continue
    }

    $gid = [int]$groupMap[$groupName]

    try {
        $grp = Get-GroupRecord -GroupName $groupName

        if ([int]$grp.gidNumber -eq $gid) {
            Write-Host "Group already correct: $groupName | GID: $gid" -ForegroundColor DarkGray
            $groupsSkipped++
            continue
        }

        if ($PSCmdlet.ShouldProcess($groupName, "Set gidNumber=$gid")) {
            $setParams = @{
                Identity    = $groupName
                Replace     = @{ gidNumber = $gid }
                ErrorAction = 'Stop'
            }
            foreach ($k in $adServerParams.Keys) { $setParams[$k] = $adServerParams[$k] }

            Set-ADGroup @setParams
            Write-Host "Group updated: $groupName | GID: $gid" -ForegroundColor Green
            $groupsUpdated++
        } else {
            $groupsSkipped++
        }
    }
    catch [Microsoft.ActiveDirectory.Management.ADIdentityNotFoundException] {
        try {
            if ($PSCmdlet.ShouldProcess($groupName, "Create group in $targetOU with gidNumber=$gid")) {
                $newParams = @{
                    Name           = $groupName
                    SamAccountName = $groupName
                    GroupScope     = 'Global'
                    GroupCategory  = 'Security'
                    Path           = $targetOU
                    OtherAttributes = @{
                        gidNumber = $gid
                    }
                    ErrorAction    = 'Stop'
                }
                foreach ($k in $adServerParams.Keys) { $newParams[$k] = $adServerParams[$k] }

                New-ADGroup @newParams | Out-Null
                Write-Host "Group created: $groupName | GID: $gid" -ForegroundColor Green
                $groupsCreated++
            } else {
                $groupsSkipped++
            }
        }
        catch {
            Write-Host "Failed to create group $groupName : $($_.Exception.Message)" -ForegroundColor Red
            $groupsFailed++
        }
    }
    catch {
        Write-Host "Group error $groupName : $($_.Exception.Message)" -ForegroundColor Red
        $groupsFailed++
    }
}

Write-Section "Phase 2: Users"

foreach ($item in $userData) {
    if ($badUsers.Contains($item.username)) {
        Write-Host "Skipped (flagged in pre-flight): $($item.username)" -ForegroundColor Yellow
        $usersSkipped++
        continue
    }

    try {
        $getUserParams = @{
            Identity    = $item.username
            Properties  = 'uidNumber','gidNumber','Enabled','memberOf','msSFU30NisDomain'
            ErrorAction = 'Stop'
        }
        foreach ($k in $adServerParams.Keys) { $getUserParams[$k] = $adServerParams[$k] }

        $user = Get-ADUser @getUserParams

        if (-not $user.Enabled) {
            Write-Host "Skipped (account disabled): $($item.username)" -ForegroundColor Yellow
            $usersSkipped++
            continue
        }

        # Determine whether the user's primary group is valid
        $applyGid = $null
        $groupObj = $null
        $groupDn  = $null
        $validGroup = $false

        if (-not [string]::IsNullOrWhiteSpace($item.group) -and $item.group -ne '#N/A' -and
            $groupMap.ContainsKey($item.group) -and -not $badGroups.Contains($item.group)) {

            $validGroup = $true
            $applyGid = [int]$groupMap[$item.group]

            try {
                $groupObj = Get-GroupRecord -GroupName $item.group
                $groupDn = $groupObj.DistinguishedName
            }
            catch {
                if (-not $WhatIfPreference) {
                    Write-Warning "Primary group '$($item.group)' was not found in AD for user '$($item.username)'; membership will be skipped."
                }
            }
        }

        $replace = @{}

        if (($user.uidNumber -as [int]) -ne [int]$item.uid) {
            $replace.uidNumber = [int]$item.uid
        }

        if ($validGroup -and ($user.gidNumber -as [int]) -ne $applyGid) {
            $replace.gidNumber = $applyGid
        }

        if (-not [string]::IsNullOrWhiteSpace($NisDomain) -and $user.msSFU30NisDomain -ne $NisDomain) {
            $replace.msSFU30NisDomain = $NisDomain
        }

        if ($replace.Count -gt 0) {
            if ($PSCmdlet.ShouldProcess($item.username, "Set POSIX attributes")) {
                $setUserParams = @{
                    Identity    = $item.username
                    Replace     = $replace
                    ErrorAction = 'Stop'
                }
                foreach ($k in $adServerParams.Keys) { $setUserParams[$k] = $adServerParams[$k] }

                Set-ADUser @setUserParams
                Write-Host "User updated: $($item.username) | UID: $($item.uid) | GID: $($replace.gidNumber)" -ForegroundColor Green
                $usersUpdated++
            } else {
                $usersSkipped++
            }
        }
        else {
            $gidText = if ($validGroup) { $applyGid } else { 'n/a' }
            Write-Host "User already correct: $($item.username) | UID: $($item.uid) | GID: $gidText" -ForegroundColor DarkGray
            $usersSkipped++
        }

        # Direct membership add for valid groups only
        if ($validGroup -and $groupDn) {
            $currentMemberOf = @($user.memberOf)
            if ($currentMemberOf -contains $groupDn) {
                Write-Host "Already member: $($item.username) -> $($item.group)" -ForegroundColor DarkGray
                $membersSkipped++
            }
            else {
                if ($PSCmdlet.ShouldProcess($item.group, "Add member $($item.username)")) {
                    $addParams = @{
                        Identity    = $item.group
                        Members     = $item.username
                        ErrorAction = 'Stop'
                    }
                    foreach ($k in $adServerParams.Keys) { $addParams[$k] = $adServerParams[$k] }

                    Add-ADGroupMember @addParams
                    Write-Host "Added to group: $($item.username) -> $($item.group)" -ForegroundColor Green
                    $membersAdded++
                }
            }
        }
    }
    catch [Microsoft.ActiveDirectory.Management.ADIdentityNotFoundException] {
        Write-Host "User not found in AD: $($item.username)" -ForegroundColor Red
        $usersFailed++
    }
    catch {
        Write-Host "Failed user $($item.username) : $($_.Exception.Message)" -ForegroundColor Red
        $usersFailed++
    }
}

Write-Section "Summary"

Write-Host "Users   — Updated: $usersUpdated  Skipped: $usersSkipped  Failed: $usersFailed"
Write-Host "Groups  — Created: $groupsCreated  Updated: $groupsUpdated  Skipped: $groupsSkipped  Failed: $groupsFailed"
Write-Host "Members — Added:   $membersAdded  Skipped: $membersSkipped"

if (($usersFailed + $groupsFailed) -gt 0) {
    Write-Error "Completed with errors. Review the output above."
    exit 1
}
