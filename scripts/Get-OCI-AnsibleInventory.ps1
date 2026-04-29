# ============================================================
#  Get-OCI-AnsibleInventory.ps1
#  Connects to OCI CLI, finds all RUNNING Linux instances
#  across every compartment, outputs a clean Ansible inventory.
# ============================================================

# ── USER CONFIG ─────────────────────────────────────────────
$OCI_CONFIG_FILE = "C:\Users\rayto\.oci\config"
$OCI_PROFILE     = "ray"
$OCI_AUTH        = "security_token"
$OUTPUT_FILE     = ".\ansible_inventory.ini"
$ANSIBLE_USER    = "opc"
$ANSIBLE_KEY     = "~/.ssh/id_rsa"
# ────────────────────────────────────────────────────────────

# Helper: run OCI CLI and return parsed JSON object
function Invoke-OCI {
    param([string[]]$CmdArgs)
    $result = & oci @CmdArgs `
        --config-file $OCI_CONFIG_FILE `
        --profile     $OCI_PROFILE `
        --auth        $OCI_AUTH 2>$null
    if (-not $result) { return $null }
    try   { return ($result | ConvertFrom-Json) }
    catch { return $null }
}

# ── STEP 1: Read tenancy OCID from config ───────────────────
Write-Host ""
Write-Host "[1/5] Reading tenancy OCID from config..." -ForegroundColor Cyan

$tenancyOcid = $null
$inProfile   = $false
foreach ($line in (Get-Content $OCI_CONFIG_FILE)) {
    if ($line -match "^\[${OCI_PROFILE}\]") { $inProfile = $true; continue }
    if ($inProfile -and $line -match "^\[") { break }
    if ($inProfile -and $line -match "^tenancy\s*=\s*(.+)") {
        $tenancyOcid = $Matches[1].Trim()
        break
    }
}

if (-not $tenancyOcid) {
    Write-Error "Cannot find tenancy OCID for profile [$OCI_PROFILE] in $OCI_CONFIG_FILE"
    exit 1
}
Write-Host "  Tenancy: $tenancyOcid" -ForegroundColor DarkGray

# ── STEP 2: List all ACTIVE compartments ────────────────────
Write-Host "[2/5] Listing compartments..." -ForegroundColor Cyan

$compQuery = 'data[?"lifecycle-state"==''ACTIVE''].{id:id,name:name}'

$compJson = Invoke-OCI @(
    "iam", "compartment", "list",
    "--compartment-id",            $tenancyOcid,
    "--compartment-id-in-subtree", "true",
    "--all",
    "--query", $compQuery
)

$compartments = [System.Collections.Generic.List[PSObject]]::new()
$compartments.Add([PSCustomObject]@{ id = $tenancyOcid; name = "root" })

if ($compJson) {
    $raw = if ($compJson.PSObject.Properties["data"]) { $compJson.data } else { $compJson }
    foreach ($c in $raw) {
        $compartments.Add([PSCustomObject]@{ id = $c.id; name = $c.name })
    }
}
Write-Host "  Found $($compartments.Count) compartment(s)" -ForegroundColor DarkGray

# ── STEP 3: Walk compartments, collect Linux instances ───────
Write-Host "[3/5] Scanning instances (skipping Windows)..." -ForegroundColor Cyan

$imageOsCache = @{}

function Get-ImageOS {
    param([string]$ImageId)
    if (-not $ImageId) { return "Unknown" }
    if ($script:imageOsCache.ContainsKey($ImageId)) { return $script:imageOsCache[$ImageId] }
    $r  = Invoke-OCI @("compute", "image", "get", "--image-id", $ImageId)
    $os = "Unknown"
    if ($r -and $r.data) { $os = $r.data."operating-system" }
    $script:imageOsCache[$ImageId] = $os
    return $os
}

$inventory = [ordered]@{}

foreach ($comp in $compartments) {

    $instJson = Invoke-OCI @(
        "compute", "instance", "list",
        "--compartment-id",  $comp.id,
        "--lifecycle-state", "RUNNING",
        "--all"
    )

    $instances = @()
    if ($instJson) {
        $instances = if ($instJson.PSObject.Properties["data"]) { $instJson.data } else { $instJson }
    }
    if (-not $instances -or $instances.Count -eq 0) { continue }

    Write-Host "  [$($comp.name)] $($instances.Count) running instance(s)" -ForegroundColor DarkGray

    foreach ($inst in $instances) {

        $instId   = $inst.id
        $instName = $inst."display-name"
        $imageId  = $inst."source-details"."image-id"

        # Skip Windows
        $os = Get-ImageOS -ImageId $imageId
        if ($os -match "Windows") {
            Write-Host "    SKIP Windows: $instName" -ForegroundColor DarkGray
            continue
        }

        # Get primary VNIC private IP
        $vnicJson = Invoke-OCI @(
            "compute", "vnic-attachment", "list",
            "--compartment-id", $comp.id,
            "--instance-id",    $instId,
            "--all"
        )

        $attachments = @()
        if ($vnicJson) {
            $attachments = if ($vnicJson.PSObject.Properties["data"]) { $vnicJson.data } else { $vnicJson }
        }

        $primary = $attachments | Where-Object { $_."nic-index" -eq 0 } | Select-Object -First 1
        if (-not $primary) { $primary = $attachments | Select-Object -First 1 }

        $privateIp = $null
        if ($primary) {
            $vnicDetail = Invoke-OCI @("network", "vnic", "get", "--vnic-id", $primary."vnic-id")
            if ($vnicDetail -and $vnicDetail.data) {
                $privateIp = $vnicDetail.data."private-ip"
            }
        }

        if (-not $privateIp) {
            Write-Host "    WARN no IP found: $instName" -ForegroundColor Yellow
            continue
        }

        Write-Host "    + $instName  ->  $privateIp  [$os]" -ForegroundColor Green

        $group = $comp.name -replace '[^a-zA-Z0-9_]', '_'
        if (-not $inventory.Contains($group)) { $inventory[$group] = @() }
        $inventory[$group] += [PSCustomObject]@{
            Name      = $instName
            PrivateIp = $privateIp
            OS        = $os
        }
    }
}

# ── STEP 4: Render Ansible INI inventory ─────────────────────
Write-Host "[4/5] Building inventory..." -ForegroundColor Cyan

$sb = [System.Text.StringBuilder]::new()

[void]$sb.AppendLine("# ============================================================")
[void]$sb.AppendLine("#  Ansible Inventory - OCI Linux Hosts")
[void]$sb.AppendLine("#  Generated : $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')")
[void]$sb.AppendLine("#  Profile   : $OCI_PROFILE  |  Auth: $OCI_AUTH")
[void]$sb.AppendLine("# ============================================================")
[void]$sb.AppendLine("")

$totalHosts = 0
foreach ($group in $inventory.Keys) {
    [void]$sb.AppendLine("[$group]")
    foreach ($h in $inventory[$group]) {
        $alias = ($h.Name -replace '\s+', '_').ToLower()
        [void]$sb.AppendLine("$alias ansible_host=$($h.PrivateIp)")
        $totalHosts++
    }
    [void]$sb.AppendLine("")
}

[void]$sb.AppendLine("[all:children]")
foreach ($group in $inventory.Keys) { [void]$sb.AppendLine($group) }
[void]$sb.AppendLine("")

[void]$sb.AppendLine("[all:vars]")
[void]$sb.AppendLine("ansible_user=$ANSIBLE_USER")
[void]$sb.AppendLine("ansible_ssh_private_key_file=$ANSIBLE_KEY")
[void]$sb.AppendLine("ansible_ssh_common_args=-o StrictHostKeyChecking=no")
[void]$sb.AppendLine("")

# ── STEP 5: Write file ────────────────────────────────────────
Write-Host "[5/5] Writing $OUTPUT_FILE ..." -ForegroundColor Cyan

$outPath = (Join-Path (Get-Location).Path (Split-Path $OUTPUT_FILE -Leaf))
[System.IO.File]::WriteAllText($outPath, $sb.ToString(), [System.Text.Encoding]::UTF8)

Write-Host ""
Write-Host "Done!  ->  $outPath" -ForegroundColor Green
Write-Host "  Linux hosts : $totalHosts"           -ForegroundColor White
Write-Host "  Groups      : $($inventory.Keys.Count)" -ForegroundColor White
Write-Host ""
Write-Host "Test with:" -ForegroundColor Yellow
Write-Host "  ansible all -i $OUTPUT_FILE -m ping" -ForegroundColor Yellow
Write-Host ""
