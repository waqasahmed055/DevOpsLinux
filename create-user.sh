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
        # Create user with home directory
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
    
    # Ensure home directory exists first
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
    
    # Set proper ownership and permissions
    print_status "Setting ownership and permissions for .ssh directory..."
    chown "$username:$username" "$ssh_dir"
    chmod 700 "$ssh_dir"
    print_success "Set proper ownership and permissions for .ssh directory"
}

# This function was removed as SSH key generation is not needed

# This function was removed as authorized_keys setup is not needed without SSH key generation

# Add ansible user to sudoers
setup_sudo_access() {
    local username="ansible"
    local sudoers_file="/etc/sudoers.d/$username"
    
    print_status "Setting up sudo access for '$username'..."
    
    # Create sudoers.d directory if it doesn't exist
    if ! directory_exists "/etc/sudoers.d"; then
        mkdir -p /etc/sudoers.d
    fi
    
    if file_exists "$sudoers_file"; then
        print_warning "Sudoers file for '$username' already exists"
    else
        print_status "Adding '$username' to sudoers..."
        echo "$username ALL=(ALL) NOPASSWD:ALL" > "$sudoers_file"
        chmod 660 "$sudoers_file"
        
        # Validate the sudoers file
        if visudo -c -f "$sudoers_file" &>/dev/null; then
            print_success "Added '$username' to sudoers with NOPASSWD"
        else
            print_error "Sudoers file validation failed, removing invalid file"
            rm -f "$sudoers_file"
            exit 1
        fi
    fi
    
    # Alternative: Add to sudo group if sudoers.d doesn't work
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

# This function was removed as SSH key display is not needed without key generation

# Configure access.conf for SSH access
setup_access_conf() {
    local username="ansible"
    local access_conf="/etc/security/access.conf"
    
    print_status "Configuring access.conf for SSH access..."
    
    # Check if access.conf exists
    if ! file_exists "$access_conf"; then
        print_warning "access.conf file does not exist at $access_conf"
        print_status "Creating basic access.conf file..."
        cat > "$access_conf" << 'EOF'
# Access control configuration
# Format: permission:users/groups:origins
# + = allow, - = deny
# ALL = all users/groups/origins

# Allow ansible user to connect from anywhere
+ : ansible : ALL

# Allow root to connect from local
+ : root : LOCAL

# Default deny (uncomment if needed)
# - : ALL : ALL
EOF
        chmod 644 "$access_conf"
        print_success "Created access.conf file with ansible user access"
    else
        # Check if ansible user is already configured
        if grep -q "^[[:space:]]*+[[:space:]]*:[[:space:]]*ansible[[:space:]]*:" "$access_conf"; then
            print_warning "ansible user already has access configured in access.conf"
        else
            print_status "Adding ansible user to access.conf..."
            # Add ansible user access rule
            echo "" >> "$access_conf"
            echo "# Allow ansible user to connect from anywhere" >> "$access_conf"
            echo "+ : ansible : ALL" >> "$access_conf"
            print_success "Added ansible user access rule to access.conf"
        fi
    fi
    
    # Show current access.conf content for ansible user
    print_status "Current access rules for ansible user:"
    grep -n "ansible" "$access_conf" || print_warning "No explicit ansible rules found in access.conf"
}

# Main execution
main() {
    print_status "Starting Ansible user setup script..."
    
    # Check if running as root
    check_root
    
    # Create ansible user
    create_ansible_user
    
    # Set password
    set_ansible_password
    
    # Create .ssh directory
    create_ssh_directory
    
    # Setup sudo access
    setup_sudo_access
    
    # Configure access.conf for SSH access
    setup_access_conf
    
    print_success "Ansible user setup completed successfully!"
    print_status "=== SETUP SUMMARY ==="
    print_status "Username: ansible"
    print_status "Password: UneeD2024"
    print_status "Home directory: /home/ansible"
    print_status "SSH directory: /home/ansible/.ssh"
    print_status "Sudo access: Enabled (NOPASSWD)"
    print_status "SSH access: Configured in /etc/security/access.conf"
    print_status "===================="
    print_status "You can now switch to ansible user with: su - ansible"
    print_status "Or login via SSH: ssh ansible@localhost"
}

# Run main function
main "$@"
