# ==============================================================
# Get-OCI-AnsibleInventory.ps1
# Finds all RUNNING Linux instances across OCI compartments
# and writes a clean Ansible INI inventory file.
# ==============================================================

# ---------- USER CONFIG ----------
$OCI_CONFIG_FILE = "C:\Users\rayto\.oci\config"
$OCI_PROFILE     = "ray"
$OCI_AUTH        = "security_token"
$OUTPUT_FILE     = ".\ansible_inventory.ini"
$ANSIBLE_USER    = "opc"
$ANSIBLE_KEY     = "~/.ssh/id_rsa"
$DEBUG_MODE      = $true
# ---------------------------------

function dbg([string]$msg) {
    if ($DEBUG_MODE) {
        Write-Host "    [DBG] $msg" -ForegroundColor DarkGray
    }
}

function Invoke-OCI([string[]]$args) {
    $fullArgs = $args + @(
        "--config-file", $OCI_CONFIG_FILE,
        "--profile",     $OCI_PROFILE,
        "--auth",        $OCI_AUTH,
        "--no-retry"
    )
    dbg "oci $($fullArgs -join ' ')"
    $output = & oci @fullArgs 2>&1
    $stdout = @($output | Where-Object { $_ -isnot [System.Management.Automation.ErrorRecord] })
    $stderr = @($output | Where-Object { $_ -is  [System.Management.Automation.ErrorRecord] })
    if ($stderr.Count -gt 0) {
        Write-Host "    [OCI-ERR] $($stderr -join ' ')" -ForegroundColor Red
    }
    if ($stdout.Count -eq 0) { return $null }
    $json = ($stdout -join "`n").Trim()
    if ($json -eq "") { return $null }
    try {
        return ($json | ConvertFrom-Json)
    } catch {
        Write-Host "    [PARSE-ERR] $_" -ForegroundColor Red
        return $null
    }
}

function Get-Data([object]$resp) {
    if ($null -eq $resp) { return @() }
    if ($resp.PSObject.Properties.Name -contains "data") {
        if ($null -eq $resp.data) { return @() }
        if ($resp.data -is [System.Array]) { return $resp.data }
        return @($resp.data)
    }
    if ($resp -is [System.Array]) { return $resp }
    return @($resp)
}

$imageCache = @{}

function Get-ImageOS([string]$imageId) {
    if ([string]::IsNullOrEmpty($imageId)) { return $null }
    if ($imageCache.ContainsKey($imageId)) { return $imageCache[$imageId] }
    $r = Invoke-OCI @("compute", "image", "get", "--image-id", $imageId)
    $items = Get-Data $r
    $os = $null
    if ($items.Count -gt 0) {
        $os = $items[0]."operating-system"
    }
    $imageCache[$imageId] = $os
    return $os
}

function IsWindows([object]$inst) {
    $name = $inst."display-name"
    if ($name -match "(?i)windows|win2k|winsvr") { return $true }
    $srcType = $inst."source-details"."source-type"
    $imgId   = $inst."source-details"."image-id"
    if ($srcType -eq "image" -and -not [string]::IsNullOrEmpty($imgId)) {
        $os = Get-ImageOS $imgId
        dbg "OS for $name = $os"
        if ($os -match "(?i)windows") { return $true }
    }
    return $false
}

# ==========================================================
Write-Host ""
Write-Host "[1/5] Reading tenancy OCID from config..." -ForegroundColor Cyan

$tenancyOcid = $null
$inSection   = $false

foreach ($line in (Get-Content $OCI_CONFIG_FILE)) {
    $t = $line.Trim()
    if ($t -eq "[$OCI_PROFILE]") {
        $inSection = $true
        continue
    }
    if ($inSection -and $t.StartsWith("[")) {
        break
    }
    if ($inSection -and $t -match "^tenancy\s*=\s*(.+)") {
        $tenancyOcid = $Matches[1].Trim()
        break
    }
}

if ([string]::IsNullOrEmpty($tenancyOcid)) {
    Write-Host "ERROR: tenancy not found for [$OCI_PROFILE] in $OCI_CONFIG_FILE" -ForegroundColor Red
    exit 1
}
Write-Host "  Tenancy: $tenancyOcid" -ForegroundColor White

# ==========================================================
Write-Host "[2/5] Testing OCI connectivity..." -ForegroundColor Cyan

$connTest = Invoke-OCI @("iam", "compartment", "get", "--compartment-id", $tenancyOcid)
if ($null -eq $connTest) {
    Write-Host ""
    Write-Host "FAILED to connect. Try these checks:" -ForegroundColor Red
    Write-Host "  1. Refresh token:  oci session authenticate --profile $OCI_PROFILE" -ForegroundColor Yellow
    Write-Host "  2. Manual test:    oci iam compartment get --compartment-id $tenancyOcid --config-file `"$OCI_CONFIG_FILE`" --profile $OCI_PROFILE --auth $OCI_AUTH" -ForegroundColor Yellow
    exit 1
}
Write-Host "  Connection OK" -ForegroundColor Green

# ==========================================================
Write-Host "[3/5] Listing compartments..." -ForegroundColor Cyan

$compResp = Invoke-OCI @(
    "iam", "compartment", "list",
    "--compartment-id",            $tenancyOcid,
    "--compartment-id-in-subtree", "true",
    "--all"
)

$compartments = New-Object System.Collections.Generic.List[PSObject]
$compartments.Add([PSCustomObject]@{ id = $tenancyOcid; name = "root" })

foreach ($c in (Get-Data $compResp)) {
    if ($c."lifecycle-state" -eq "ACTIVE") {
        $compartments.Add([PSCustomObject]@{ id = $c.id; name = $c.name })
    }
}

Write-Host "  Found $($compartments.Count) compartment(s)" -ForegroundColor White

# ==========================================================
Write-Host "[4/5] Scanning instances..." -ForegroundColor Cyan

$inventory   = [ordered]@{}
$winSkipped  = 0
$noipSkipped = 0

foreach ($comp in $compartments) {
    Write-Host "  -> $($comp.name)" -ForegroundColor DarkCyan

    $instResp = Invoke-OCI @(
        "compute", "instance", "list",
        "--compartment-id",  $comp.id,
        "--lifecycle-state", "RUNNING",
        "--all"
    )

    $instances = Get-Data $instResp
    if ($instances.Count -eq 0) {
        dbg "No RUNNING instances in $($comp.name)"
        continue
    }
    Write-Host "     $($instances.Count) RUNNING instance(s)" -ForegroundColor DarkGray

    foreach ($inst in $instances) {
        $instId   = $inst.id
        $instName = $inst."display-name"
        Write-Host "     Checking: $instName" -ForegroundColor DarkGray

        if (IsWindows $inst) {
            Write-Host "       SKIP Windows: $instName" -ForegroundColor DarkGray
            $winSkipped++
            continue
        }

        $vnicResp = Invoke-OCI @(
            "compute", "instance", "list-vnics",
            "--instance-id", $instId
        )

        $vnics     = Get-Data $vnicResp
        $primary   = @($vnics | Where-Object { $_."is-primary" -eq $true })[0]
        if ($null -eq $primary) { $primary = @($vnics)[0] }

        $privateIp = $null
        if ($null -ne $primary) {
            $privateIp = $primary."private-ip"
        }

        if ([string]::IsNullOrEmpty($privateIp)) {
            Write-Host "       WARN no private IP: $instName" -ForegroundColor Yellow
            $noipSkipped++
            continue
        }

        $osLabel = "Linux"
        $imgId   = $inst."source-details"."image-id"
        if (-not [string]::IsNullOrEmpty($imgId)) {
            $os = Get-ImageOS $imgId
            if ($os) { $osLabel = $os }
        }

        Write-Host "       + $instName -> $privateIp [$osLabel]" -ForegroundColor Green

        $group = ($comp.name -replace '[^a-zA-Z0-9_]', '_')
        if (-not $inventory.Contains($group)) {
            $inventory[$group] = New-Object System.Collections.Generic.List[PSObject]
        }
        $inventory[$group].Add([PSCustomObject]@{
            Name      = $instName
            PrivateIp = $privateIp
            OS        = $osLabel
        })
    }
}

# ==========================================================
Write-Host "[5/5] Writing inventory to $OUTPUT_FILE ..." -ForegroundColor Cyan

$sb = New-Object System.Text.StringBuilder

[void]$sb.AppendLine("# Ansible Inventory - OCI Linux Hosts")
[void]$sb.AppendLine("# Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')")
[void]$sb.AppendLine("# Profile  : $OCI_PROFILE")
[void]$sb.AppendLine("")

$totalHosts = 0

if ($inventory.Keys.Count -eq 0) {
    [void]$sb.AppendLine("# No Linux hosts found.")
} else {
    foreach ($group in $inventory.Keys) {
        [void]$sb.AppendLine("[$group]")
        foreach ($h in $inventory[$group]) {
            $alias = ($h.Name -replace '[^a-zA-Z0-9_\-\.]', '_').ToLower()
            [void]$sb.AppendLine("$alias  ansible_host=$($h.PrivateIp)  # $($h.OS)")
            $totalHosts++
        }
        [void]$sb.AppendLine("")
    }

    [void]$sb.AppendLine("[all:children]")
    foreach ($group in $inventory.Keys) {
        [void]$sb.AppendLine($group)
    }
    [void]$sb.AppendLine("")
}

[void]$sb.AppendLine("[all:vars]")
[void]$sb.AppendLine("ansible_user=$ANSIBLE_USER")
[void]$sb.AppendLine("ansible_ssh_private_key_file=$ANSIBLE_KEY")
[void]$sb.AppendLine("ansible_ssh_common_args=-o StrictHostKeyChecking=no")
[void]$sb.AppendLine("")

$outPath = Join-Path (Get-Location).Path (Split-Path $OUTPUT_FILE -Leaf)
[System.IO.File]::WriteAllText($outPath, $sb.ToString(), [System.Text.Encoding]::UTF8)

Write-Host ""
Write-Host "====================================" -ForegroundColor Cyan
Write-Host "  Output   : $outPath"               -ForegroundColor White
Write-Host "  Linux    : $totalHosts hosts"      -ForegroundColor Green
Write-Host "  Skipped  : $winSkipped Windows, $noipSkipped no-IP" -ForegroundColor DarkGray
Write-Host "====================================" -ForegroundColor Cyan
Write-Host ""

if ($totalHosts -gt 0) {
    Write-Host "Test: ansible all -i $OUTPUT_FILE -m ping" -ForegroundColor Yellow
} else {
    Write-Host "0 hosts found. Check [OCI-ERR] and [DBG] lines above." -ForegroundColor Yellow
    Write-Host "Manual check: oci compute instance list --compartment-id $tenancyOcid --lifecycle-state RUNNING --all --config-file `"$OCI_CONFIG_FILE`" --profile $OCI_PROFILE --auth $OCI_AUTH" -ForegroundColor DarkYellow
}
Write-Host ""
