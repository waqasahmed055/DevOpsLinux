Get-VM |
  Where-Object {
    $_.PowerState -eq 'PoweredOn' -and
    (
      ($_.ExtensionData.Guest.GuestFamily -eq 'linuxGuest') -or
      ($_.Guest.OSFullName -and $_.Guest.OSFullName -match 'Linux|Ubuntu|CentOS|Debian|Red Hat|SUSE|Oracle')
    )
  } |
  Select-Object `
    @{Name='Name';Expression={$_.Name}}, `
    @{Name='PowerState';Expression={$_.PowerState}}, `
    @{Name='OS';Expression={ if ($_.Guest.OSFullName) { $_.Guest.OSFullName } else { $_.ExtensionData.Guest.GuestFullName } }}, `
    @{Name='GuestId';Expression={ $_.ExtensionData.Guest.GuestId }}, `
    @{Name='IP';Expression={ ($_.Guest.IPAddress -join ', ') }} |
  Export-Csv -Path .\linux_vms.csv -NoTypeInformation -Encoding UTF8
