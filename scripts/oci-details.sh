# Step 1: Get instance details to find the image-id
$instance = oci compute instance get --instance-id $INSTANCE_ID | ConvertFrom-Json

# Step 2: Get the image details
$IMAGE_ID = $instance.data.'image-id'

oci compute image get `
  --image-id $IMAGE_ID `
  --query "data.{OS:`"operating-system`",Version:`"operating-system-version`",Name:`"display-name`"}" `
  --output table

#Powershell script
```
# Set your compartment ID
$COMPARTMENT_ID = "ocid1.compartment.oc1..aaaaaaaa..."

# Get all instances
$instances = oci compute instance list --compartment-id $COMPARTMENT_ID | ConvertFrom-Json

# Loop through each instance
foreach ($instance in $instances.data) {
    $instanceId = $instance.id
    $instanceName = $instance.'display-name'
    $instanceState = $instance.'lifecycle-state'
    $imageId = $instance.'image-id'
    
    # Get IP addresses
    $vnics = oci compute instance list-vnics --instance-id $instanceId | ConvertFrom-Json
    $publicIp = $vnics.data[0].'public-ip'
    $privateIp = $vnics.data[0].'private-ip'
    
    # Get OS information
    $image = oci compute image get --image-id $imageId | ConvertFrom-Json
    $os = $image.data.'operating-system'
    $osVersion = $image.data.'operating-system-version'
    
    # Display information
    Write-Host "Instance: $instanceName"
    Write-Host "  State: $instanceState"
    Write-Host "  Public IP: $publicIp"
    Write-Host "  Private IP: $privateIp"
    Write-Host "  OS: $os $osVersion"
    Write-Host "------------------------"
}
```


  
