#!/bin/bash

# Configuration Variables
INITIAL_USER="user-a"
INITIAL_PASSWORD="your-initial-password-here"
ANSIBLE_USER="ansible"
NEW_ANSIBLE_PASSWORD="abc@123"
SERVER_LIST_FILE="servers.txt"  # One server per line

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Log files
SUCCESS_LOG="success_servers.log"
FAILED_LOG="failed_servers.log"

# Clear previous logs
> "$SUCCESS_LOG"
> "$FAILED_LOG"

# Check if sshpass is installed
if ! command -v sshpass &> /dev/null; then
    echo -e "${RED}Error: sshpass is not installed. Install it with: sudo dnf install sshpass${NC}"
    exit 1
fi

# Check if expect is installed
if ! command -v expect &> /dev/null; then
    echo -e "${RED}Error: expect is not installed. Install it with: sudo dnf install expect${NC}"
    exit 1
fi

# Check if server list exists
if [ ! -f "$SERVER_LIST_FILE" ]; then
    echo -e "${RED}Error: Server list file '$SERVER_LIST_FILE' not found${NC}"
    exit 1
fi

# Function to change password on a server
change_password() {
    local server=$1
    
    echo -e "${YELLOW}Processing server: $server${NC}"
    
    # Create expect script for password change
    expect -c "
        set timeout 60
        log_user 1
        
        spawn ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null ${INITIAL_USER}@${server}
        
        expect {
            -re \"(password|Password):\" {
                send \"${INITIAL_PASSWORD}\r\"
            }
            timeout {
                puts \"Timeout connecting to ${server}\"
                exit 1
            }
            eof {
                puts \"Connection failed to ${server}\"
                exit 1
            }
        }
        
        # Wait for shell prompt - RedHat/OCI format [user@host dir]$ or [user@host dir]#
        expect {
            -re \"\\\\](\\\$|#)\" {
                # Got prompt, continue
            }
            -re \"(\\\$|#) $\" {
                # Got simple prompt
            }
            timeout {
                puts \"Timeout after login - didn't receive prompt\"
                exit 1
            }
        }
        
        # Send sudo passwd command
        send \"sudo passwd ${ANSIBLE_USER}\r\"
        
        # Handle sudo password prompt
        expect {
            -re \"(password|Password).*:\" {
                send \"${INITIAL_PASSWORD}\r\"
            }
            -re \"New password:|Enter new UNIX password:\" {
                # No sudo password needed, already at new password prompt
                send \"${NEW_ANSIBLE_PASSWORD}\r\"
                exp_continue
            }
            timeout {
                puts \"Timeout waiting for sudo password\"
                exit 1
            }
        }
        
        # Wait for new password prompt
        expect {
            -re \"New password:|Enter new UNIX password:\" {
                send \"${NEW_ANSIBLE_PASSWORD}\r\"
            }
            timeout {
                puts \"Timeout waiting for new password prompt\"
                exit 1
            }
        }
        
        # Wait for retype password prompt
        expect {
            -re \"Retype.*password:|Retype new UNIX password:|Retype new password:\" {
                send \"${NEW_ANSIBLE_PASSWORD}\r\"
            }
            timeout {
                puts \"Timeout waiting for retype prompt\"
                exit 1
            }
        }
        
        # Wait for success message or prompt return
        expect {
            -re \"successfully|updated successfully|passwd: all authentication tokens updated successfully\" {
                puts \"SUCCESS\"
            }
            -re \"\\\\](\\\$|#)\" {
                puts \"SUCCESS\"
            }
            -re \"(\\\$|#) $\" {
                puts \"SUCCESS\"
            }
            timeout {
                puts \"Timeout waiting for completion\"
                exit 1
            }
        }
        
        send \"exit\r\"
        expect eof
        exit 0
    "
    
    return $?
}

# Function to verify SSH access
verify_access() {
    local server=$1
    
    sshpass -p "$NEW_ANSIBLE_PASSWORD" ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10 ${ANSIBLE_USER}@${server} "echo 'SSH_TEST_OK'" 2>/dev/null
    
    if [ $? -eq 0 ]; then
        return 0
    else
        return 1
    fi
}

# Main execution
echo "=========================================="
echo "Ansible Password Update Script"
echo "=========================================="
echo ""

total_servers=$(wc -l < "$SERVER_LIST_FILE")
current=0
success=0
failed=0

# Process each server
while IFS= read -r server || [ -n "$server" ]; do
    # Skip empty lines and comments
    [[ -z "$server" || "$server" =~ ^[[:space:]]*# ]] && continue
    
    ((current++))
    echo ""
    echo "[$current/$total_servers] Processing: $server"
    echo "----------------------------------------"
    
    # Change password
    if change_password "$server"; then
        echo -e "${GREEN}✓ Password changed successfully on $server${NC}"
        
        # Wait a moment for the password to propagate
        sleep 2
        
        # Verify access
        echo "Verifying SSH access with ansible user..."
        if verify_access "$server"; then
            echo -e "${GREEN}✓ SSH verification successful for $server${NC}"
            echo "$server" >> "$SUCCESS_LOG"
            ((success++))
        else
            echo -e "${RED}✗ SSH verification failed for $server${NC}"
            echo "$server - Password changed but SSH verification failed" >> "$FAILED_LOG"
            ((failed++))
        fi
    else
        echo -e "${RED}✗ Failed to change password on $server${NC}"
        echo "$server - Password change failed" >> "$FAILED_LOG"
        ((failed++))
    fi
done < "$SERVER_LIST_FILE"

# Summary
echo ""
echo "=========================================="
echo "Summary"
echo "=========================================="
echo -e "Total servers: $total_servers"
echo -e "${GREEN}Successful: $success${NC}"
echo -e "${RED}Failed: $failed${NC}"
echo ""
echo "Detailed logs:"
echo "  Success: $SUCCESS_LOG"
echo "  Failed: $FAILED_LOG"
echo "=========================================="

# Final verification for all successful servers
if [ $success -gt 0 ]; then
    echo ""
    echo "=========================================="
    echo "Final SSH Connectivity Test"
    echo "=========================================="
    
    while IFS= read -r server; do
        echo -n "Testing $server... "
        if sshpass -p "$NEW_ANSIBLE_PASSWORD" ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=5 ${ANSIBLE_USER}@${server} "hostname" 2>/dev/null; then
            echo -e "${GREEN}✓ Connected${NC}"
        else
            echo -e "${RED}✗ Failed${NC}"
        fi
    done < "$SUCCESS_LOG"
fi

exit 0
