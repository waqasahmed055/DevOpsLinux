#!/usr/bin/env bash
# =========================================================
# Fully non-interactive password reset for ansible user
# =========================================================

set -euo pipefail

# ===================== VARIABLES =========================
ADMIN_USER="server-a"
ADMIN_PASS="AdminUserPasswordHere"

ANSIBLE_USER="ansible"
NEW_PASS="abc@123"

SERVERS=(
  "10.50.54.9"
  "10.50.54.10"
)

SSH_OPTS="-o StrictHostKeyChecking=no \
          -o UserKnownHostsFile=/dev/null \
          -o ConnectTimeout=10"

# =========================================================

command -v sshpass >/dev/null || { echo "sshpass is required"; exit 1; }

log() {
  echo "$(date '+%F %T') $*"
}

parse_host() {
  if [[ "$1" == *:* ]]; then
    HOST="${1%%:*}"
    PORT="${1##*:}"
  else
    HOST="$1"
    PORT="22"
  fi
}

change_password() {
  local srv="$1"
  parse_host "$srv"

  log "[$srv] Resetting ansible password"

  sshpass -p "$ADMIN_PASS" ssh ${SSH_OPTS} -p "$PORT" \
    "${ADMIN_USER}@${HOST}" \
    "echo '$ADMIN_PASS' | sudo -S bash -c '
      echo \"${ANSIBLE_USER}:${NEW_PASS}\" | chpasswd
      usermod -U ${ANSIBLE_USER} 2>/dev/null || true
      chage -d 0 ${ANSIBLE_USER} 2>/dev/null || true
    '" >/dev/null
}

verify_ssh() {
  local srv="$1"
  parse_host "$srv"

  sshpass -p "$NEW_PASS" ssh ${SSH_OPTS} -p "$PORT" \
    "${ANSIBLE_USER}@${HOST}" "echo OK" >/dev/null 2>&1
}

# ===================== MAIN ==============================

declare -A CHANGE VERIFY

for server in "${SERVERS[@]}"; do
  log "Processing $server"

  if change_password "$server"; then
    CHANGE["$server"]="RESET_OK"
  else
    CHANGE["$server"]="FAILED"
    continue
  fi

  sleep 1

  if verify_ssh "$server"; then
    VERIFY["$server"]="SSH_OK"
  else
    VERIFY["$server"]="SSH_FAILED"
  fi
done

# ===================== SUMMARY ===========================

echo
echo "==================== SUMMARY ===================="
printf "%-20s %-15s %-10s\n" "SERVER" "PASSWORD" "SSH"
echo "------------------------------------------------"
for s in "${SERVERS[@]}"; do
  printf "%-20s %-15s %-10s\n" \
    "$s" \
    "${CHANGE[$s]:-N/A}" \
    "${VERIFY[$s]:-N/A}"
done
echo "================================================"

# Exit non-zero if any failure
for s in "${SERVERS[@]}"; do
  if [[ "${CHANGE[$s]}" != "RESET_OK" || "${VERIFY[$s]}" != "SSH_OK" ]]; then
    exit 1
  fi
done

exit 0
