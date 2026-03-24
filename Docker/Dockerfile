FROM centos:centos7
USER root

# Configure CentOS vault repo and install epel-release & httpd
RUN sed -i \
    -e 's/^mirrorlist=/#mirrorlist=/g' \
    -e 's|^#baseurl=http://mirror.centos.org/centos/\$releasever|baseurl=http://vault.centos.org/centos/7|g' \
    /etc/yum.repos.d/CentOS-Base.repo && \
    yum clean all && \
    yum makecache && \
    yum install -y epel-release httpd && \
    yum clean all
    CMD ["/usr/sbin/httpd", "-D", "FOREGROUND"]

    existing Dockerfile
```
    RUN sed -i \
    -e 's/^mirrorlist=/#mirrorlist=/g' \
    -e 's|^#baseurl=http://mirror.centos.org/centos/\$releasever|baseurl=http://vault.centos.org/centos/7|g' \
    /etc/yum.repos.d/CentOS-Base.repo && \
    yum clean all && \
    yum makecache

```
