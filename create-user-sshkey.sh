#!/bin/bash
#curl -fsSL https://raw.githubusercontent.com/waqasahmed055/DevOpsLinux/edit/main/create-user.sh -o create-user.sh
#chmod +x create-user.sh
#sudo ./create-user.sh
# Ansible User Setup Script
# This script sets up an ansible user with SSH key authentication

set -e  # Exit on any error

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# ============================================================
# REPLACE THE KEY BELOW with your actual public key
# Copy it from: /home/ansible/.ssh/id_rsa.pub  (or id_ed25519.pub)
# ============================================================
ANSIBLE_PUBLIC_KEY="ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAI REPLACE_THIS_WITH_YOUR_ACTUAL_PUBLIC_KEY ansible@controlnode"

# Check if script is run as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        print_error "This script must be run as root (use sudo)"
        print_error "Please run: sudo $0"
        exit 1
    fi
    print_success "Running as root - OK"
}

# Check if user exists
user_exists() {
    id "$1" &>/dev/null
}

# Check if directory exists
directory_exists() {
    [[ -d "$1" ]]
}

# Check if file exists
file_exists() {
    [[ -f "$1" ]]
}

# Create ansible user
create_ansible_user() {
    local username="ansible"
    
    if user_exists "$username"; then
        print_warning "User '$username' already exists, skipping user creation"
    else
        print_status "Creating user '$username'..."
        useradd -m -s /bin/bash "$username"
        if user_exists "$username"; then
            print_success "User '$username' created successfully"
        else
            print_error "Failed to create user '$username'"
            exit 1
        fi
    fi
}

# Set password for ansible user
set_ansible_password() {
    local username="ansible"
    
    print_status "Setting password for user '$username'..."
    if echo "ansible:UneeD2024" | chpasswd; then
        print_success "Password set for user '$username'"
    else
        print_error "Failed to set password for user '$username'"
        exit 1
    fi
}

# Create .ssh directory
create_ssh_directory() {
    local username="ansible"
    local home_dir="/home/$username"
    local ssh_dir="$home_dir/.ssh"
    
    if ! directory_exists "$home_dir"; then
        print_error "Home directory '$home_dir' does not exist"
        exit 1
    fi
    
    if directory_exists "$ssh_dir"; then
        print_warning ".ssh directory already exists at '$ssh_dir'"
    else
        print_status "Creating .ssh directory at '$ssh_dir'..."
        mkdir -p "$ssh_dir"
        if directory_exists "$ssh_dir"; then
            print_success ".ssh directory created at '$ssh_dir'"
        else
            print_error "Failed to create .ssh directory"
            exit 1
        fi
    fi
    
    # .ssh dir: owned by ansible, rwx------ (700)
    chown "$username:$username" "$ssh_dir"
    chmod 700 "$ssh_dir"
    print_success "Set ownership and permissions on .ssh directory (700)"
}

# Setup authorized_keys with hardcoded public key
setup_authorized_keys() {
    local username="ansible"
    local ssh_dir="/home/$username/.ssh"
    local auth_keys="$ssh_dir/authorized_keys"

    print_status "Setting up authorized_keys for '$username'..."

    if file_exists "$auth_keys"; then
        # Avoid duplicate entries
        if grep -qF "$ANSIBLE_PUBLIC_KEY" "$auth_keys" 2>/dev/null; then
            print_warning "Public key already present in authorized_keys, skipping"
        else
            echo "$ANSIBLE_PUBLIC_KEY" >> "$auth_keys"
            print_success "Public key appended to existing authorized_keys"
        fi
    else
        echo "$ANSIBLE_PUBLIC_KEY" > "$auth_keys"
        print_success "authorized_keys created with public key"
    fi

    # authorized_keys: owned by ansible, rw------- (600)
    chown "$username:$username" "$auth_keys"
    chmod 600 "$auth_keys"
    print_success "Set ownership and permissions on authorized_keys (600)"
}

# Add ansible user to sudoers
setup_sudo_access() {
    local username="ansible"
    local sudoers_file="/etc/sudoers.d/$username"
    
    print_status "Setting up sudo access for '$username'..."
    
    if ! directory_exists "/etc/sudoers.d"; then
        mkdir -p /etc/sudoers.d
    fi
    
    if file_exists "$sudoers_file"; then
        print_warning "Sudoers file for '$username' already exists"
    else
        print_status "Adding '$username' to sudoers..."
        echo "$username ALL=(ALL) NOPASSWD:ALL" > "$sudoers_file"
        chmod 660 "$sudoers_file"
        
        if visudo -c -f "$sudoers_file" &>/dev/null; then
            print_success "Added '$username' to sudoers with NOPASSWD"
        else
            print_error "Sudoers file validation failed, removing invalid file"
            rm -f "$sudoers_file"
            exit 1
        fi
    fi
    
    if getent group sudo &>/dev/null; then
        print_status "Adding '$username' to sudo group..."
        usermod -aG sudo "$username"
        print_success "Added '$username' to sudo group"
    elif getent group wheel &>/dev/null; then
        print_status "Adding '$username' to wheel group..."
        usermod -aG wheel "$username"
        print_success "Added '$username' to wheel group"
    fi
}

# Main execution
main() {
    print_status "Starting Ansible user setup script..."
    
    check_root
    create_ansible_user
    set_ansible_password
    create_ssh_directory
    setup_authorized_keys
    setup_sudo_access
    
    print_success "Ansible user setup completed successfully!"
    print_status "=== SETUP SUMMARY ==="
    print_status "Username:          ansible"
    print_status "Password:          UneeD2024"
    print_status "Home directory:    /home/ansible"
    print_status "SSH directory:     /home/ansible/.ssh         (chmod 700)"
    print_status "authorized_keys:   /home/ansible/.ssh/authorized_keys  (chmod 600)"
    print_status "Sudo access:       Enabled (NOPASSWD)"
    print_status "===================="
    print_status "You can now switch to ansible user with: su - ansible"
    print_status "Or login via SSH: ssh ansible@<host>"
}

main "$@"
