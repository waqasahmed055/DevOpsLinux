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
```
