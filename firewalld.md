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


```
