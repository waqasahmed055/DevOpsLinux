# ============================================================
#  Get-OCI-AnsibleInventory.ps1
#  Discovers all RUNNING Linux instances across all OCI
#  compartments and outputs a clean Ansible INI inventory.
# ============================================================

# ── USER CONFIG ─────────────────────────────────────────────
$OCI_CONFIG_FILE = "C:\Users\rayto\.oci\config"
$OCI_PROFILE     = "ray"
$OCI_AUTH        = "security_token"
$OUTPUT_FILE     = ".\ansible_inventory.ini"
$ANSIBLE_USER    = "opc"
$ANSIBLE_KEY     = "~/.ssh/id_rsa"
$DEBUG           = $true    # set $false to silence raw-output lines
# ────────────────────────────────────────────────────────────

function Write-Debug-Line([string]$msg) {
    if ($DEBUG) { Write-Host "  [DBG] $msg" -ForegroundColor DarkGray }
}

# ── Core OCI runner ──────────────────────────────────────────
# Runs OCI CLI, captures stdout+stderr, returns parsed object or $null.
# Never silently discards errors — prints them so you can diagnose.
function Invoke-OCI {
    param([string[]]$CmdArgs)

    # Build full argument list
    $allArgs = $CmdArgs + @(
        "--config-file", $OCI_CONFIG_FILE,
        "--profile",     $OCI_PROFILE,
        "--auth",        $OCI_AUTH,
        "--no-retry"
    )

    Write-Debug-Line "oci $($allArgs -join ' ')"

    # 2>&1 merges stderr into the output stream so we can inspect it
    $raw = & oci @allArgs 2>&1

    # Separate real stdout lines from error records
    $outLines = $raw | Where-Object { $_ -isnot [System.Management.Automation.ErrorRecord] }
    $errLines = $raw | Where-Object { $_ -is  [System.Management.Automation.ErrorRecord] }

    if ($errLines) {
        Write-Host "  [OCI ERR] $($errLines -join ' | ')" -ForegroundColor Red
    }

    if (-not $outLines) { return $null }

    $jsonStr = ($outLines -join "`n").Trim()
    if ([string]::IsNullOrEmpty($jsonStr)) { return $null }

    try {
        # -Depth 20 prevents truncation on deep objects (PS 7+)
        return $jsonStr | ConvertFrom-Json -Depth 20 -ErrorAction Stop
    } catch {
        # PS 5.1 doesn't support -Depth; fall back
        try   { return $jsonStr | ConvertFrom-Json -ErrorAction Stop }
        catch { Write-Host "  [PARSE ERR] $_" -ForegroundColor Red; return $null }
    }
}

# Helper: safely extract the .data array from an OCI response
function Get-OCIData([object]$resp) {
    if ($null -eq $resp) { return @() }
    # Response wrapped in {"data":[...]}
    if ($resp.PSObject.Properties.Name -contains "data") {
        $d = $resp.data
        if ($null -eq $d) { return @() }
        # Single object returned (e.g. image get) → wrap in array
        if ($d -is [System.Management.Automation.PSCustomObject]) { return @($d) }
        return $d
    }
    # Response is a bare array (rare, but handle it)
    if ($resp -is [System.Array]) { return $resp }
    return @($resp)
}

# ── STEP 1: Read tenancy OCID from config ───────────────────
Write-Host ""
Write-Host "[1/5] Reading tenancy OCID from $OCI_CONFIG_FILE" -ForegroundColor Cyan

$tenancyOcid = $null
$inProfile   = $false

foreach ($line in (Get-Content $OCI_CONFIG_FILE -ErrorAction Stop)) {
    $trimmed = $line.Trim()
    if ($trimmed -eq "[$OCI_PROFILE]")     { $inProfile = $true;  continue }
    if ($inProfile -and $trimmed -match "^\[") { break }
    if ($inProfile -and $trimmed -match "^tenancy\s*=\s*(.+)") {
        $tenancyOcid = $Matches[1].Trim()
        break
    }
}

if (-not $tenancyOcid) {
    Write-Error "Could not find 'tenancy' in [$OCI_PROFILE] section of $OCI_CONFIG_FILE"
    exit 1
}
Write-Host "  Tenancy OCID: $tenancyOcid" -ForegroundColor White

# ── STEP 2: Verify connectivity ──────────────────────────────
Write-Host "[2/5] Testing OCI connectivity..." -ForegroundColor Cyan

$testResp = Invoke-OCI @("iam", "compartment", "get", "--compartment-id", $tenancyOcid)
if ($null -eq $testResp) {
    Write-Host ""
    Write-Host "  ERROR: Could not connect to OCI. Check:" -ForegroundColor Red
    Write-Host "    1. Is your security_token still valid? Run: oci session authenticate --profile $OCI_PROFILE" -ForegroundColor Yellow
    Write-Host "    2. Is the tenancy OCID correct in $OCI_CONFIG_FILE ?" -ForegroundColor Yellow
    Write-Host "    3. Run manually: oci iam compartment get --compartment-id $tenancyOcid --config-file $OCI_CONFIG_FILE --profile $OCI_PROFILE --auth $OCI_AUTH" -ForegroundColor Yellow
    exit 1
}
Write-Host "  Connection OK" -ForegroundColor Green

# ── STEP 3: List all active compartments ────────────────────
Write-Host "[3/5] Listing compartments..." -ForegroundColor Cyan

$compResp = Invoke-OCI @(
    "iam", "compartment", "list",
    "--compartment-id",            $tenancyOcid,
    "--compartment-id-in-subtree", "true",
    "--all"
)

$compartments = [System.Collections.Generic.List[PSObject]]::new()
# Always include the root tenancy itself
$compartments.Add([PSCustomObject]@{ id = $tenancyOcid; name = "root" })

foreach ($c in (Get-OCIData $compResp)) {
    # Only ACTIVE compartments
    if ($c."lifecycle-state" -eq "ACTIVE") {
        $compartments.Add([PSCustomObject]@{
            id   = $c.id
            name = $c.name
        })
    }
}

Write-Host "  Found $($compartments.Count) compartment(s)" -ForegroundColor White

# ── Image OS cache ───────────────────────────────────────────
$imageOsCache = @{}

function Get-ImageOS([string]$ImageId) {
    if ([string]::IsNullOrEmpty($ImageId)) { return $null }
    if ($script:imageOsCache.ContainsKey($ImageId)) {
        return $script:imageOsCache[$ImageId]
    }
    $r   = Invoke-OCI @("compute", "image", "get", "--image-id", $ImageId)
    $arr = Get-OCIData $r
    $os  = if ($arr.Count -gt 0) { $arr[0]."operating-system" } else { $null }
    $script:imageOsCache[$ImageId] = $os
    return $os
}

# ── Windows detection ────────────────────────────────────────
# Returns $true if we are confident this is a Windows instance
function Test-IsWindows([object]$inst) {
    $name = $inst."display-name"

    # 1. Obvious Windows name patterns
    if ($name -match "(?i)windows|win\d+|winsvr|win-server") { return $true }

    # 2. source-type = "image" → look up OS from the image
    $srcType = $inst."source-details"."source-type"
    $imageId  = $inst."source-details"."image-id"

    if ($srcType -eq "image" -and -not [string]::IsNullOrEmpty($imageId)) {
        $os = Get-ImageOS -ImageId $imageId
        Write-Debug-Line "Image OS for $name : $os"
        if ($null -ne $os -and $os -match "(?i)windows") { return $true }
    }
    # source-type = "bootVolume" → can't look up OS; assume Linux (safest default)
    return $false
}

# ── STEP 4: Scan instances ───────────────────────────────────
Write-Host "[4/5] Scanning instances across compartments..." -ForegroundColor Cyan

$inventory   = [ordered]@{}
$skippedWin  = 0
$skippedNoIP = 0

foreach ($comp in $compartments) {

    Write-Host "  Compartment: $($comp.name)" -ForegroundColor DarkCyan

    $instResp = Invoke-OCI @(
        "compute", "instance", "list",
        "--compartment-id",  $comp.id,
        "--lifecycle-state", "RUNNING",
        "--all"
    )

    $instances = Get-OCIData $instResp
    if ($instances.Count -eq 0) {
        Write-Debug-Line "No running instances in $($comp.name)"
        continue
    }

    Write-Host "    $($instances.Count) RUNNING instance(s) found" -ForegroundColor DarkGray

    foreach ($inst in $instances) {
        $instId   = $inst.id
        $instName = $inst."display-name"

        Write-Host "    Checking: $instName" -ForegroundColor DarkGray

        # ── Windows filter ───────────────────────────────────
        if (Test-IsWindows -inst $inst) {
            Write-Host "      SKIP (Windows): $instName" -ForegroundColor DarkGray
            $skippedWin++
            continue
        }

        # ── Get private IP via instance list-vnics ───────────
        # This is ONE call instead of two (vnic-attachment + vnic get)
        $vnicResp = Invoke-OCI @(
            "compute", "instance", "list-vnics",
            "--instance-id", $instId
        )

        $vnics     = Get-OCIData $vnicResp
        # Primary VNIC has is-primary = true; fall back to first entry
        $primary   = $vnics | Where-Object { $_."is-primary" -eq $true } | Select-Object -First 1
        if (-not $primary) { $primary = $vnics | Select-Object -First 1 }

        $privateIp = $null
        if ($primary) { $privateIp = $primary."private-ip" }

        if ([string]::IsNullOrEmpty($privateIp)) {
            Write-Host "      WARN: No private IP found for $instName — skipped" -ForegroundColor Yellow
            $skippedNoIP++
            continue
        }

        # Detect OS label for inventory comment
        $osLabel = "Linux"
        $imageId = $inst."source-details"."image-id"
        if (-not [string]::IsNullOrEmpty($imageId)) {
            $os = Get-ImageOS -ImageId $imageId
            if ($os) { $osLabel = $os }
        }

        Write-Host "      + $instName  ->  $privateIp  [$osLabel]" -ForegroundColor Green

        # Ansible group name: compartment name, sanitised
        $group = $comp.name -replace '[^a-zA-Z0-9_]', '_'
        if (-not $inventory.Contains($group)) { $inventory[$group] = @() }
        $inventory[$group] += [PSCustomObject]@{
            Name      = $instName
            PrivateIp = $privateIp
            OS        = $osLabel
        }
    }
}

# ── STEP 5: Write Ansible inventory ─────────────────────────
Write-Host "[5/5] Writing inventory to $OUTPUT_FILE ..." -ForegroundColor Cyan

$sb = [System.Text.StringBuilder]::new()

[void]$sb.AppendLine("# ============================================================")
[void]$sb.AppendLine("#  Ansible Inventory - OCI Linux Hosts")
[void]$sb.AppendLine("#  Generated : $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')")
[void]$sb.AppendLine("#  Profile   : $OCI_PROFILE  |  Auth: $OCI_AUTH")
[void]$sb.AppendLine("# ============================================================")
[void]$sb.AppendLine("")

$totalHosts = 0

if ($inventory.Keys.Count -eq 0) {
    [void]$sb.AppendLine("# No Linux hosts found.")
} else {
    foreach ($group in $inventory.Keys) {
        [void]$sb.AppendLine("[$group]")
        foreach ($h in $inventory[$group]) {
            $alias = ($h.Name -replace '[^a-zA-Z0-9_\-\.]', '_').ToLower()
            [void]$sb.AppendLine("$alias ansible_host=$($h.PrivateIp)  # $($h.OS)")
            $totalHosts++
        }
        [void]$sb.AppendLine("")
    }

    [void]$sb.AppendLine("[all:children]")
    foreach ($group in $inventory.Keys) { [void]$sb.AppendLine($group) }
    [void]$sb.AppendLine("")
}

[void]$sb.AppendLine("[all:vars]")
[void]$sb.AppendLine("ansible_user=$ANSIBLE_USER")
[void]$sb.AppendLine("ansible_ssh_private_key_file=$ANSIBLE_KEY")
[void]$sb.AppendLine("ansible_ssh_common_args=-o StrictHostKeyChecking=no")
[void]$sb.AppendLine("")

# Resolve to absolute path so Resolve-Path doesn't fail on non-existent files
$outDir  = (Get-Location).Path
$outName = Split-Path $OUTPUT_FILE -Leaf
$outPath = Join-Path $outDir $outName
[System.IO.File]::WriteAllText($outPath, $sb.ToString(), [System.Text.Encoding]::UTF8)

# ── Summary ──────────────────────────────────────────────────
Write-Host ""
Write-Host "======================================" -ForegroundColor Cyan
Write-Host "  Inventory written to: $outPath"      -ForegroundColor White
Write-Host "  Linux hosts found  : $totalHosts"    -ForegroundColor Green
Write-Host "  Windows skipped    : $skippedWin"    -ForegroundColor DarkGray
Write-Host "  No-IP skipped      : $skippedNoIP"   -ForegroundColor DarkGray
Write-Host "======================================" -ForegroundColor Cyan
Write-Host ""

if ($totalHosts -eq 0) {
    Write-Host "  HINT: 0 hosts found. Possible reasons:" -ForegroundColor Yellow
    Write-Host "    - No RUNNING compute instances in any compartment" -ForegroundColor Yellow
    Write-Host "    - Instances exist but are in STOPPED/TERMINATED state" -ForegroundColor Yellow
    Write-Host "    - Your profile lacks IAM read permissions on compute/network" -ForegroundColor Yellow
    Write-Host "    - Check [DBG] lines above for OCI CLI errors" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  Quick manual test:" -ForegroundColor Yellow
    Write-Host "    oci compute instance list --compartment-id $tenancyOcid --all --config-file $OCI_CONFIG_FILE --profile $OCI_PROFILE --auth $OCI_AUTH" -ForegroundColor DarkYellow
} else {
    Write-Host "  Test with:" -ForegroundColor Yellow
    Write-Host "    ansible all -i $OUTPUT_FILE -m ping" -ForegroundColor Yellow
}
Write-Host ""
