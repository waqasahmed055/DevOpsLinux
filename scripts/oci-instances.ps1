# OCI Instance Report
$PROFILE = "DEFAULT"
$CONFIG_FILE = "$env:USERPROFILE\.oci\config"
$AUTH_TYPE = "security_token"
$COMPARTMENT_ID = "ocid1.compartment.oc1..aaaaaaaant6nhu65dwfoecobudeid5gqby4fv3vwiqvhus27r432oc7k5v6q"

Write-Host "Getting instances from compartment..." -ForegroundColor Cyan

# Get instances
$instances = (oci compute instance list --compartment-id $COMPARTMENT_ID --all --profile $PROFILE --config-file "$CONFIG_FILE" --auth $AUTH_TYPE | ConvertFrom-Json).data

Write-Host "Found $($instances.Count) instances. Getting details..." -ForegroundColor Green

$report = @()

foreach ($inst in $instances) {
    Write-Host "Processing: $($inst.'display-name')" -ForegroundColor Yellow
    
    # Get IPs
    $vnics = (oci compute instance list-vnics --instance-id $inst.id --all --profile $PROFILE --config-file "$CONFIG_FILE" --auth $AUTH_TYPE | ConvertFrom-Json).data
    $vnic = $vnics | Where-Object { $_.'is-primary' -eq $true } | Select-Object -First 1
    
    # Get OS
    $imageId = if ($inst.'source-details'.'image-id') { $inst.'source-details'.'image-id' } else { $inst.'image-id' }
    $image = (oci compute image get --image-id $imageId --profile $PROFILE --config-file "$CONFIG_FILE" --auth $AUTH_TYPE | ConvertFrom-Json).data
    
    $report += [PSCustomObject]@{
        'Name'       = $inst.'display-name'
        'State'      = $inst.'lifecycle-state'
        'Public IP'  = if ($vnic.'public-ip') { $vnic.'public-ip' } else { "None" }
        'Private IP' = $vnic.'private-ip'
        'OS'         = "$($image.'operating-system') $($image.'operating-system-version')"
    }
}

$report | Format-Table -AutoSize
$report | Export-Csv -Path "OCI-Instances.csv" -NoTypeInformation
Write-Host "`nDone! Exported to OCI-Instances.csv" -ForegroundColor Green
