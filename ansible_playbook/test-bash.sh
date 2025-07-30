#!/bin/bash
# Test script to populate bash history with both normal and password-containing commands
# Run this script to create test history entries, then run your Ansible playbook to test

echo "=== BASH HISTORY TESTING SCRIPT ==="
echo "This script will add various commands to your bash history for testing"
echo "Some contain password keywords (should be removed)"
echo "Others are normal commands (should be preserved)"
echo ""

# Function to add command to history
add_to_history() {
    local cmd="$1"
    echo "Adding to history: $cmd"
    # Add to current session history
    history -s "$cmd"
    # Also append directly to history file
    echo "$cmd" >> ~/.bash_history
}

echo "Adding NORMAL commands (these should be PRESERVED):"
echo "=================================================="

# Normal commands that should be preserved
add_to_history "ls -la"
add_to_history "cd /var/log"
add_to_history "ps aux"
add_to_history "df -h"
add_to_history "free -m"
add_to_history "top"
add_to_history "cat /etc/hostname"
add_to_history "whoami"
add_to_history "date"
add_to_history "uptime"
add_to_history "netstat -tulpn"
add_to_history "systemctl status sshd"
add_to_history "tail -f /var/log/messages"
add_to_history "find /tmp -name '*.log'"
add_to_history "grep -r 'error' /var/log/"
add_to_history "awk '{print \$1}' /etc/passwd"
add_to_history "sed 's/old/new/g' file.txt"
add_to_history "chmod 755 script.sh"
add_to_history "chown user:group file.txt"
add_to_history "tar -czf backup.tar.gz /home"

echo ""
echo "Adding PASSWORD-CONTAINING commands (these should be REMOVED):"
echo "============================================================="

# Commands with password keywords that should be removed
add_to_history "mysql -u root -p password123"
add_to_history "ssh user@server -password mypass"
add_to_history "curl -u admin:password http://example.com"
add_to_history "wget --password=secret123 ftp://server/file"
add_to_history "scp -password file user@server:/path"
add_to_history "rsync --password-file=/tmp/pass source dest"
add_to_history "echo 'password=admin123' > config.txt"
add_to_history "export DB_PASSWORD=mysecret"
add_to_history "passwd username"
add_to_history "sudo passwd root"
add_to_history "chpasswd < passwords.txt"
add_to_history "htpasswd -c .htpasswd user"
add_to_history "openssl passwd -1 mypassword"
add_to_history "gpg --symmetric --cipher-algo AES256 --s2k-mode 3 --s2k-count 65536 --s2k-digest-algo SHA512 --compress-algo 1 --personal-compress-preferences 2 1 3 --personal-cipher-preferences AES256 AES192 AES CAST5 3DES --personal-digest-preferences SHA512 SHA256 SHA1 --cert-digest-algo SHA256 --default-preference-list SHA512 SHA256 SHA1 AES256 AES192 AES CAST5 ZLIB BZIP2 ZIP --keyserver-options no-honor-keyserver-url --display-charset utf-8 --utf8-strings --no-version --with-fingerprint --keyid-format 0xlong --list-options show-uid-validity --verify-options show-uid-validity --armor --output encrypted.gpg --passphrase mypassword123 file.txt"
add_to_history "docker login -u user -p password123 registry.com"
add_to_history "ansible-vault create --vault-password-file=pass.txt secrets.yml"
add_to_history "git clone https://user:password@github.com/repo.git"
add_to_history "ftp -n server <<< 'user username password'"
add_to_history "mount -t cifs //server/share /mnt -o username=user,password=pass"
add_to_history "kubectl create secret generic mysecret --from-literal=password=secretpass"
add_to_history "redis-cli -a password123 ping"
add_to_history "mongosh --username admin --password secret123"
add_to_history "psql -h localhost -U postgres -W password"
add_to_history "mysqldump -u root -p password123 database > backup.sql"
add_to_history "API_KEY=secret123 curl -H 'Authorization: Bearer token123' api.com"
add_to_history "echo 'secret=mysecret' >> .env"
add_to_history "export JWT_SECRET=verysecrettoken"
add_to_history "openssl genrsa -aes256 -passout pass:password123 -out private.key 2048"
add_to_history "gpg --batch --yes --passphrase password123 --decrypt file.gpg"
add_to_history "zip -P password123 archive.zip files/*"
add_to_history "unrar x -ppassword123 archive.rar"
add_to_history "john --wordlist=/usr/share/wordlists/rockyou.txt --format=md5 hash.txt"
