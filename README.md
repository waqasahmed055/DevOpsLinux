# DevOpsLinux
Work related to Linux DevOps

echo "Test email body" | mail -s "Test Subject" recipient@example.com

SELECT TABLE_NAME
FROM INFORMATION_SCHEMA.TABLES
WHERE TABLE_TYPE = 'BASE TABLE';

SELECT name
FROM sys.tables;

Tomcat installation

wget https://dlcdn.apache.org/tomcat/tomcat-9/v9.0.107/bin/apache-tomcat-9.0.107.tar.gz
sudo tar -xzf apache-tomcat-9.0.107.tar.gz -C /opt/tomcat --strip-components=1

# Set proper ownership
sudo chown -R tomcat:tomcat /opt/tomcat/
sudo chmod +x /opt/tomcat/bin/*.sh

#user
sudo useradd -r -m -U -d /opt/tomcat -s /bin/false tomcat

# Install OpenJDK 11
sudo dnf install java-11-openjdk java-11-openjdk-devel -y

# Or install OpenJDK 17 (recommended)
sudo dnf install java-17-openjdk java-17-openjdk-devel -y

# Verify Java installation
java -version

