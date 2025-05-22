#!/bin/bash

# Ansible User Setup Script
# This script sets up an ansible user with SSH key authentication

set -e  # Exit on any error

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_status()  { echo -e "${BLUE}[INFO]${NC}    $1"; }
print_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[WARN]${NC}    $1"; }
print_error()   { echo -e "${RED}[ERROR]${NC}   $1"; }

check_root() {
    if [[ $EUID -ne 0 ]]; then
        print_error "This script must be run as root (use sudo)"
        exit 1
    fi
    print_success "Running as root - OK"
}

user_exists()      { id "$1" &>/dev/null; }
directory_exists() { [[ -d "$1" ]]; }
file_exists()      { [[ -f "$1" ]]; }

create_ansible_user() {
    local u="ansible"
    if user_exists "$u"; then
        print_warning "User '$u' already exists"
    else
        print_status "Creating user '$u'..."
        useradd -m -s /bin/bash "$u"
        print_success "User '$u' created"
    fi
}

set_ansible_password() {
    print_status "Setting password for 'ansible'..."
    echo "ansible:UneeD2024" | chpasswd
    print_success "Password set"
}

create_ssh_directory() {
    local sshdir="/home/ansible/.ssh"
    if directory_exists "$sshdir"; then
        print_warning "$sshdir already exists"
    else
        print_status "Creating $sshdir..."
        mkdir -p "$sshdir"
        chown ansible:ansible "$sshdir"
        chmod 700 "$sshdir"
        print_success "$sshdir created and secured"
    fi
}

setup_sudo_access() {
    local sf="/etc/sudoers.d/ansible"
    print_status "Configuring sudo for 'ansible'..."
    echo "ansible ALL=(ALL) NOPASSWD:ALL" > "$sf"
    chmod 440 "$sf"
    if visudo -cf "$sf" &>/dev/null; then
        print_success "NOPASSWD sudo granted"
    else
        print_error "Invalid sudoers file; aborting"
        rm -f "$sf"
        exit 1
    fi

    if getent group sudo &>/dev/null; then
        usermod -aG sudo ansible && print_success "Added to sudo group"
    elif getent group wheel &>/dev/null; then
        usermod -aG wheel ansible && print_success "Added to wheel group"
    fi
}

configure_access_conf() {
    local conf="/etc/security/access.conf"
    local bak="/etc/security/access.conf.bak"

    if ! file_exists "$conf"; then
        print_error "$conf not found; cannot patch"
        exit 1
    fi

    # Backup original
    cp "$conf" "$bak"
    print_status "Backed up original to $bak"

    # Use sed to insert 'ansible ' immediately after 'ALL EXCEPT'
    # Matches lines like "-:ALL EXCEPT ga-sa users :ALL" (with or without spaces)
    sed -i -E \
        '/^[[:space:]]*-[[:space:]]*: *ALL EXCEPT / {
            s/^( *- *: *ALL EXCEPT *)(.*)/\1ansible \2/
        }' "$conf"

    print_success "Patched 'ALL EXCEPT' line in $conf"
    print_status "Resulting line(s):"
    grep -E 'ALL EXCEPT.*' "$conf"
}

main() {
    print_status "Starting Ansible user setup..."
    check_root
    create_ansible_user
    set_ansible_password
    create_ssh_directory
    setup_sudo_access
    configure_access_conf
    print_success "Ansible user setup completed!"
}

main "$@"
