#!/usr/bin/env bash
# =============================================================================
# create_newboot_partition.sh
#
# Creates a new 3G XFS partition on /dev/sda (next available slot),
# formats it as XFS, mounts it at /newboot, and adds it to /etc/fstab.
#
# Designed for RHEL 8 / RHEL 9 systems.
#
# Usage:
#   chmod +x create_newboot_partition.sh
#   sudo ./create_newboot_partition.sh [--dry-run]
#
# Options:
#   --dry-run   Show what would be done without making any changes
# =============================================================================

set -euo pipefail

# ── Constants ────────────────────────────────────────────────────────────────
DISK="/dev/sda"
MOUNT_POINT="/newboot"
FS_TYPE="xfs"
PART_SIZE_MB=3000          # 3 GB in MB (parted works in MB here)
PART_SIZE_MIN_MB=3000      # minimum free space required

# ── Color output ─────────────────────────────────────────────────────────────
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

# ── Must run as root ──────────────────────────────────────────────────────────
[[ $EUID -ne 0 ]] && die "This script must be run as root (sudo)."

$DRY_RUN && warn "DRY-RUN mode — no changes will be made.\n"

# =============================================================================
# STEP 1: Install parted and xfsprogs if missing
# =============================================================================
step "Checking required packages"

PKGS_TO_INSTALL=()

if ! command -v parted &>/dev/null; then
    warn "parted not found — will install."
    PKGS_TO_INSTALL+=("parted")
else
    ok "parted is already installed: $(parted --version | head -1)"
fi

if ! command -v mkfs.xfs &>/dev/null; then
    warn "mkfs.xfs not found — will install xfsprogs."
    PKGS_TO_INSTALL+=("xfsprogs")
else
    ok "mkfs.xfs is already installed."
fi

if [[ ${#PKGS_TO_INSTALL[@]} -gt 0 ]]; then
    info "Installing: ${PKGS_TO_INSTALL[*]}"
    run "dnf install -y ${PKGS_TO_INSTALL[*]}"
fi

# =============================================================================
# STEP 2: Validate disk exists
# =============================================================================
step "Validating disk $DISK"

[[ -b "$DISK" ]] || die "Block device $DISK not found."
ok "$DISK exists."

# =============================================================================
# STEP 3: Parse current partition layout with parted
# =============================================================================
step "Reading partition table on $DISK"

# parted -m gives machine-readable colon-delimited output:
# BYT;
# /dev/sda:447.1GB:scsi:512:512:gpt:...:;
# 1:1049kB:211MB:210MB:fat16::boot,esp;
# 2:211MB:2361MB:2150MB:ext4::;

PARTED_OUT=$(parted -m -s "$DISK" unit MB print 2>/dev/null) \
    || die "Failed to read partition table from $DISK."

info "Current layout:"
parted -s "$DISK" unit MB print || true
echo

# ── Detect partition table type (GPT or MSDOS/MBR) ───────────────────────────
DISK_LINE=$(echo "$PARTED_OUT" | grep "^${DISK}:")
PTABLE_TYPE=$(echo "$DISK_LINE" | cut -d: -f6)
DISK_SIZE_MB=$(echo "$DISK_LINE" | cut -d: -f2 | tr -d 'MB')
# Strip units — parted prints "447137MB" style
DISK_SIZE_MB=$(echo "$DISK_SIZE_MB" | sed 's/[^0-9.]//g' | cut -d. -f1)

info "Partition table type : $PTABLE_TYPE"
info "Disk total size      : ${DISK_SIZE_MB} MB"

# ── Find END of last real partition ──────────────────────────────────────────
# Lines that start with a digit are partition lines; skip "free" pseudo entries
LAST_PART_LINE=$(echo "$PARTED_OUT" \
    | grep -E '^[0-9]+:' \
    | tail -1)

if [[ -z "$LAST_PART_LINE" ]]; then
    die "No existing partitions found on $DISK. Nothing to place 'next' partition after."
fi

# Field layout: num:start:end:size:fstype:name:flags;
LAST_PART_NUM=$(echo "$LAST_PART_LINE" | cut -d: -f1)
LAST_PART_END=$(echo "$LAST_PART_LINE" | cut -d: -f3 | sed 's/[^0-9.]//g' | cut -d. -f1)

info "Last partition       : ${DISK}${LAST_PART_NUM}"
info "Last partition end   : ${LAST_PART_END} MB"

# ── Calculate free space ──────────────────────────────────────────────────────
FREE_MB=$(( DISK_SIZE_MB - LAST_PART_END ))
info "Unpartitioned space  : ${FREE_MB} MB"

if (( FREE_MB < PART_SIZE_MIN_MB )); then
    die "Not enough free space on $DISK. Need ${PART_SIZE_MIN_MB} MB, only ${FREE_MB} MB available. Add a new disk."
fi

ok "Sufficient free space available (${FREE_MB} MB ≥ ${PART_SIZE_MIN_MB} MB)."

# ── Calculate new partition boundaries ───────────────────────────────────────
# Start right after last partition end; parted will align to optimal boundary.
NEW_PART_START_MB=$(( LAST_PART_END + 1 ))
NEW_PART_END_MB=$(( NEW_PART_START_MB + PART_SIZE_MB ))

# Safety: don't exceed disk
if (( NEW_PART_END_MB > DISK_SIZE_MB )); then
    NEW_PART_END_MB=$(( DISK_SIZE_MB - 1 ))
fi

info "New partition start  : ${NEW_PART_START_MB} MB"
info "New partition end    : ${NEW_PART_END_MB} MB"

# =============================================================================
# STEP 4: Check /newboot is not already mounted
# =============================================================================
step "Pre-flight checks"

if mountpoint -q "$MOUNT_POINT" 2>/dev/null; then
    die "$MOUNT_POINT is already mounted. Aborting to avoid data loss."
fi

if grep -q "$MOUNT_POINT" /etc/fstab 2>/dev/null; then
    die "$MOUNT_POINT already exists in /etc/fstab. Aborting."
fi

ok "No existing $MOUNT_POINT mount detected."

# =============================================================================
# STEP 5: MBR-specific check — max 4 primary partitions
# =============================================================================
if [[ "$PTABLE_TYPE" == "msdos" ]]; then
    PRIMARY_COUNT=$(echo "$PARTED_OUT" | grep -cE '^[0-9]+:' || true)
    if (( PRIMARY_COUNT >= 4 )); then
        die "MBR disk already has ${PRIMARY_COUNT} partitions (max 4 primary). Cannot add more without an extended partition. Consider converting to GPT."
    fi
fi

# =============================================================================
# STEP 6: Create the partition
# =============================================================================
step "Creating new partition on $DISK"

if [[ "$PTABLE_TYPE" == "gpt" ]]; then
    # GPT: use a partition name instead of primary/logical
    info "GPT disk — using partition name 'newboot'"
    run "parted -s \"$DISK\" mkpart newboot ${FS_TYPE} ${NEW_PART_START_MB}MB ${NEW_PART_END_MB}MB"
else
    # MBR/msdos: use "primary"
    info "MBR disk — creating primary partition"
    run "parted -s \"$DISK\" mkpart primary ${FS_TYPE} ${NEW_PART_START_MB}MB ${NEW_PART_END_MB}MB"
fi

# ── Inform the kernel about the new partition table ───────────────────────────
if ! $DRY_RUN; then
    info "Notifying kernel of partition table change..."
    partprobe "$DISK" 2>/dev/null || true
    udevadm settle
    sleep 2
fi

# =============================================================================
# STEP 7: Identify the new partition device name
# =============================================================================
step "Identifying new partition device"

# lsblk lists partitions in order; last child of $DISK is the new one.
# Works for both /dev/sda → sda4 and /dev/nvme0n1 → nvme0n1p4
if ! $DRY_RUN; then
    NEW_PART=$(lsblk -pno NAME "$DISK" | grep -v "^${DISK}$" | tail -1)
    [[ -b "$NEW_PART" ]] || die "New partition device not found after partprobe. Check: lsblk $DISK"
    ok "New partition device : $NEW_PART"
else
    # In dry-run, predict partition name
    if echo "$DISK" | grep -q "nvme"; then
        NEW_PART="${DISK}p$(( LAST_PART_NUM + 1 ))"
    else
        NEW_PART="${DISK}$(( LAST_PART_NUM + 1 ))"
    fi
    info "[DRY-RUN] Predicted new partition: $NEW_PART"
fi

# =============================================================================
# STEP 8: Format the partition as XFS
# =============================================================================
step "Formatting $NEW_PART as XFS"

run "mkfs.xfs -f -L newboot \"$NEW_PART\""

# ── Get UUID for fstab ────────────────────────────────────────────────────────
if ! $DRY_RUN; then
    # Give udev a moment to register the new filesystem UUID
    udevadm settle
    PART_UUID=$(blkid -s UUID -o value "$NEW_PART")
    [[ -n "$PART_UUID" ]] || die "Could not retrieve UUID for $NEW_PART."
    ok "XFS UUID: $PART_UUID"
else
    PART_UUID="XXXXXXXX-XXXX-XXXX-XXXX-XXXXXXXXXXXX"
    info "[DRY-RUN] UUID will be assigned after mkfs.xfs"
fi

# =============================================================================
# STEP 9: Create mount point and mount
# =============================================================================
step "Mounting $NEW_PART at $MOUNT_POINT"

run "mkdir -p \"$MOUNT_POINT\""
run "mount -t xfs \"$NEW_PART\" \"$MOUNT_POINT\""

if ! $DRY_RUN; then
    mountpoint -q "$MOUNT_POINT" \
        && ok "$MOUNT_POINT mounted successfully." \
        || die "Mount failed for $NEW_PART at $MOUNT_POINT."
fi

# =============================================================================
# STEP 10: Add to /etc/fstab (UUID-based, persistent across reboots)
# =============================================================================
step "Adding entry to /etc/fstab"

FSTAB_COMMENT="# /newboot — added by create_newboot_partition.sh"
FSTAB_ENTRY="UUID=${PART_UUID}  ${MOUNT_POINT}  ${FS_TYPE}  defaults  0  0"

if ! $DRY_RUN; then
    # Backup fstab before touching it
    cp /etc/fstab /etc/fstab.bak.$(date +%Y%m%d%H%M%S)
    echo "" >> /etc/fstab
    echo "$FSTAB_COMMENT" >> /etc/fstab
    echo "$FSTAB_ENTRY"   >> /etc/fstab
    ok "/etc/fstab updated."
    info "fstab line: $FSTAB_ENTRY"
else
    echo -e "${YLW}[DRY-RUN]${NC} Would append to /etc/fstab:"
    echo "  $FSTAB_COMMENT"
    echo "  $FSTAB_ENTRY"
fi

# ── Verify fstab is valid (RHEL 8+ has findmnt --verify) ─────────────────────
if ! $DRY_RUN && command -v findmnt &>/dev/null; then
    findmnt --verify --verbose 2>&1 | grep -v "^$" || true
fi

# =============================================================================
# STEP 11: Summary
# =============================================================================
step "Summary"

if ! $DRY_RUN; then
    echo
    df -hT "$MOUNT_POINT"
    echo
    lsblk "$DISK"
    echo
    ok "Done. New 3G XFS partition created and mounted at $MOUNT_POINT."
    info "Partition : $NEW_PART"
    info "UUID      : $PART_UUID"
    info "Mount     : $MOUNT_POINT"
    info "fstab     : backed up + updated"
    echo
    info "Next step: copy /boot contents here, update /etc/fstab /boot line, reboot to verify."
else
    echo
    ok "[DRY-RUN] No changes made. Re-run without --dry-run to apply."
    info "Would have created : ${NEW_PART} (predicted)"
    info "Would have mounted : $MOUNT_POINT"
    info "Partition size     : ${PART_SIZE_MB} MB"
    info "Start / End        : ${NEW_PART_START_MB} MB / ${NEW_PART_END_MB} MB"
fi
