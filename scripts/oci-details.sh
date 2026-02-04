# Step 1: Get instance details to find the image-id
$instance = oci compute instance get --instance-id $INSTANCE_ID | ConvertFrom-Json

# Step 2: Get the image details
$IMAGE_ID = $instance.data.'image-id'

oci compute image get `
  --image-id $IMAGE_ID `
  --query "data.{OS:`"operating-system`",Version:`"operating-system-version`",Name:`"display-name`"}" `
  --output table


  
