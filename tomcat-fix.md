```
AmbientCapabilities=CAP_NET_BIND_SERVICE
CapabilityBoundingSet=CAP_NET_BIND_SERVICE
```

```
# Navigate to /tmp directory
cd /tmp

# Download latest Tomcat 9 (check https://tomcat.apache.org/download-90.cgi for latest version)
wget https://dlcdn.apache.org/tomcat/tomcat-9/v9.0.109/bin/apache-tomcat-9.0.109.tar.gz

# Extract the archive
sudo tar -xzf apache-tomcat-9.0.109.tar.gz -C /opt/tomcat --strip-components=1

# Set proper ownership
sudo chown -R tomcat:tomcat /opt/tomcat/
sudo chmod +x /opt/tomcat/bin/*.sh
```

```
# Set JAVA_HOME for current session
export JAVA_HOME=/usr/lib/jvm/java-1.8.0-openjdk-1.8.0.432.b06-1.0.1.el7_9.x86_64

# Make it permanent
echo 'export JAVA_HOME=/usr/lib/jvm/java-1.8.0-openjdk-1.8.0.432.b06-1.0.1.el7_9.x86_64' | sudo tee -a /etc/environment
echo 'export PATH=$JAVA_HOME/bin:$PATH' | sudo tee -a /etc/environment
```

```
sudo tee /etc/systemd/system/tomcat.service << 'EOF'
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
```
```
# Ensure tomcat user owns the directory
sudo chown -R tomcat:tomcat /opt/tomcat9/
sudo chmod +x /opt/tomcat9/bin/*.sh
```
