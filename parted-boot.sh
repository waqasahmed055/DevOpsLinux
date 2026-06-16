#!/usr/bin/env bash
# =============================================================================
# create_newboot_partition.sh
#
# Creates a new 3 GiB XFS partition on /dev/sda (next available slot),
# formats it as XFS, mounts it at /newboot, copies /boot contents into it,
# and adds it to /etc/fstab.
#
# Designed for RHEL 8 / RHEL 9 systems.
#
# Usage:
#   sudo ./create_newboot_partition.sh [--dry-run]
# =============================================================================

set -euo pipefail

# ── Constants ────────────────────────────────────────────────────────────────
DISK="/dev/sda"
MOUNT_POINT="/newboot"
FS_TYPE="xfs"
PART_SIZE_MB=3000          # 3 GiB in MiB
PART_SIZE_MIN_MB=3000

# ── Colors ──────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GRN='\033[0;32m'
YLW='\033[1;33m'
BLU='\033[0;34m'
NC='\033[0m'

info()  { echo -e "${BLU}[INFO]${NC}  $*"; }
ok()    { echo -e "${GRN}[OK]${NC}    $*"; }
warn()  { echo -e "${YLW}[WARN]${NC}  $*"; }
die()   { echo -e "${RED}[ERROR]${NC} $*" >&2; exit 1; }
step()  { echo -e "\n${YLW}──── $* ────${NC}"; }

# ── Dry-run flag ─────────────────────────────────────────────────────────────
DRY_RUN=false
for arg in "$@"; do
    [[ "$arg" == "--dry-run" ]] && DRY_RUN=true
done

run() {
    if $DRY_RUN; then
        echo -e "${YLW}[DRY-RUN]${NC} $*"
    else
        eval "$@"
    fi
}

# ── Must be root ─────────────────────────────────────────────────────────────
[[ $EUID -ne 0 ]] && die "This script must be run as root (sudo)."

$DRY_RUN && warn "DRY-RUN mode — no changes will be made.\n"

# =============================================================================
# 1. Install required packages
# =============================================================================
step "Checking required packages"

PKGS_TO_INSTALL=()

if ! command -v parted &>/dev/null; then
    warn "parted not found — will install."
    PKGS_TO_INSTALL+=("parted")
else
    ok "parted is installed: $(parted --version | head -1)"
fi

if ! command -v mkfs.xfs &>/dev/null; then
    warn "mkfs.xfs not found — will install xfsprogs."
    PKGS_TO_INSTALL+=("xfsprogs")
else
    ok "mkfs.xfs is installed."
fi

if [[ ${#PKGS_TO_INSTALL[@]} -gt 0 ]]; then
    info "Installing: ${PKGS_TO_INSTALL[*]}"
    run "dnf install -y ${PKGS_TO_INSTALL[*]}"
fi

# =============================================================================
# 2. Validate disk
# =============================================================================
step "Validating disk $DISK"
[[ -b "$DISK" ]] || die "Block device $DISK not found."
ok "$DISK exists."

# =============================================================================
# 3. Read partition table with parted machine‑readable output
# =============================================================================
step "Reading partition table on $DISK"

PARTED_OUT=$(parted -m -s "$DISK" unit MiB print 2>/dev/null) \
    || die "Failed to read partition table from $DISK."

info "Current layout:"
parted -s "$DISK" unit MiB print || true
echo

# ── Extract disk info ───────────────────────────────────────────────────────
DISK_LINE=$(echo "$PARTED_OUT" | grep "^${DISK}:")
PTABLE_TYPE=$(echo "$DISK_LINE" | cut -d: -f6)
DISK_SIZE_MB=$(echo "$DISK_LINE" | cut -d: -f2 | tr -d 'MiB' | sed 's/[^0-9]//g')

info "Partition table type : $PTABLE_TYPE"
info "Disk total size      : ${DISK_SIZE_MB} MiB"

# ── Find the last partition (ignore "free" lines) ──────────────────────────
LAST_PART_LINE=$(echo "$PARTED_OUT" \
    | grep -E '^[0-9]+:' \
    | tail -1)

if [[ -z "$LAST_PART_LINE" ]]; then
    die "No existing partitions found on $DISK."
fi

LAST_PART_NUM=$(echo "$LAST_PART_LINE" | cut -d: -f1)
LAST_PART_END=$(echo "$LAST_PART_LINE" | cut -d: -f3 | sed 's/[^0-9]//g')

info "Last partition       : ${DISK}${LAST_PART_NUM}"
info "Last partition end   : ${LAST_PART_END} MiB"

# ── Calculate free space ──────────────────────────────────────────────────
FREE_MB=$(( DISK_SIZE_MB - LAST_PART_END ))
info "Unpartitioned space  : ${FREE_MB} MiB"

if (( FREE_MB < PART_SIZE_MIN_MB )); then
    die "Not enough free space. Need ${PART_SIZE_MIN_MB} MiB, have ${FREE_MB} MiB."
fi
ok "Sufficient free space (${FREE_MB} MiB ≥ ${PART_SIZE_MIN_MB} MiB)."

# ── Determine next partition number and boundaries ─────────────────────────
NEXT_PART_NUM=$(( LAST_PART_NUM + 1 ))
NEW_START_MB=$(( LAST_PART_END + 1 ))
NEW_END_MB=$(( NEW_START_MB + PART_SIZE_MB ))

# Ensure we don't exceed disk
if (( NEW_END_MB > DISK_SIZE_MB )); then
    NEW_END_MB=$(( DISK_SIZE_MB - 1 ))
fi

# ── Predict device name ──────────────────────────────────────────────────
if echo "$DISK" | grep -q "nvme"; then
    NEW_PART="${DISK}p${NEXT_PART_NUM}"
else
    NEW_PART="${DISK}${NEXT_PART_NUM}"
fi

info "New partition number : $NEXT_PART_NUM"
info "New partition device : $NEW_PART"
info "Start / End (MiB)    : $NEW_START_MB / $NEW_END_MB"

# =============================================================================
# 4. Pre-flight checks
# =============================================================================
step "Pre-flight checks"

if mountpoint -q "$MOUNT_POINT" 2>/dev/null; then
    die "$MOUNT_POINT is already mounted."
fi

if grep -q "$MOUNT_POINT" /etc/fstab 2>/dev/null; then
    die "$MOUNT_POINT already exists in /etc/fstab."
fi

if [[ -b "$NEW_PART" ]]; then
    die "Device $NEW_PART already exists. Aborting to prevent overwriting data."
fi

ok "No existing $MOUNT_POINT mount or fstab entry found; device $NEW_PART is free."

# ── MBR primary partition limit ─────────────────────────────────────────────
if [[ "$PTABLE_TYPE" == "msdos" ]]; then
    PRIMARY_COUNT=$(echo "$PARTED_OUT" | grep -cE '^[0-9]+:' || true)
    if (( PRIMARY_COUNT >= 4 )); then
        die "MBR disk already has 4 primary partitions. Cannot add another without extended partition."
    fi
    PART_TYPE="primary"
else
    PART_TYPE="primary"   # For GPT, 'primary' is acceptable; it becomes a label
fi

# =============================================================================
# 5. Create partition
# =============================================================================
step "Creating partition on $DISK"

if ! $DRY_RUN; then
    # Use MiB units, align automatically
    parted -s "$DISK" mkpart "$PART_TYPE" "$FS_TYPE" "${NEW_START_MB}MiB" "${NEW_END_MB}MiB" \
        || die "Failed to create partition with parted."

    # Inform kernel and wait for device
    info "Notifying kernel of partition table changes..."
    partprobe "$DISK" 2>/dev/null || true
    udevadm settle

    # Wait for the new partition device to appear (max 10 seconds)
    for i in {1..10}; do
        if [[ -b "$NEW_PART" ]]; then
            ok "New partition device $NEW_PART appeared."
            break
        fi
        sleep 1
    done

    if [[ ! -b "$NEW_PART" ]]; then
        die "Device $NEW_PART did not appear after partprobe. Check kernel messages."
    fi
else
    info "[DRY-RUN] Would create partition: $NEW_PART (${NEW_START_MB}MiB – ${NEW_END_MB}MiB)"
fi

# =============================================================================
# 6. Format as XFS
# =============================================================================
step "Formatting $NEW_PART as XFS"
run "mkfs.xfs -f -L newboot \"$NEW_PART\""

# ── Retrieve UUID ──────────────────────────────────────────────────────────
if ! $DRY_RUN; then
    udevadm settle
    PART_UUID=$(blkid -s UUID -o value "$NEW_PART")
    [[ -n "$PART_UUID" ]] || die "Could not retrieve UUID for $NEW_PART."
    ok "XFS UUID: $PART_UUID"
else
    PART_UUID="XXXXXXXX-XXXX-XXXX-XXXX-XXXXXXXXXXXX"
    info "[DRY-RUN] UUID will be assigned after mkfs.xfs"
fi

# =============================================================================
# 7. Mount and copy /boot contents
# =============================================================================
step "Mounting $NEW_PART at $MOUNT_POINT"

run "mkdir -p \"$MOUNT_POINT\""
run "mount -t xfs \"$NEW_PART\" \"$MOUNT_POINT\""

if ! $DRY_RUN; then
    mountpoint -q "$MOUNT_POINT" \
        && ok "$MOUNT_POINT mounted successfully." \
        || die "Mount failed for $NEW_PART at $MOUNT_POINT."
fi

# ── Copy /boot contents into the new partition ──────────────────────────────
step "Copying /boot contents to $MOUNT_POINT"
run "cp -arv /boot/. \"$MOUNT_POINT/\""

if ! $DRY_RUN; then
    # Quick check: list some files to confirm
    info "Contents of $MOUNT_POINT:"
    ls -la "$MOUNT_POINT" | head -10
    ok "Copy completed. All /boot files are now on the new partition."
else
    info "[DRY-RUN] Would copy /boot/. to $MOUNT_POINT/"
fi

# =============================================================================
# 8. Add to /etc/fstab (for /newboot) – optional, you can comment out
# =============================================================================
step "Adding entry to /etc/fstab for $MOUNT_POINT"
FSTAB_COMMENT="# /newboot — added by create_newboot_partition.sh"
FSTAB_ENTRY="UUID=${PART_UUID}  ${MOUNT_POINT}  ${FS_TYPE}  defaults  0  0"

if ! $DRY_RUN; then
    cp /etc/fstab /etc/fstab.bak.$(date +%Y%m%d%H%M%S)
    {
        echo ""
        echo "$FSTAB_COMMENT"
        echo "$FSTAB_ENTRY"
    } >> /etc/fstab
    ok "/etc/fstab updated with /newboot entry."
    info "fstab line: $FSTAB_ENTRY"
else
    echo -e "${YLW}[DRY-RUN]${NC} Would append to /etc/fstab:"
    echo "  $FSTAB_COMMENT"
    echo "  $FSTAB_ENTRY"
fi

# ── Verify fstab syntax (optional) ────────────────────────────────────────
if ! $DRY_RUN && command -v findmnt &>/dev/null; then
    findmnt --verify --verbose 2>&1 | grep -v "^$" || true
fi

# =============================================================================
# 9. Summary
# =============================================================================
step "Summary"

if ! $DRY_RUN; then
    echo
    df -hT "$MOUNT_POINT"
    echo
    lsblk "$DISK"
    echo
    ok "Done. New 3 GiB XFS partition created and mounted at $MOUNT_POINT."
    info "Partition : $NEW_PART"
    info "UUID      : $PART_UUID"
    info "Mount     : $MOUNT_POINT"
    info "fstab     : backed up and updated with $MOUNT_POINT entry."
    echo
    info "Next steps (manual):"
    info "  1. Update /etc/fstab to change /boot mount to UUID=$PART_UUID"
    info "  2. Reboot and verify that /boot uses the new larger partition"
    info "  3. After reboot, you can remove the old /boot partition if no longer needed"
else
    echo
    ok "[DRY-RUN] No changes were made."
    info "Would have created : $NEW_PART"
    info "Would have mounted : $MOUNT_POINT"
    info "Would have copied  : /boot to $MOUNT_POINT"
    info "Partition size     : ${PART_SIZE_MB} MiB"
fi
