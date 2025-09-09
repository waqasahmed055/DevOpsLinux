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
sudo tee /etc/environment << EOF
JAVA_HOME=/usr/lib/jvm/java-17-openjdk
CATALINA_HOME=/opt/tomcat
EOF
```

```
sudo tee /etc/systemd/system/tomcat.service << EOF
[Unit]
Description=Apache Tomcat Web Application Container
After=network.target

[Service]
Type=forking

Environment="JAVA_HOME=/usr/lib/jvm/java-17-openjdk"
Environment="CATALINA_HOME=/opt/tomcat"
Environment="CATALINA_BASE=/opt/tomcat"
Environment="CATALINA_OPTS=-Xms512M -Xmx1024M -server -XX:+UseG1GC"
Environment="JAVA_OPTS=-Djava.awt.headless=true -Djava.security.egd=file:/dev/./urandom --add-opens=java.base/java.lang=ALL-UNNAMED --add-opens=java.base/java.io=ALL-UNNAMED --add-opens=java.base/java.util=ALL-UNNAMED --add-opens=java.base/java.util.concurrent=ALL-UNNAMED --add-opens=java.rmi/sun.rmi.transport=ALL-UNNAMED"

ExecStart=/opt/tomcat/bin/startup.sh
ExecStop=/opt/tomcat/bin/shutdown.sh

User=tomcat
Group=tomcat
UMask=0007
RestartSec=10
Restart=always

[Install]
WantedBy=multi-user.target
EOF
```

