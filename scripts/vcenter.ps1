<# 
.SYNOPSIS
    Export Linux VMs from vCenter into an Ansible inventory INI file.

.DESCRIPTION
    Connects to vCenter, finds only Linux virtual machines, and writes a simple
    Ansible inventory file in INI format.

    Output example:
      [linux]
      app01 ansible_host=10.10.1.11 ansible_user=ansible
      db01  ansible_host=10.10.1.12 ansible_user=ansible

.NOTES
    Requires VMware PowerCLI module.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$VCenterServer,

    [Parameter(Mandatory = $true)]
    [string]$OutputPath,

    [Parameter(Mandatory = $false)]
    [string]$AnsibleUser = "ansible",

    [Parameter(Mandatory = $false)]
    [switch]$IgnoreCertificateWarnings
)

function Get-FirstIPv4Address {
    param(
        [Parameter(Mandatory = $true)]
        $Vm
    )

    try {
        $ips = @()

        if ($Vm.ExtensionData -and $Vm.ExtensionData.Guest -and $Vm.ExtensionData.Guest.Net) {
            foreach ($net in $Vm.ExtensionData.Guest.Net) {
                if ($net.IpAddress) {
                    $ips += $net.IpAddress
                }
            }
        }

        $ipv4 = $ips | Where-Object {
            $_ -match '^\d{1,3}(\.\d{1,3}){3}$'
        } | Select-Object -First 1

        return $ipv4
    }
    catch {
        return $null
    }
}

function Convert-ToInventoryName {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    $clean = $Name.Trim()

    $clean = $clean -replace '\s+', '_'          # spaces to underscores
    $clean = $clean -replace '[^a-zA-Z0-9_.-]', '_'  # remove unsafe chars
    $clean = $clean -replace '_+', '_'           # collapse repeats

    return $clean
}

function Test-IsLinuxVm {
    param(
        [Parameter(Mandatory = $true)]
        $Vm
    )

    $guestFullName = $null
    $guestId = $null

    if ($Vm.ExtensionData) {
        $guestFullName = $Vm.ExtensionData.Guest.GuestFullName
        $guestId = $Vm.ExtensionData.Config.GuestId
    }

    $linuxRegex = 'linux|oracle linux|red hat|rhel|centos|ubuntu|debian|suse|opensuse|rocky|alma|amazon linux'

    return (
        ($guestFullName -and ($guestFullName -match $linuxRegex)) -or
        ($guestId -and ($guestId -match 'linux|rhel|sles|ubuntu|debian|centos|rocky|alma|oracle'))
    )
}

try {
    if ($IgnoreCertificateWarnings) {
        Set-PowerCLIConfiguration -InvalidCertificateAction Ignore -Confirm:$false | Out-Null
    }

    $cred = Get-Credential -Message "Enter vCenter credentials"
    Connect-VIServer -Server $VCenterServer -Credential $cred | Out-Null

    $linuxVms = Get-VM | Where-Object { Test-IsLinuxVm -Vm $_ } | Sort-Object Name

    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add("# Ansible inventory generated from vCenter")
    $lines.Add("# vCenter: $VCenterServer")
    $lines.Add("# Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')")
    $lines.Add("")

    $lines.Add("[linux]")
    foreach ($vm in $linuxVms) {
        $inventoryName = Convert-ToInventoryName -Name $vm.Name
        $ipAddress = Get-FirstIPv4Address -Vm $vm

        if ([string]::IsNullOrWhiteSpace($ipAddress)) {
            Write-Warning "Skipping $($vm.Name) because no IPv4 address was found."
            continue
        }

        $guestFullName = $vm.ExtensionData.Guest.GuestFullName
        $lines.Add(("{0} ansible_host={1} ansible_user={2} vmware_guest_os={3}" -f `
            $inventoryName, $ipAddress, $AnsibleUser, ($guestFullName -replace '\s+', '_')))
    }

    $lines.Add("")
    $lines.Add("[linux:vars]")
    $lines.Add("ansible_connection=ssh")
    $lines.Add("ansible_port=22")

    $outputDir = Split-Path -Path $OutputPath -Parent
    if ($outputDir -and -not (Test-Path $outputDir)) {
        New-Item -Path $outputDir -ItemType Directory -Force | Out-Null
    }

    $lines | Set-Content -Path $OutputPath -Encoding UTF8

    Write-Host "Inventory written to: $OutputPath"
    Write-Host "Linux VMs exported: $($linuxVms.Count)"
}


###.\Export-LinuxInventory.ps1 -VCenterServer "vcenter.example.com" -OutputPath "C:\temp\inventory.ini" -AnsibleUser "ansible" -IgnoreCertificateWarnings
finally {
    Disconnect-VIServer -Server * -Confirm:$false -ErrorAction SilentlyContinue | Out-Null
}
