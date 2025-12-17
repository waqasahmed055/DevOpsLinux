#!/usr/bin/env bash
# bulk-change-ansible-pass-expect.sh
# Use expect to handle SSH login + sudo prompt reliably.
set -euo pipefail
IFS=$'\n\t'

# ------------------ VARIABLES (edit these) ------------------
ADMIN_USER="server-a"                   # user used to connect to targets
ADMIN_PASS="AdminUserPasswordHere"      # admin's SSH + sudo password (in-script as requested)
ANSIBLE_USER="ansible"                  # the user to change
NEW_PASS="abc@123"                      # new password for ansible
SERVERS=(
  "10.50.54.9"
  "10.50.54.10:2222"
)
# SSH options used by expect (we'll pass them to ssh command)
SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10"
# ------------------------------------------------------------

# check expect is available
if ! command -v expect >/dev/null 2>&1; then
  echo "ERROR: 'expect' is required on this host. Install it (yum/dnf) and retry." >&2
  exit 2
fi

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

# Performs change via expect, returns 0 on success, non-zero otherwise
change_password_expect() {
  local srv="$1"
  parse_hostport "$srv"

  log "[$srv] Starting change (ssh -> sudo -> chpasswd)"

  /usr/bin/expect <<- 'EXPECT_EOF'
  # Use a heredoc that does not expand $, we will expand using shell here-doc substitution.
EXPECT_EOF
}

# We'll build and run a properly expanded expect script in bash below,
# because we need shell variable expansion inside the expect script.
for srv in "${SERVERS[@]}"; do
  parse_hostport "$srv"
  log "Processing: $srv (target ${HOST}:${PORT})"

  # Create and run an expect script per-host that:
  # 1) ssh to ADMIN_USER@HOST:PORT with SSH_OPTS
  # 2) handle "yes/no" host key, "password:" prompt for SSH
  # 3) after login run sudo to change ansible password (sudo will prompt; expect will send ADMIN_PASS)
  # 4) look for success marker REMOTE_OK and exit 0 if found
  expect_script=$(cat <<-EOF
    #!/usr/bin/expect -f
    set timeout 60
    log_user 1
    # Compose spawn command
    spawn ssh ${SSH_OPTS} -p ${PORT} ${ADMIN_USER}@${HOST}
    expect {
      -re "(?i)are you sure you want to continue connecting" {
        send "yes\r"
        exp_continue
      }
      -re ".*[Pp]assword:.*" {
        send "${ADMIN_PASS}\r"
      }
      timeout {
        puts "ERROR: ssh connection timed out"
        exit 3
      }
    }

    # Wait for a shell prompt. Match typical prompts ($, #, >) after newline.
    expect {
      -re {[#\\$>%] $} {}
      -re {\\r\\n} {}
      timeout {}
    }

    # Run sudo to change password. Use -p marker SUDOPROMPT to detect sudo password prompt.
    send -- "sudo -p SUDOPROMPT -S bash -c 'echo \"${ANSIBLE_USER}:${NEW_PASS}\" | chpasswd && usermod -U ${ANSIBLE_USER} 2>/dev/null || true && chage -d 0 ${ANSIBLE_USER} 2>/dev/null || true && echo REMOTE_OK_${ANSIBLE_USER}'\r"

    expect {
      -re "SUDOPROMPT" {
        send "${ADMIN_PASS}\r"
        exp_continue
      }
      -re "REMOTE_OK_${ANSIBLE_USER}" {
        puts "REMOTE_CHANGE_SUCCESS"
        exit 0
      }
      -re ".*[Pp]assword.*for.*" {
        # sudo still asking differently — try sending admin pass
        send "${ADMIN_PASS}\r"
        exp_continue
      }
      timeout {
        puts "ERROR: sudo/chpasswd timed out or failed"
        exit 4
      }
    }
EOF
)

  # Run the generated expect script
  # Use a temporary file to aid debugging if needed
  tmpf="$(mktemp /tmp/change-ansible.XXXXXX.expect)"
  printf '%s\n' "$expect_script" > "$tmpf"
  chmod +x "$tmpf"

  if out="$("$tmpf" 2>&1)"; then
    log "[$srv] change output: $out"
    CHANGE_STATUS["$srv"]="RESET_OK"
  else
    rc=$?
    log "[$srv] change FAILED (rc=$rc). Output: $out"
    CHANGE_STATUS["$srv"]="RESET_FAILED"
    VERIFY_STATUS["$srv"]="SKIPPED"
    rm -f "$tmpf"
    continue
  fi
  rm -f "$tmpf"

  # small pause then verify SSH as ansible user using expect
  sleep 1

  # verify with expect (handles hostkey prompt and password)
  verify_expect_script=$(cat <<-EOF
    #!/usr/bin/expect -f
    set timeout 20
    log_user 0
    spawn ssh ${SSH_OPTS} -p ${PORT} ${ANSIBLE_USER}@${HOST} "echo SSH_VERIFY_OK"
    expect {
      -re "(?i)are you sure you want to continue connecting" {
        send "yes\r"
        exp_continue
      }
      -re ".*[Pp]assword:.*" {
        send "${NEW_PASS}\r"
        exp_continue
      }
      -re "SSH_VERIFY_OK" {
        puts "VERIFY_OK"
        exit 0
      }
      -re "Permission denied" {
        puts "VERIFY_DENIED"
        exit 2
      }
      timeout {
        puts "VERIFY_TIMEOUT"
        exit 3
      }
    }
EOF
)

  tmpv="$(mktemp /tmp/verify-ansible.XXXXXX.expect)"
  printf '%s\n' "$verify_expect_script" > "$tmpv"
  chmod +x "$tmpv"

  if vout="$("$tmpv" 2>&1)"; then
    log "[$srv] verify output: $vout"
    VERIFY_STATUS["$srv"]="SSH_OK"
  else
    vrc=$?
    log "[$srv] verify FAILED (rc=$vrc). Output: $vout"
    VERIFY_STATUS["$srv"]="SSH_FAILED"
  fi
  rm -f "$tmpv"

done

# Show summary
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
