#!/usr/bin/env bash
# bulk-reset-ansible-pass.sh
# Fully non-interactive: uses sshpass for SSH login and supplies sudo password.
# Edit the VARIABLES section below and run: chmod +x bulk-reset-ansible-pass.sh && ./bulk-reset-ansible-pass.sh

set -euo pipefail
IFS=$'\n\t'

############## VARIABLES (edit only here) ################
ADMIN_USER="server-a"                    # admin user on targets
ADMIN_PASS="AdminUserPasswordHere"       # admin's SSH + sudo password
ANSIBLE_USER="ansible"                   # user to reset
NEW_PASS="abc@123"                       # new password for ansible

# servers list: host or host:port
SERVERS=(
  "10.50.54.9"
  "10.50.54.10:2222"
)

# SSH options (we enforce password auth to make sshpass reliable)
SSH_BASE_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=8 \
  -o PreferredAuthentications=password -o PubkeyAuthentication=no"

# If sudo on target requires a tty (Defaults requiretty), set to "yes"
FORCE_TTY="yes"

# number of seconds to wait between change and verify
VERIFY_SLEEP=1
#########################################################

# basic checks
command -v ssh >/dev/null 2>&1 || { echo "ssh not found"; exit 1; }
command -v sshpass >/dev/null 2>&1 || { echo "sshpass not found - install it (yum/dnf)"; exit 1; }

log() { printf '%s %s\n' "$(date '+%F %T')" "$*"; }

parse_hostport() {
  local raw="$1"
  if [[ "$raw" == *:* ]]; then
    HOST="${raw%%:*}"
    PORT="${raw##*:}"
  else
    HOST="$raw"
    PORT="22"
  fi
}

# Change password on remote host. Returns 0 on success.
change_password_remote() {
  local raw="$1"
  parse_hostport "$raw"

  # Build ssh command flags (force tty if needed)
  local TT=""
  if [[ "$FORCE_TTY" == "yes" ]]; then
    TT="-tt"
  fi

  # remote command: use printf to ensure newline and sudo -S to read from stdin
  # Use sudo -p '' to suppress interactive prompt text; we'll still feed password via stdin.
  local remote_cmd
  remote_cmd="printf '%s\n' \"${ADMIN_PASS}\" | sudo -S -p '' bash -c 'echo \"${ANSIBLE_USER}:${NEW_PASS}\" | chpasswd && usermod -U ${ANSIBLE_USER} 2>/dev/null || true && chage -d 0 ${ANSIBLE_USER} 2>/dev/null || true && echo REMOTE_OK_${ANSIBLE_USER}'"

  log "[$raw] running remote change (sshpass -> ssh ${ADMIN_USER}@${HOST}:${PORT})"

  # Use sshpass to provide SSH password for login; inside remote_cmd we again print the admin password and pipe to sudo -S
  # Capture combined output to validate REMOTE_OK marker.
  local out
  if out=$(sshpass -p "${ADMIN_PASS}" ssh ${TT} ${SSH_BASE_OPTS} -p "${PORT}" "${ADMIN_USER}@${HOST}" "${remote_cmd}" 2>&1); then
    if printf '%s' "$out" | grep -q "REMOTE_OK_${ANSIBLE_USER}"; then
      log "[$raw] remote change confirmed"
      return 0
    else
      log "[$raw] remote change command completed but did not return success marker. Output: $(printf '%s' \"$out\" | tr '\n' ' ')"
      return 1
    fi
  else
    log "[$raw] ssh/remote command failed. Output: $(printf '%s' \"$out\" | tr '\n' ' ')"
    return 2
  fi
}

# Verify login as ansible user using sshpass
verify_ansible_ssh() {
  local raw="$1"
  parse_hostport "$raw"

  # Try to login with sshpass; if requiretty was set and remote shell forces password change at first login, this may still fail
  if sshpass -p "${NEW_PASS}" ssh ${SSH_BASE_OPTS} -p "${PORT}" -oBatchMode=no -oConnectTimeout=8 "${ANSIBLE_USER}@${HOST}" "echo SSH_VERIFY_OK" >/dev/null 2>&1; then
    return 0
  else
    return 1
  fi
}

# Main loop
declare -A CHANGE_STATUS
declare -A VERIFY_STATUS

for s in "${SERVERS[@]}"; do
  log "Processing ${s}"
  if change_password_remote "$s"; then
    CHANGE_STATUS["$s"]="RESET_OK"
  else
    CHANGE_STATUS["$s"]="RESET_FAILED"
    VERIFY_STATUS["$s"]="SKIPPED"
    continue
  fi

  sleep "${VERIFY_SLEEP}"

  if verify_ansible_ssh "$s"; then
    VERIFY_STATUS["$s"]="SSH_OK"
    log "[$s] verify: SSH_OK"
  else
    VERIFY_STATUS["$s"]="SSH_FAILED"
    log "[$s] verify: SSH_FAILED"
  fi
done

# Summary
echo
echo "================ SUMMARY ================"
printf "%-28s %-14s %-12s\n" "SERVER(:PORT)" "PASSWORD" "SSH_VERIFY"
printf -- "-----------------------------------------------------------\n"
for s in "${SERVERS[@]}"; do
  printf "%-28s %-14s %-12s\n" "$s" "${CHANGE_STATUS[$s]:-N/A}" "${VERIFY_STATUS[$s]:-N/A}"
done
echo "========================================="
# exit non-zero if any failed
for s in "${SERVERS[@]}"; do
  if [[ "${CHANGE_STATUS[$s]}" != "RESET_OK" || "${VERIFY_STATUS[$s]}" != "SSH_OK" ]]; then
    exit 1
  fi
done
exit 0
