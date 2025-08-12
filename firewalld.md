```
grep -E '^FirewallBackend' /etc/firewalld/firewalld.conf || sudo cat /etc/firewalld/firewalld.conf
sudo nft list ruleset

sed -i 's/FirewallBackend=nftables/FirewallBackend=iptables/' /etc/firewalld/firewalld.conf

```
