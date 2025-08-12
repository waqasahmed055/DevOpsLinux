```
grep -E '^FirewallBackend' /etc/firewalld/firewalld.conf || sudo cat /etc/firewalld/firewalld.conf
sudo nft list ruleset

sed -i 's/FirewallBackend=nftables/FirewallBackend=iptables/' /etc/firewalld/firewalld.conf

sudo tcpdump -n -i any 'tcp[tcpflags] & tcp-syn != 0 and dst portrange 9901-9910' -c 20


sudo nft add rule inet filter input tcp dport 9901-9910 ct state new log prefix "FW-LOG-9901-9910: " counter accept

```
