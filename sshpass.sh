#!/usr/bin/env bash
# =========================================================
# Bulk reset ansible password on RHEL servers
# =========================================================

set -euo pipefail

# ===================== VARIABLES =========================
# Admin user used to connect expired ansible servers
ADMIN_USER="server-a"
ADMIN_PASS="AdminUserPasswordHere"

# User whose password will be reset
ANSIBLE_USER="ansible"
NEW_PASS="abc@123"

# Server list (host or host:port)
SERVERS=(
  "server1.example.com"
  "10.0.0.5"
  "server3.internal:2222"
)

# SSH options
SSH_OPTS="-o StrictHostKeyChecking=no \
          -o UserKnownHostsFile=/dev/null \
          -o ConnectTimeout=10"

# =========================================================

command -v ssh >/dev/null || { echo "ssh not found"; exit 1; }
command -v sshpass >/dev/null || { echo "sshpass required"; exit 1; }

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

  log "[$srv] Changing password..."

  ssh ${SSH_OPTS} -p "$PORT" "${ADMIN_USER}@${HOST}" "sudo -S bash -c '
    echo \"${ANSIBLE_USER}:${NEW_PASS}\" | chpasswd
    usermod -U ${ANSIBLE_USER} 2>/dev/null || true
    chage -d 0 ${ANSIBLE_USER} 2>/dev/null || true
    echo OK
  '" <<< "$ADMIN_PASS" >/dev/null
}

verify_ssh() {
  local srv="$1"
  parse_host "$srv"

  sshpass -p "$NEW_PASS" ssh ${SSH_OPTS} -p "$PORT" \
    "${ANSIBLE_USER}@${HOST}" "echo OK" >/dev/null 2>&1
}

# ===================== MAIN ==============================

declare -A CHANGE_STATUS
declare -A VERIFY_STATUS

for server in "${SERVERS[@]}"; do
  log "Processing $server"

  if change_password "$server"; then
    CHANGE_STATUS["$server"]="PASSWORD_RESET"
  else
    CHANGE_STATUS["$server"]="FAILED"
    continue
  fi

  sleep 1

  if verify_ssh "$server"; then
    VERIFY_STATUS["$server"]="SSH_OK"
  else
    VERIFY_STATUS["$server"]="SSH_FAILED"
  fi
done

# ===================== SUMMARY ===========================

echo
echo "==================== SUMMARY ===================="
printf "%-30s %-20s %-15s\n" "SERVER" "PASSWORD" "SSH VERIFY"
echo "------------------------------------------------"
for s in "${SERVERS[@]}"; do
  printf "%-30s %-20s %-15s\n" \
    "$s" \
    "${CHANGE_STATUS[$s]:-N/A}" \
    "${VERIFY_STATUS[$s]:-N/A}"
done
echo "================================================"

# Exit non-zero if any failure
for s in "${SERVERS[@]}"; do
  if [[ "${CHANGE_STATUS[$s]}" != "PASSWORD_RESET" || "${VERIFY_STATUS[$s]}" != "SSH_OK" ]]; then
    exit 1
  fi
done

exit 0
