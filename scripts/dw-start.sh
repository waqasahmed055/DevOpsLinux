#!/bin/bash
# =============================================================================
# DegreeWorks - Start Application Services
# Run as: su - dwadmin, then: sudo bash dw_start.sh
# =============================================================================

set -euo pipefail

BASE_DIR="/degreeworks"
LOG_FILE="/var/log/dw_start_$(date +%Y%m%d_%H%M%S).log"
DW_USER="dwadmin"

JAR_SERVICES=(
    "APIServices"
    "Composer"
    "Controller"
    "RespDashboard"
    "TransferEquiv"
    "TransferEquivAdmin"
    "TransitUI"
)

# Start order per documentation: dap → web → res → tbe
DW_START_COMMANDS=("dapstart" "webstart" "resstart" "tbestart")

# ─────────────────────────────────────────────
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

die() {
    log "ERROR: $*"
    log "Startup aborted. Review log: $LOG_FILE"
    exit 1
}

# ─────────────────────────────────────────────
check_user() {
    if [[ "$(whoami)" != "$DW_USER" && "$(whoami)" != "root" ]]; then
        die "Must run as $DW_USER or root. Current user: $(whoami)"
    fi
}

check_already_running() {
    log "=== PRE-START CHECK ==="
    if pgrep -u "$DW_USER" -f "degreeworks" > /dev/null 2>&1; then
        log "  ⚠ WARNING: DegreeWorks processes are already running:"
        pgrep -u "$DW_USER" -a -f "degreeworks" | tee -a "$LOG_FILE" || true
        read -rp "Services may already be up. Continue anyway? (yes/no): " confirm
        [[ "$confirm" == "yes" ]] || { log "Aborted by user."; exit 0; }
    else
        log "  ✓ No existing DegreeWorks processes — clean start"
    fi
}

start_dw_services() {
    log "=== STARTING DW SYSTEM SERVICES ==="
    for svc in "${DW_START_COMMANDS[@]}"; do
        if command -v "$svc" &>/dev/null; then
            log "Running: $svc"
            "$svc" >> "$LOG_FILE" 2>&1 \
                && log "  ✓ $svc completed" \
                || die "$svc failed — aborting to prevent partial startup"
        else
            log "  ⚠ Command not found: $svc — skipping"
        fi
        sleep 2
    done
}

start_jar_services() {
    log "=== STARTING JAR SERVICES ==="
    for service in "${JAR_SERVICES[@]}"; do
        START_SCRIPT="$BASE_DIR/$service/start_${service}.sh"
        if [[ -f "$START_SCRIPT" ]]; then
            log "Starting: $service"
            bash "$START_SCRIPT" >> "$LOG_FILE" 2>&1 \
                && log "  ✓ $service started" \
                || die "$service failed to start — aborting"
        else
            log "  ⚠ Script not found: $START_SCRIPT — skipping"
        fi
        sleep 1
    done
}

verify_running() {
    log "=== VERIFYING SERVICES ARE UP ==="
    RUNNING=$(pgrep -u "$DW_USER" -a -f "degreeworks" 2>/dev/null || true)
    if [[ -n "$RUNNING" ]]; then
        log "  ✓ The following DegreeWorks processes are running:"
        echo "$RUNNING" | tee -a "$LOG_FILE"
    else
        log "  ⚠ WARNING: No DegreeWorks processes detected after startup"
        log "  Check log for errors: $LOG_FILE"
    fi
}

# ─────────────────────────────────────────────
# MAIN
# ─────────────────────────────────────────────
log "============================================================"
log " DegreeWorks Application Startup"
log " Host     : $(hostname)"
log " Log file : $LOG_FILE"
log "============================================================"

check_user

echo ""
echo "This script will:"
echo "  1. Check no services are already running"
echo "  2. Start DW system services (dapstart webstart resstart tbestart)"
echo "  3. Start all JAR services via their start_*.sh scripts"
echo ""
read -rp "Proceed? (yes/no): " CONFIRM
[[ "$CONFIRM" == "yes" ]] || { log "Aborted by user."; exit 0; }

check_already_running
start_dw_services
start_jar_services
verify_running

log "============================================================"
log " DONE. DegreeWorks application is started."
log " Full log: $LOG_FILE"
log "============================================================"
