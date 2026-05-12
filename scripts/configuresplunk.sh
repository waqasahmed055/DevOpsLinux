#!/bin/bash
# =============================================
# Splunk Universal Forwarder Configuration Script
# Converted from Ansible Playbook
# Targeted for RedHat/CentOS/Rocky 8+
# =============================================
set -euo pipefail

# ================== VARIABLES ==================
DEPLOYDIR_LOC="/opt/splunkforwarder/etc/system/local"
DEPLOYMENT_SERVER="ls-splunkds-prd.arvest.com:8089"
SPLUNK_PASSWD="splunk11"
RPM_FILE="splunkforwarder-10.2.0-d749cb17ea65.x86_64.rpm"
TMP_RPM="/tmp/splunkforwarder-10.2.0.x86_64.rpm"

echo "=== Starting Splunk Universal Forwarder Configuration ==="

# ================== PRE-CHECKS ==================
if [[ $EUID -ne 0 ]]; then
    echo "Error: This script must be run as root or with sudo"
    exit 1
fi

# OS check: must be RedHat-family, major version >= 8
if [[ -f /etc/os-release ]]; then
    . /etc/os-release
    DISTRO_ID="${ID:-}"
    MAJOR_VER="${VERSION_ID%%.*}"
else
    echo "Error: Cannot determine OS (/etc/os-release not found)"
    exit 1
fi

case "${DISTRO_ID,,}" in
    rhel|centos|rocky|almalinux|ol) ;;
    *)
        echo "Error: This script requires a RedHat-based distribution. Detected: ${DISTRO_ID}"
        exit 1
        ;;
esac

if (( MAJOR_VER < 8 )); then
    echo "Error: Requires major version >= 8. Detected: ${MAJOR_VER}"
    exit 1
fi

echo "OS check passed: ${DISTRO_ID} ${MAJOR_VER}"

if [[ ! -f "$RPM_FILE" ]]; then
    echo "Error: $RPM_FILE not found in current directory!"
    exit 1
fi

# ================== TASKS ==================

# Task: Copy outputs.conf
echo "→ Copying outputs.conf..."
cp -f outputs.conf "$DEPLOYDIR_LOC/outputs.conf" 2>/dev/null || true
chown splunk:splunk "$DEPLOYDIR_LOC/outputs.conf" 2>/dev/null || true
chmod 0664 "$DEPLOYDIR_LOC/outputs.conf" 2>/dev/null || true

# Task: Stop Splunk services
echo "→ Stopping Splunk services..."
systemctl stop splunk.server 2>/dev/null || true
systemctl stop splunkforwarder.service 2>/dev/null || true
systemctl stop SplunkForwarder.service 2>/dev/null || true

# Task: Copy Splunk Forwarder RPM
echo "→ Copying Splunk Forwarder RPM..."
cp -f "$RPM_FILE" "$TMP_RPM"

# Task: Upgrade/Install Splunk Universal Forwarder
echo "→ Upgrading/Installing Splunk Universal Forwarder..."
yum localinstall -y "$TMP_RPM"

# Task: Ensure splunk user exists
echo "→ Ensuring splunk user exists..."
id -u splunk &>/dev/null || useradd -r -s /bin/false splunk

# Task: Remove old splunkfwd user if exists
echo "→ Removing old splunkfwd user if exists..."
userdel splunkfwd 2>/dev/null || true

# Task: Start Splunk to accept license and seed password
# Note: Splunk CLI uses single-dash -systemd-managed (not GNU double-dash)
echo "→ Starting Splunk to accept license and set password..."
/opt/splunkforwarder/bin/splunk start \
    --accept-license \
    --answer-yes \
    --no-prompt \
    --seed-passwd "$SPLUNK_PASSWD" \
    -systemd-managed 1 \
    -user splunk || true

# Task: Stop Splunk service
echo "→ Stopping Splunk service..."
/opt/splunkforwarder/bin/splunk stop 2>/dev/null || true
systemctl stop SplunkForwarder.service 2>/dev/null || true

# Task: Disable old init.d boot-start
echo "→ Disabling old init.d boot-start..."
/opt/splunkforwarder/bin/splunk disable boot-start 2>/dev/null || true

# Task: Enable systemd boot-start (creates /etc/systemd/system/SplunkForwarder.service)
# Note: Splunk CLI uses single-dash -systemd-managed (not GNU double-dash)
echo "→ Enabling systemd boot-start..."
/opt/splunkforwarder/bin/splunk enable boot-start \
    -systemd-managed 1 \
    -user splunk

# Task: Create deployment directory (owner/group splunk, mode 0755)
echo "→ Creating deployment directory..."
mkdir -p "$DEPLOYDIR_LOC"
chown splunk:splunk "$DEPLOYDIR_LOC"
chmod 0755 "$DEPLOYDIR_LOC"

# Task: Create deploymentclient.conf (owner/group splunk, mode 0644)
echo "→ Creating deploymentclient.conf..."
cat > "$DEPLOYDIR_LOC/deploymentclient.conf" << EOF
[target-broker:deploymentServer]
targetUri = $DEPLOYMENT_SERVER
EOF
chown splunk:splunk "$DEPLOYDIR_LOC/deploymentclient.conf"
chmod 0644 "$DEPLOYDIR_LOC/deploymentclient.conf"

# Task: Set ACLs for splunk user
echo "→ Setting ACLs for splunk user..."
setfacl -m u:splunk:r /etc/ssh/sshd_config 2>/dev/null || true
setfacl -m u:splunk:r /var/log/audit/audit.log 2>/dev/null || true

# Task: Reload systemd and restart services
echo "→ Reloading systemd daemon..."
systemctl daemon-reload

echo "→ Restarting SplunkForwarder service..."
systemctl restart SplunkForwarder.service 2>/dev/null || true
systemctl restart splunkforwarder.service 2>/dev/null || true

echo "→ Restarting Splunk server service (if exists)..."
systemctl restart splunk.server 2>/dev/null || true

echo "=== Splunk Universal Forwarder Configuration Completed ==="
echo "Check status with: systemctl status SplunkForwarder.service"
