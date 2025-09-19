#!/bin/sh
set -eux

# Subnets & service IPs
EXT_SUBNET="172.42.10.0/24"
DMZ_SUBNET="172.42.20.0/24"
MGMT_SUBNET="172.42.42.0/24"
SQUID_DMZ_IP="172.42.20.95"
WAF_DMZ_IP="172.42.20.90"
FW_DMZ_IP="172.42.20.254"


cat >/etc/nftables.conf <<'EOF'
flush ruleset

define EXT = { 172.42.10.0/24 }
define DMZ = { 172.42.20.0/24 }
define MGMT = { 172.42.42.0/24 }
define INTERNALS = { 172.42.10.0/24, 172.42.20.0/24, 172.42.42.0/24 }
define FW_DMZ_IP = 172.42.20.254

define SQUID = 172.42.20.95
define WAF   = 172.42.20.90

table inet filter {
  chain input {
    type filter hook input priority 0;
    policy drop;

    ct state established,related accept
    iif lo accept
    ip protocol icmp accept
    tcp dport 22 accept
  }

  chain forward {
    type filter hook forward priority 0;
    policy drop;

    # Always allow established flows
    ct state established,related counter accept

    # MGMT plane free in/out (subnet-based, no interface)
    ip saddr $MGMT counter accept
    ip daddr $MGMT counter accept

    # free HOST
    ip saddr 192.168.65.0/24 counter accept
    ip daddr 192.168.65.0/24 counter accept

    # Free 443 for now
    ip saddr $EXT tcp dport 443 accept

    # ===== ICMP (ping) support =====
    # Allow ICMP between all internal networks for troubleshooting
    ip saddr $INTERNALS ip daddr $INTERNALS ip protocol icmp counter accept

    # ===== DMZ-to-DMZ communication =====
    # Allow internal DMZ services to communicate with each other
    ip saddr $DMZ ip daddr $DMZ counter accept

    # ===== Transparent Proxy Support =====
    # Allow intercepted traffic from EXT to reach Squid
    # This is crucial for transparent proxy to work
    ip saddr $EXT ip daddr $SQUID counter accept

    # ===== Web entry policy =====
    # EXT -> DMZ web only through WAF (80/443)
    ip saddr $EXT ip daddr $WAF tcp dport {80,443,8080,3001} counter accept


    # ===== Proxy paths =====
    ip saddr $EXT ip daddr $DMZ tcp dport 3128 counter accept

    # ===== Direct access policy =====
    # Allow EXT -> DMZ for all ports except web (80/443 must go through proxy/WAF)
    ip saddr $EXT ip daddr $DMZ tcp dport != {80,443,8080,3001} counter accept

    # Drop (and log) any direct EXT -> DMZ web to other DMZ hosts
    ip saddr $EXT ip daddr $DMZ tcp dport {80,443,8080,3001} log prefix "FW_DROP_DIRECT_DMZ_WEB " flags all drop

    # Squid egress to Internet (HTTP/HTTPS) and DNS
    ip saddr $SQUID ip daddr != $INTERNALS tcp dport {80,443,8080,3001} counter accept
    ip saddr $SQUID ip daddr != $INTERNALS udp dport 53 counter accept

    # Everything else -> log + drop
    log prefix "FW_DROP " flags all
  }

  chain output {
    type filter hook output priority 0;
    policy accept;
  }
}

table ip nat {
  chain prerouting {
    type nat hook prerouting priority -100; policy accept;
    ip daddr 192.168.65.0/24 return
  }

  chain postrouting {
    type nat hook postrouting priority 100; policy accept;
    #
    # SNAT only when leaving INTERNETS (i.e., to non-internal addresses)
    ip daddr != $INTERNALS masquerade
  }
}
EOF

# Load rules
nft -f /etc/nftables.conf

# Heartbeat to syslog
TS=$(date +"%b %e %T"); HOST=$(hostname)
printf '<14>%s %s fw: firewall online (nft loaded, ip_forward=1)\n' "$TS" "$HOST" \
  | nc -u -w1 "${SYSLOG_ADDR:-172.42.42.10}" 514 || true

exec tail -f /dev/null
