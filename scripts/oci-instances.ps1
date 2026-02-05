# OCI Instance Report - Simple Script
# Edit these variables:
$PROFILE = "DEFAULT"                                     # Your OCI profile name
$CONFIG_FILE = "$env:USERPROFILE\.oci\config"          # Path to config file
$AUTH_TYPE = "api_key"                                   # api_key or security_token
$COMPARTMENT_ID = ""                                     # Compartment OCID (empty = all compartments)

# Build common OCI parameters
$OCI_PARAMS = "--profile $PROFILE --config-file `"$CONFIG_FILE`""
if ($AUTH_TYPE -ne "api_key") {
    $OCI_PARAMS += " --auth $AUTH_TYPE"
}

Write-Host "`nFetching OCI Instances...`n" -ForegroundColor Cyan

# Get all compartments
$compartments = (Invoke-Expression "oci iam compartment list --all --compartment-id-in-subtree true $OCI_PARAMS" | ConvertFrom-Json).data | Where-Object { $_.'lifecycle-state' -eq 'ACTIVE' }

# If specific compartment set, use only that
if ($COMPARTMENT_ID) {
    $compartments = $compartments | Where-Object { $_.id -eq $COMPARTMENT_ID }
}

$report = @()

foreach ($comp in $compartments) {
    $instances = (Invoke-Expression "oci compute instance list --compartment-id $($comp.id) --all $OCI_PARAMS" | ConvertFrom-Json).data
    
    foreach ($inst in $instances) {
        # Get IP addresses
        $vnics = (Invoke-Expression "oci compute instance list-vnics --instance-id $($inst.id) --all $OCI_PARAMS" | ConvertFrom-Json).data
        $vnic = $vnics | Where-Object { $_.'is-primary' -eq $true } | Select-Object -First 1
        
        # Get OS info
        $imageId = if ($inst.'source-details'.'image-id') { $inst.'source-details'.'image-id' } else { $inst.'image-id' }
        $image = (Invoke-Expression "oci compute image get --image-id $imageId $OCI_PARAMS 2>$null" | ConvertFrom-Json).data
        
        $report += [PSCustomObject]@{
            'Instance Name' = $inst.'display-name'
            'State'         = $inst.'lifecycle-state'
            'Public IP'     = if ($vnic.'public-ip') { $vnic.'public-ip' } else { "None" }
            'Private IP'    = $vnic.'private-ip'
            'OS'            = "$($image.'operating-system') $($image.'operating-system-version')"
            'Compartment'   = $comp.name
        }
    }
}

# Display
$report | Format-Table -AutoSize

# Export
$report | Export-Csv -Path "OCI-Instances.csv" -NoTypeInformation
Write-Host "`nExported to: OCI-Instances.csv" -ForegroundColor Green
