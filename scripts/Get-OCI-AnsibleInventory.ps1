# ============================================================
#  Get-OCI-AnsibleInventory.ps1
#  Connects to OCI via CLI, discovers all RUNNING Linux
#  instances across all compartments, and writes a clean
#  Ansible INI inventory grouped by compartment.
# ============================================================

# ── USER CONFIG ─────────────────────────────────────────────
$OCI_CONFIG_FILE = "C:\Users\rayto\.oci\config"
$OCI_PROFILE     = "ray"
$OCI_AUTH        = "security_token"
$OUTPUT_FILE     = ".\ansible_inventory.ini"
$ANSIBLE_USER    = "opc"          # default OCI Linux SSH user
$ANSIBLE_KEY     = "~/.ssh/id_rsa"  # path to your SSH private key (optional)
# ────────────────────────────────────────────────────────────

# Helper: run an OCI CLI command and return parsed JSON
function Invoke-OCI {
    param([string[]]$Args)
    $baseArgs = @(
        "--config-file", $OCI_CONFIG_FILE,
        "--profile",     $OCI_PROFILE,
        "--auth",        $OCI_AUTH
    )
    $allArgs = $Args + $baseArgs
    $raw = oci @allArgs 2>$null
    if (-not $raw) { return $null }
    try { return ($raw | ConvertFrom-Json) } catch { return $null }
}

# ── STEP 1: Read tenancy OCID from config file ───────────────
Write-Host "`n[1/5] Reading tenancy OCID from OCI config..." -ForegroundColor Cyan

$tenancyOcid = $null
$configLines = Get-Content $OCI_CONFIG_FILE -ErrorAction Stop
$inProfile = $false
foreach ($line in $configLines) {
    if ($line -match "^\[${OCI_PROFILE}\]") { $inProfile = $true; continue }
    if ($inProfile -and $line -match "^\[") { break }
    if ($inProfile -and $line -match "^tenancy\s*=\s*(.+)") {
        $tenancyOcid = $matches[1].Trim()
        break
    }
}

if (-not $tenancyOcid) {
    Write-Error "Could not find tenancy OCID for profile [$OCI_PROFILE] in $OCI_CONFIG_FILE"
    exit 1
}
Write-Host "  Tenancy: $tenancyOcid" -ForegroundColor Gray

# ── STEP 2: List ALL active compartments ────────────────────
Write-Host "[2/5] Discovering compartments..." -ForegroundColor Cyan

$compResult = Invoke-OCI @(
    "iam", "compartment", "list",
    "--compartment-id",           $tenancyOcid,
    "--compartment-id-in-subtree","true",
    "--all",
    "--query", "data[?`"lifecycle-state`"=='ACTIVE'].{id:id,name:name}"
)

# Build compartment list: include root tenancy + all sub-compartments
$compartments = @()
$compartments += [PSCustomObject]@{ id = $tenancyOcid; name = "root" }
if ($compResult -and $compResult.data) {
    foreach ($c in $compResult.data) {
        $compartments += [PSCustomObject]@{ id = $c.id; name = $c.name }
    }
} elseif ($compResult) {
    foreach ($c in $compResult) {
        $compartments += [PSCustomObject]@{ id = $c.id; name = $c.name }
    }
}
Write-Host "  Found $($compartments.Count) compartment(s)" -ForegroundColor Gray

# ── STEP 3: Collect all RUNNING instances ───────────────────
Write-Host "[3/5] Scanning instances in each compartment..." -ForegroundColor Cyan

# Cache image OS lookups so we don't hit the API repeatedly
$imageOsCache = @{}

function Get-ImageOS {
    param([string]$ImageId)
    if (-not $ImageId) { return "Unknown" }
    if ($imageOsCache.ContainsKey($ImageId)) { return $imageOsCache[$ImageId] }

    $img = Invoke-OCI @("compute", "image", "get", "--image-id", $ImageId)
    $os  = "Unknown"
    if ($img -and $img.data) {
        $os = $img.data."operating-system"
    }
    $imageOsCache[$ImageId] = $os
    return $os
}

# Map: compartmentName → list of { name, privateIp }
$inventory = [ordered]@{}

foreach ($comp in $compartments) {
    $instResult = Invoke-OCI @(
        "compute", "instance", "list",
        "--compartment-id", $comp.id,
        "--lifecycle-state", "RUNNING",
        "--all"
    )

    $instances = @()
    if ($instResult -and $instResult.data) { $instances = $instResult.data }
    elseif ($instResult)                   { $instances = $instResult }

    if ($instances.Count -eq 0) { continue }

    Write-Host "  [$($comp.name)] — $($instances.Count) running instance(s)" -ForegroundColor Gray

    foreach ($inst in $instances) {
        $instId    = $inst.id
        $instName  = $inst."display-name"
        $imageId   = $inst."source-details"."image-id"

        # ── OS filter: skip Windows ──────────────────────────
        $os = Get-ImageOS -ImageId $imageId
        if ($os -match "Windows") {
            Write-Host "    SKIP (Windows): $instName" -ForegroundColor DarkGray
            continue
        }

        # ── Get primary VNIC → private IP ───────────────────
        $vnicAttachResult = Invoke-OCI @(
            "compute", "vnic-attachment", "list",
            "--compartment-id", $comp.id,
            "--instance-id",    $instId,
            "--all"
        )

        $vnicAttachs = @()
        if ($vnicAttachResult -and $vnicAttachResult.data) { $vnicAttachs = $vnicAttachResult.data }
        elseif ($vnicAttachResult)                         { $vnicAttachs = $vnicAttachResult }

        # Primary VNIC has nic-index = 0
        $primaryVnic = $vnicAttachs | Where-Object { $_."nic-index" -eq 0 } | Select-Object -First 1
        if (-not $primaryVnic) { $primaryVnic = $vnicAttachs | Select-Object -First 1 }

        $privateIp = $null
        if ($primaryVnic) {
            $vnicResult = Invoke-OCI @(
                "network", "vnic", "get",
                "--vnic-id", $primaryVnic."vnic-id"
            )
            if ($vnicResult -and $vnicResult.data) {
                $privateIp = $vnicResult.data."private-ip"
            }
        }

        if (-not $privateIp) {
            Write-Host "    WARN: No private IP found for $instName — skipping" -ForegroundColor Yellow
            continue
        }

        Write-Host "    + $instName  →  $privateIp  [$os]" -ForegroundColor Green

        # Sanitize compartment name for Ansible group name
        $groupName = $comp.name -replace '[^a-zA-Z0-9_]', '_'

        if (-not $inventory.Contains($groupName)) {
            $inventory[$groupName] = @()
        }
        $inventory[$groupName] += [PSCustomObject]@{
            Name      = $instName
            PrivateIp = $privateIp
            OS        = $os
        }
    }
}

# ── STEP 4: Build Ansible inventory ─────────────────────────
Write-Host "[4/5] Building Ansible inventory..." -ForegroundColor Cyan

$lines = @()
$lines += "# ============================================================"
$lines += "#  Ansible Inventory — Generated by Get-OCI-AnsibleInventory.ps1"
$lines += "#  Date   : $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
$lines += "#  Profile: $OCI_PROFILE"
$lines += "#  Auth   : $OCI_AUTH"
$lines += "# ============================================================"
$lines += ""

$allHosts = @()

foreach ($group in $inventory.Keys) {
    $hosts = $inventory[$group]
    $lines += "[$group]"
    foreach ($h in $hosts) {
        # Sanitize hostname for Ansible (no spaces, lowercase)
        $hostAlias = ($h.Name -replace '\s+', '_').ToLower()
        $lines += "$hostAlias ansible_host=$($h.PrivateIp)"
        $allHosts += $hostAlias
    }
    $lines += ""
}

# [all:children] block — every group listed
$lines += "[all:children]"
foreach ($group in $inventory.Keys) {
    $lines += $group
}
$lines += ""

# [all:vars] — shared SSH vars
$lines += "[all:vars]"
$lines += "ansible_user=$ANSIBLE_USER"
$lines += "ansible_ssh_private_key_file=$ANSIBLE_KEY"
$lines += "ansible_ssh_common_args='-o StrictHostKeyChecking=no'"
$lines += ""

# ── STEP 5: Write file ───────────────────────────────────────
Write-Host "[5/5] Writing inventory to: $OUTPUT_FILE" -ForegroundColor Cyan

$lines | Set-Content -Path $OUTPUT_FILE -Encoding UTF8

Write-Host "`n✅ Done! Inventory saved to $OUTPUT_FILE" -ForegroundColor Green
Write-Host "   Total Linux hosts : $($allHosts.Count)" -ForegroundColor White
Write-Host "   Groups (compartments): $($inventory.Keys.Count)" -ForegroundColor White
Write-Host ""
Write-Host "   Test with:" -ForegroundColor Yellow
Write-Host "   ansible all -i $OUTPUT_FILE -m ping" -ForegroundColor Yellow
Write-Host ""
