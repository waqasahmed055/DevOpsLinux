#!/usr/bin/nft -f

# Flush existing rules
flush ruleset

# Create inet table (handles both IPv4 and IPv6)
table inet filter {
    # Input chain for incoming traffic
    chain input {
        # Set chain policy and hook
        type filter hook input priority filter; policy drop;
        
        # Allow loopback interface traffic (unrestricted for local processes)
        iifname "lo" accept
        
        # Allow established and related connections
        ct state established,related accept
        
        # Allow SSH (port 22) on ens3 interface
        iifname "ens3" tcp dport 22 accept
        
        # Allow HTTPS (port 443) on ens3 interface
        iifname "ens3" tcp dport 443 accept
        
        # Allow individual ports 9901-9910 on ens3 interface
        iifname "ens3" tcp dport 9901 accept
        iifname "ens3" tcp dport 9902 accept
        iifname "ens3" tcp dport 9903 accept
        iifname "ens3" tcp dport 9904 accept
        iifname "ens3" tcp dport 9905 accept
        iifname "ens3" tcp dport 9906 accept
        iifname "ens3" tcp dport 9907 accept
        iifname "ens3" tcp dport 9908 accept
        iifname "ens3" tcp dport 9909 accept
        iifname "ens3" tcp dport 9910 accept
        
        # Allow ICMP ping requests (optional but recommended)
        icmp type echo-request accept
        icmpv6 type echo-request accept
        
        # Log dropped packets (optional - remove if not needed)
        # log prefix "nftables dropped: " drop
        
        # Default policy is drop (implicit)
    }
    
    # Forward chain (if forwarding is needed)
    chain forward {
        type filter hook forward priority filter; policy drop;
    }
    
    # Output chain for outgoing traffic (allow all by default)
    chain output {
        type filter hook output priority filter; policy accept;
    }
}
