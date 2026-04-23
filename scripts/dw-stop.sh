#!/bin/bash
# =============================================================================
# DegreeWorks - Stop Services & Patch
# Run as: su - dwadmin, then: sudo bash dw_stop_and_patch.sh
# =============================================================================

set -euo pipefail

BASE_DIR="/degreeworks"
LOG_FILE="/var/log/dw_patch_$(date +%Y%m%d_%H%M%S).log"
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

DW_STOP_COMMANDS=("tbestop" "resstop" "webstop" "dapstop")

# How long to wait after stop script before checking / killing (seconds)
GRACEFUL_TIMEOUT=30
# How long to wait after SIGTERM before escalating to SIGKILL (seconds)
SIGTERM_TIMEOUT=15

# ─────────────────────────────────────────────
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

die() {
    log "ERROR: $*"
    log "Aborted. Review log: $LOG_FILE"
    exit 1
}

# ─────────────────────────────────────────────
check_user() {
    if [[ "$(whoami)" != "$DW_USER" && "$(whoami)" != "root" ]]; then
        die "Must run as $DW_USER or root. Current user: $(whoami)"
    fi
}

# kill_service_procs <label> <pgrep_pattern>
# 1. Tries SIGTERM and waits SIGTERM_TIMEOUT seconds
# 2. If still alive, escalates to SIGKILL
kill_service_procs() {
    local label="$1"
    local pattern="$2"

    local pids
    pids=$(pgrep -u "$DW_USER" -f "$pattern" 2>/dev/null || true)
    [[ -z "$pids" ]] && return 0   # nothing to kill

    log "  → Sending SIGTERM to stuck $label processes: $pids"
    kill -TERM $pids 2>/dev/null || true

    # Wait up to SIGTERM_TIMEOUT for graceful exit
    local waited=0
    while [[ $waited -lt $SIGTERM_TIMEOUT ]]; do
        sleep 1
        (( waited++ ))
        pids=$(pgrep -u "$DW_USER" -f "$pattern" 2>/dev/null || true)
        [[ -z "$pids" ]] && { log "  ✓ $label exited cleanly after SIGTERM (${waited}s)"; return 0; }
    done

    # Still alive — force kill
    pids=$(pgrep -u "$DW_USER" -f "$pattern" 2>/dev/null || true)
    if [[ -n "$pids" ]]; then
        log "  ⚠ $label still alive after ${SIGTERM_TIMEOUT}s — sending SIGKILL to: $pids"
        kill -KILL $pids 2>/dev/null || true
        sleep 2
        pids=$(pgrep -u "$DW_USER" -f "$pattern" 2>/dev/null || true)
        if [[ -n "$pids" ]]; then
            log "  ✗ CRITICAL: $label could not be killed (PIDs: $pids) — manual intervention needed"
        else
            log "  ✓ $label killed via SIGKILL"
        fi
    fi
}

stop_jar_services() {
    log "=== STOPPING JAR SERVICES ==="
    for service in "${JAR_SERVICES[@]}"; do
        STOP_SCRIPT="$BASE_DIR/$service/stop_${service}.sh"

        if [[ -f "$STOP_SCRIPT" ]]; then
            log "Stopping: $service"
            bash "$STOP_SCRIPT" >> "$LOG_FILE" 2>&1 \
                && log "  ✓ $service stop script completed" \
                || log "  ⚠ $service stop script returned non-zero (may already be down)"
        else
            log "  ⚠ Script not found: $STOP_SCRIPT — will rely on process kill"
        fi

        # Wait for graceful shutdown
        log "  Waiting up to ${GRACEFUL_TIMEOUT}s for $service to exit..."
        local waited=0
        while [[ $waited -lt $GRACEFUL_TIMEOUT ]]; do
            sleep 2
            (( waited += 2 ))
            if ! pgrep -u "$DW_USER" -f "$service" > /dev/null 2>&1; then
                log "  ✓ $service exited cleanly (${waited}s)"
                break
            fi
        done

        # If still running after graceful wait — kill it
        if pgrep -u "$DW_USER" -f "$service" > /dev/null 2>&1; then
            log "  ⚠ $service still running after ${GRACEFUL_TIMEOUT}s — escalating"
            kill_service_procs "$service" "$service"
        fi

        sleep 1
    done
}

stop_dw_services() {
    log "=== STOPPING DW SYSTEM SERVICES ==="
    for svc in "${DW_STOP_COMMANDS[@]}"; do
        if command -v "$svc" &>/dev/null; then
            log "Running: $svc"
            "$svc" >> "$LOG_FILE" 2>&1 \
                && log "  ✓ $svc completed" \
                || log "  ⚠ $svc returned non-zero (may already be down)"
        else
            log "  ⚠ Command not found: $svc — skipping"
        fi
        sleep 2
    done

    # After all stop commands — sweep for any leftover DW system processes
    log "  Checking for leftover DW system processes..."
    kill_service_procs "dw-system" "tbe\|resstop\|webstop\|dapstop\|Tomcat\|jboss"
}

verify_all_down() {
    log "=== FINAL VERIFICATION — ALL PROCESSES ==="
    local remaining
    remaining=$(pgrep -u "$DW_USER" -a -f "degreeworks\|APIServices\|Composer\|Controller\|RespDashboard\|TransferEquiv\|TransitUI" 2>/dev/null || true)

    if [[ -n "$remaining" ]]; then
        log "  ⚠ Processes still alive after all stop attempts:"
        echo "$remaining" | tee -a "$LOG_FILE"
        log "  Attempting final SIGKILL sweep..."
        kill_service_procs "remaining-dw" "degreeworks\|APIServices\|Composer\|Controller\|RespDashboard\|TransferEquiv\|TransitUI"

        # Last check
        remaining=$(pgrep -u "$DW_USER" -a -f "degreeworks\|APIServices\|Composer\|Controller\|RespDashboard\|TransferEquiv\|TransitUI" 2>/dev/null || true)
        if [[ -n "$remaining" ]]; then
            log "  ✗ CRITICAL: Could not kill all processes. Manual intervention required:"
            echo "$remaining" | tee -a "$LOG_FILE"
            die "Unsafe to patch — processes still running"
        fi
    fi

    log "  ✓ All DegreeWorks processes are down — safe to patch"
}

run_patch() {
    log "=== RUNNING DNF UPDATE ==="
    dnf update -y >> "$LOG_FILE" 2>&1 \
        && log "  ✓ dnf update completed successfully" \
        || die "dnf update failed — check log: $LOG_FILE"
}

# ─────────────────────────────────────────────
# MAIN
# ─────────────────────────────────────────────
log "============================================================"
log " DegreeWorks Stop & Patch"
log " Host     : $(hostname)"
log " Log file : $LOG_FILE"
log "============================================================"

check_user

echo ""
echo "This script will:"
echo "  1. Stop all JAR services via their stop_*.sh scripts"
echo "  2. Stop DW system services (tbestop resstop webstop dapstop)"
echo "  3. Verify no processes remain"
echo "  4. Run: dnf update -y"
echo ""
read -rp "Proceed? (yes/no): " CONFIRM
[[ "$CONFIRM" == "yes" ]] || { log "Aborted by user."; exit 0; }

stop_jar_services
stop_dw_services
verify_all_down
run_patch

log "============================================================"
log " DONE. Server is patched and application is stopped."
log " Start services manually when ready."
log " Full log: $LOG_FILE"
log "============================================================"
