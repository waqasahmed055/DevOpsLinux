Get-VM |
Where-Object {
    $_.PowerState -eq 'PoweredOn' -and
    $_.ExtensionData.Guest.GuestFamily -eq 'linuxGuest'
} |
Select-Object `
    @{Name='VMName'; Expression = { $_.Name }}, `
    @{Name='OS'; Expression = {
        if ($_.Guest.OSFullName -match 'Red Hat')     { ($_.Guest.OSFullName -replace 'Red Hat.*?(\d+(\.\d+)?)','$1'; "RedHat $($Matches[1])") }
        elseif ($_.Guest.OSFullName -match 'Ubuntu')  { ($_.Guest.OSFullName -replace 'Ubuntu ','') -replace ' LTS',''; "Ubuntu $($Matches[0])" }
        elseif ($_.Guest.OSFullName -match 'CentOS')  { ($_.Guest.OSFullName -replace 'CentOS ','') }
        elseif ($_.Guest.OSFullName -match 'Oracle')  { ($_.Guest.OSFullName -replace 'Oracle Linux ','Oracle ') }
        elseif ($_.Guest.OSFullName -match 'SUSE')    { ($_.Guest.OSFullName -replace 'SUSE Linux Enterprise ','SLES ') }
        else { $_.ExtensionData.Guest.GuestId }
    }}, `
    @{Name='IP'; Expression = {
        ($_.Guest.IPAddress |
            Where-Object { $_ -match '^\d{1,3}(\.\d{1,3}){3}$' }) -join ', '
    }}, `
    @{Name='PowerState'; Expression = { $_.PowerState }} |
Export-Csv -Path .\linux_vms_ipv4_short_os.csv -NoTypeInformation -Encoding UTF8
