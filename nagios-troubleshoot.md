```
./configure --with-nagios-user=nagios --with-nagios-group=nagios --with-command-group=nagcmd

/usr/local/nagios/bin/nagios -v /usr/local/nagios/etc/nagios.cfg

make install-daemoninit
make install-config
make install-commandmode
make install-webconf

```
