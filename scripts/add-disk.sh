<#
.SYNOPSIS
    Adds a new hard disk to one or more vSphere VMs via PowerCLI.

.DESCRIPTION
    Single-VM mode: pass -VMName (and optionally -SizeGB, -Datastore, -StorageFormat).
    Multi-VM mode:  pass -CsvPath pointing to a CSV with columns: VMName,SizeGB,Datastore
                    (Datastore column can be blank to auto-use the VM's existing datastore).

    Validates the VM and free datastore space before adding the disk, then logs
    results to Success.csv / Failed.csv in the script's working directory.

.PARAMETER VCenterServer
    FQDN or IP of the vCenter server.

.PARAMETER VMName
    Single VM name (single-VM mode).

.PARAMETER SizeGB
    Disk size in GB. Default 5.

.PARAMETER Datastore
    Datastore name to place the disk on. If omitted, uses the VM's existing datastore
    with the most free space.

.PARAMETER StorageFormat
    Thin, Thick, or EagerZeroedThick. Default Thin.

.PARAMETER CsvPath
    Path to a CSV for multi-VM mode. Columns: VMName,SizeGB,Datastore

.PARAMETER MinFreePercent
    Minimum free space (%) required on the target datastore before adding the disk. Default 20.

.PARAMETER WhatIfPreview
    If set, shows what would happen without actually creating any disks.

.EXAMPLE
    .\Add-VMDisk.ps1 -VCenterServer vcenter.company.local -VMName "app-vm-01" -SizeGB 5

.EXAMPLE
    .\Add-VMDisk.ps1 -VCenterServer vcenter.company.local -CsvPath .\vms.csv

    vms.csv:
        VMName,SizeGB,Datastore
        app-vm-01,5,
        app-vm-02,5,DS-Cluster-01
        app-vm-03,10,DS-Cluster-02
#>

[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter(Mandatory = $true)]
    [string]$VCenterServer,

    [Parameter(ParameterSetName = 'Single')]
    [string]$VMName,

    [Parameter(ParameterSetName = 'Single')]
    [decimal]$SizeGB = 5,

    [Parameter(ParameterSetName = 'Single')]
    [string]$Datastore,

    [Parameter(ParameterSetName = 'Multi', Mandatory = $true)]
    [string]$CsvPath,

    [ValidateSet('Thin', 'Thick', 'EagerZeroedThick')]
    [string]$StorageFormat = 'Thin',

    [int]$MinFreePercent = 20,

    [PSCredential]$Credential
)

$ErrorActionPreference = 'Stop'
$scriptRoot   = Split-Path -Parent $MyInvocation.MyCommand.Path
$successLog   = Join-Path $scriptRoot 'Success.csv'
$failedLog    = Join-Path $scriptRoot 'Failed.csv'

function Ensure-PowerCLI {
    if (-not (Get-Module -ListAvailable -Name VMware.PowerCLI)) {
        throw "VMware.PowerCLI module not found. Install with: Install-Module VMware.PowerCLI -Scope CurrentUser"
    }
    Import-Module VMware.PowerCLI -ErrorAction Stop
    # Suppress cert-warning prompts / CEIP prompt noise in non-interactive runs
    Set-PowerCLIConfiguration -InvalidCertificateAction Ignore -ParticipateInCeip $false -Confirm:$false | Out-Null
}

function Connect-ToVCenter {
    param([string]$Server, [PSCredential]$Cred)
    if ($Cred) {
        Connect-VIServer -Server $Server -Credential $Cred -ErrorAction Stop | Out-Null
    }
    else {
        Connect-VIServer -Server $Server -ErrorAction Stop | Out-Null
    }
}

function Resolve-TargetDatastore {
    param($VM, [string]$RequestedDatastore, [decimal]$RequiredGB, [int]$MinFreePct)

    if ($RequestedDatastore) {
        $ds = Get-Datastore -Name $RequestedDatastore -ErrorAction Stop
    }
    else {
        # Pick the VM's own datastore with the most free space
        $ds = $VM | Get-Datastore | Sort-Object -Property FreeSpaceGB -Descending | Select-Object -First 1
        if (-not $ds) { throw "Could not determine a datastore for VM '$($VM.Name)'." }
    }

    $freePercent = ($ds.FreeSpaceGB / $ds.CapacityGB) * 100
    $freeAfter   = $ds.FreeSpaceGB - $RequiredGB

    if ($freeAfter -lt 0) {
        throw "Datastore '$($ds.Name)' does not have enough free space for a $RequiredGB GB disk (free: $([math]::Round($ds.FreeSpaceGB,1)) GB)."
    }
    if ($freePercent -lt $MinFreePct) {
        throw "Datastore '$($ds.Name)' free space ($([math]::Round($freePercent,1))%) is below the minimum threshold ($MinFreePct%)."
    }

    return $ds
}

function Add-DiskToVM {
    param($VMNameIn, [decimal]$Size, [string]$DatastoreName)

    $result = [pscustomobject]@{
        VMName    = $VMNameIn
        SizeGB    = $Size
        Datastore = $DatastoreName
        Status    = $null
        Detail    = $null
        Timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    }

    try {
        $vm = Get-VM -Name $VMNameIn -ErrorAction Stop
        $ds = Resolve-TargetDatastore -VM $vm -RequestedDatastore $DatastoreName -RequiredGB $Size -MinFreePct $MinFreePercent

        if ($PSCmdlet.ShouldProcess($VMNameIn, "Add $Size GB $StorageFormat disk on datastore '$($ds.Name)'")) {
            $newDisk = New-HardDisk -VM $vm -CapacityGB $Size -Datastore $ds -StorageFormat $StorageFormat -Confirm:$false
            $result.Status    = 'Success'
            $result.Datastore = $ds.Name
            $result.Detail    = "Added $($newDisk.Name) ($($newDisk.CapacityGB) GB, $($newDisk.Filename))"
        }
        else {
            $result.Status = 'WhatIf'
            $result.Detail = "Would add $Size GB $StorageFormat disk on datastore '$($ds.Name)'"
        }
    }
    catch {
        $result.Status = 'Failed'
        $result.Detail = $_.Exception.Message
    }

    return $result
}

# ---- Main ----

Ensure-PowerCLI
Connect-ToVCenter -Server $VCenterServer -Cred $Credential

$results = @()

try {
    if ($PSCmdlet.ParameterSetName -eq 'Multi') {
        if (-not (Test-Path $CsvPath)) { throw "CSV file not found: $CsvPath" }
        $rows = Import-Csv -Path $CsvPath

        foreach ($row in $rows) {
            $size = if ($row.SizeGB) { [decimal]$row.SizeGB } else { 5 }
            $results += Add-DiskToVM -VMNameIn $row.VMName -Size $size -DatastoreName $row.Datastore
        }
    }
    else {
        if (-not $VMName) { throw "Provide -VMName for single-VM mode, or -CsvPath for multi-VM mode." }
        $results += Add-DiskToVM -VMNameIn $VMName -Size $SizeGB -DatastoreName $Datastore
    }
}
finally {
    Disconnect-VIServer -Server $VCenterServer -Confirm:$false -ErrorAction SilentlyContinue
}

# ---- Report ----

$results | Format-Table -AutoSize

$successRows = $results | Where-Object { $_.Status -eq 'Success' }
$failedRows  = $results | Where-Object { $_.Status -eq 'Failed' }

if ($successRows) { $successRows | Export-Csv -Path $successLog -Append -NoTypeInformation }
if ($failedRows)  { $failedRows  | Export-Csv -Path $failedLog  -Append -NoTypeInformation }

Write-Host "`nDone. Success: $($successRows.Count)  Failed: $($failedRows.Count)" -ForegroundColor Cyan
if ($failedRows) { Write-Host "See $failedLog for details." -ForegroundColor Yellow }
