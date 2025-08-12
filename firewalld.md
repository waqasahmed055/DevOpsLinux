```
grep -E '^FirewallBackend' /etc/firewalld/firewalld.conf || sudo cat /etc/firewalld/firewalld.conf
sudo nft list ruleset

sed -i 's/FirewallBackend=nftables/FirewallBackend=iptables/' /etc/firewalld/firewalld.conf

sudo tcpdump -n -i any 'tcp[tcpflags] & tcp-syn != 0 and dst portrange 9901-9910' -c 20


sudo nft add rule inet filter input tcp dport 9901-9910 ct state new log prefix "FW-LOG-9901-9910: " counter accept

sudo nft list tables
sudo nft list chain inet filter input 2>/dev/null || echo "chain-missing"

###
sudo nft add table inet filter
sudo nft add chain inet filter input '{ type filter hook input priority 0; policy accept; }'

##
sudo nft add rule inet filter input 'tcp dport 9901-9910 ct state new log prefix "FW-LOG-9901-9910: " counter accept'
sudo nft add rule inet filter input 'tcp dport 9901-9910 ct state new log prefix "FW-LOG-9901-9910: " counter accept'

#####

sudo nft add rule inet filter input 'tcp dport 9901-9910 ct state new log prefix "FW-LOG-9901-9910: " counter accept'
# watch logs:
sudo journalctl -k -f | grep FW-LOG-9901-9910

```


````
sudo tcpdump -nn -i any 'tcp and host 10.51.18.215 and (dst portrange 9901-9910 or src portrange 9901-9910)' -c 200
sudo ss -ltnp | egrep '9901|9902|9903|9904|9905|9906|9907|9908|9909|9910' || true

#####
sudo nft list ruleset | grep -nE 'drop|reject' || true
sudo firewall-cmd --direct --get-all-rules || true


````


```

sudo nft insert rule inet filter input position 0 'tcp dport 9901-9910 ct state new log prefix "TEST-ACCEPT-99xx: " counter accept'
sudo nft list chain inet filter input
# look for the TEST-ACCEPT-99xx rule and a counter value > 0 after you retry a request

sudo tcpdump -nn -i any 'tcp and host 10.51.18.215 and (dst portrange 9901-9910 or src portrange 9901-9910)' -c 200
