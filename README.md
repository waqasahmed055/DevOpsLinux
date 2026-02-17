```
# show parsed smb.conf and extract section names (excluding [global])
testparm -s | awk -F'[][]' '/\[/{print $2}' | grep -v '^global$'


testparm -s 2>/dev/null | awk '/path/ && $3 !~ /share\/?$/ {for(i=3;i<NF;++i)printf$i" ";print$i}'

echo "ShareName" > shares.csv
testparm -s | awk -F'[][]' '/\[/{print $2}' | grep -v '^global$' >> shares.csv


```




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

ldapsearch -LLL -H ldap://ad.example.com -D "CN=SyncUser,OU=Service Accounts,DC=example,DC=com" -w '<password>' -b "DC=example,DC=com" "(sAMAccountName=jdoe)" sAMAccountName,distinguishedName


curl -O https://raw.githubusercontent.com/waqasahmed055/DevOpsLinux/main/ansible_playbook/test-bash.sh && chmod +x test-bash.sh && ./test-bash.sh


```


```
sudo -u nagios /usr/lib/nagios/plugins/check_ping -H 8.8.8.8 -w 100.0,20% -c 500.0,60% -p 5

```
sudo dnf downgrade \
  glibc-2.28-1* \
  glibc-common-2.28-1* \
  glibc-minimal-langpack-2.28-1* \
  glibc-headers-2.28-1* \
  glibc-all-langpacks-2.28-1* \
  glibc-gconv-extra-2.28-1* \
  glibc-locale-source-2.28-1*
```




https://www.ubuntumint.com/install-apache-tomcat-rhel-8/

```
find . -type f -exec grep -Ei 'rabbitmq.*(user|username|password)|user(name)?\s*=\s*|password\s*=' {} \; -print

find /opt/myapp -type f -exec grep -Ei 'rabbitmq.*(user|username|password)|user(name)?\s*=\s*|password\s*=' {} \; -print
```

```
sudo -u nagios /usr/lib/nagios/plugins/check_ping -H 8.8.8.8 -w 100.0,20% -c 500.0,60% -p 5
```


