#!/bin/bash

# Tomcat 9 Installation Script for Oracle Linux/CentOS 7.9
# This script installs and configures Apache Tomcat 9 with Java 8

set -e  # Exit on any error

echo "========================================="
echo "Tomcat 9 Installation Script"
echo "========================================="

# Check if running as root or with sudo
if [ "$EUID" -ne 0 ]; then 
    echo "Please run this script as root or with sudo"
    exit 1
fi

# Check if tomcat user exists, create if not
if id "tomcat" &>/dev/null; then
    echo "Tomcat user already exists, skipping user creation..."
else
    echo "Creating tomcat user..."
    useradd -r -m -U -d /opt/tomcat -s /bin/false tomcat
fi

# Create tomcat9 directory
echo "Creating /opt/tomcat9 directory..."
mkdir -p /opt/tomcat9

# Navigate to /tmp directory
cd /tmp

# Download latest Tomcat 9 (check https://tomcat.apache.org/download-90.cgi for latest version)
echo "Downloading Tomcat 9.0.109..."
wget https://dlcdn.apache.org/tomcat/tomcat-9/v9.0.109/bin/apache-tomcat-9.0.109.tar.gz

# Extract the archive
echo "Extracting Tomcat archive..."
tar -xzf apache-tomcat-9.0.109.tar.gz -C /opt/tomcat9 --strip-components=1

# Set proper ownership
echo "Setting ownership and permissions..."
chown -R tomcat:tomcat /opt/tomcat9/
chmod +x /opt/tomcat9/bin/*.sh

# Set JAVA_HOME for current session
export JAVA_HOME=/usr/lib/jvm/java-1.8.0-openjdk-1.8.0.432.b06-1.0.1.el7_9.x86_64

# Make it permanent
echo "Setting JAVA_HOME environment variable..."
echo 'export JAVA_HOME=/usr/lib/jvm/java-1.8.0-openjdk-1.8.0.432.b06-1.0.1.el7_9.x86_64' >> /etc/environment
echo 'export PATH=$JAVA_HOME/bin:$PATH' >> /etc/environment

# Create systemd service file
echo "Creating systemd service file..."
tee /etc/systemd/system/tomcat.service << 'EOF'
[Unit]
Description=Apache Tomcat Web Application Container
After=network.target

[Service]
Type=forking

Environment="JAVA_HOME=/usr/lib/jvm/java-1.8.0-openjdk-1.8.0.432.b06-1.0.1.el7_9.x86_64"
Environment="CATALINA_HOME=/opt/tomcat9"
Environment="CATALINA_BASE=/opt/tomcat9"
Environment="CATALINA_OPTS=-Xms512M -Xmx1024M -server -XX:+UseParallelGC"
Environment="JAVA_OPTS=-Djava.awt.headless=true -Djava.security.egd=file:/dev/./urandom"

ExecStart=/opt/tomcat9/bin/startup.sh
ExecStop=/opt/tomcat9/bin/shutdown.sh

User=tomcat
Group=tomcat
UMask=0007
RestartSec=10
Restart=always

[Install]
WantedBy=multi-user.target
EOF

# Ensure tomcat user owns the directory
echo "Final ownership and permission setup..."
chown -R tomcat:tomcat /opt/tomcat9/
chmod +x /opt/tomcat9/bin/*.sh

# Reload systemd daemon
echo "Reloading systemd daemon..."
systemctl daemon-reload

# Enable and start Tomcat
echo "Enabling and starting Tomcat service..."
systemctl enable tomcat
systemctl start tomcat

# Check service status
echo "========================================="
echo "Checking Tomcat service status..."
systemctl status tomcat --no-pager

echo "========================================="
echo "Tomcat 9 installation completed!"
echo "========================================="
echo "Access Tomcat at: http://your-server-ip:8080"
echo "Tomcat installation directory: /opt/tomcat9"
echo "Service management:"
echo "  Start:   systemctl start tomcat"
echo "  Stop:    systemctl stop tomcat"
echo "  Restart: systemctl restart tomcat"
echo "  Status:  systemctl status tomcat"
echo "  Logs:    journalctl -u tomcat -f"
echo "========================================="
