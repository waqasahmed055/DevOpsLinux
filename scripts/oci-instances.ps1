
Write-Host "`nFetching OCI Instances...`n" -ForegroundColor Cyan

# Get all compartments
if ($AUTH_TYPE -eq "api_key") {
    $compartments = (oci iam compartment list --all --compartment-id-in-subtree true --profile $PROFILE --config-file "$CONFIG_FILE" | ConvertFrom-Json).data | Where-Object { $_.'lifecycle-state' -eq 'ACTIVE' }
} else {
    $compartments = (oci iam compartment list --all --compartment-id-in-subtree true --profile $PROFILE --config-file "$CONFIG_FILE" --auth $AUTH_TYPE | ConvertFrom-Json).data | Where-Object { $_.'lifecycle-state' -eq 'ACTIVE' }
}

# If specific compartment set, use only that
if ($COMPARTMENT_ID) {
    $compartments = $compartments | Where-Object { $_.id -eq $COMPARTMENT_ID }
}

$report = @()

foreach ($comp in $compartments) {
    # Get instances
    if ($AUTH_TYPE -eq "api_key") {
        $instances = (oci compute instance list --compartment-id $comp.id --all --profile $PROFILE --config-file "$CONFIG_FILE" | ConvertFrom-Json).data
    } else {
        $instances = (oci compute instance list --compartment-id $comp.id --all --profile $PROFILE --config-file "$CONFIG_FILE" --auth $AUTH_TYPE | ConvertFrom-Json).data
    }
    
    foreach ($inst in $instances) {
        # Get IP addresses
        if ($AUTH_TYPE -eq "api_key") {
            $vnics = (oci compute instance list-vnics --instance-id $inst.id --all --profile $PROFILE --config-file "$CONFIG_FILE" | ConvertFrom-Json).data
        } else {
            $vnics = (oci compute instance list-vnics --instance-id $inst.id --all --profile $PROFILE --config-file "$CONFIG_FILE" --auth $AUTH_TYPE | ConvertFrom-Json).data
        }
        $vnic = $vnics | Where-Object { $_.'is-primary' -eq $true } | Select-Object -First 1
        
        # Get OS info
        $imageId = if ($inst.'source-details'.'image-id') { $inst.'source-details'.'image-id' } else { $inst.'image-id' }
        
        try {
            if ($AUTH_TYPE -eq "api_key") {
                $image = (oci compute image get --image-id $imageId --profile $PROFILE --config-file "$CONFIG_FILE" 2>&1 | ConvertFrom-Json).data
            } else {
                $image = (oci compute image get --image-id $imageId --profile $PROFILE --config-file "$CONFIG_FILE" --auth $AUTH_TYPE 2>&1 | ConvertFrom-Json).data
            }
        } catch {
            $image = $null
        }
        
        $report += [PSCustomObject]@{
            'Instance Name' = $inst.'display-name'
            'State'         = $inst.'lifecycle-state'
            'Public IP'     = if ($vnic.'public-ip') { $vnic.'public-ip' } else { "None" }
            'Private IP'    = $vnic.'private-ip'
            'OS'            = if ($image) { "$($image.'operating-system') $($image.'operating-system-version')" } else { "Unknown" }
            'Compartment'   = $comp.name
        }
    }
}

# Display
$report | Format-Table -AutoSize

# Export
$report | Export-Csv -Path "OCI-Instances.csv" -NoTypeInformation
Write-Host "`nExported to: OCI-Instances.csv" -ForegroundColor Green
