```
ls /usr/local/nagios/var/spool/perfdata/ | wc -l
ls /usr/local/nagios/var/spool/xidpe/ | wc -l

find /usr/local/nagios/var/spool/perfdata/ -type f -delete

https://support.nagios.com/kb/article.php?id=9

```

```
tail -f /usr/local/nagios/var/service-perfdata
tail -f /usr/local/nagios/var/host-perfdata

ps aux | grep npcd

##
sudo lsof +D /usr/local/nagios/var/spool/xidpe 2>/dev/null | head -n 40
sudo fuser -v /usr/local/nagios/var/spool/xidpe || true
```

```
ls -ld /usr/local/nagios/var /usr/local/nagios/var/spool /usr/local/nagios/var/spool/xidpe /usr/local/nagios/share/perfdata
ls -lZ /usr/local/nagios/var/spool/xidpe /usr/local/nagios/share/perfdata
# fix ownership (if not nagios:nagios)
sudo chown -R nagios:nagios /usr/local/nagios
# test SELinux quickly (temporary)
getenforce
sudo setenforce 0
```
