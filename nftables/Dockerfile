# Minimal firewall/router with nftables on Alpine
FROM alpine:3.20

# Tools: nftables + routing + basic net utils
RUN apk add --no-cache \
      nftables iproute2 iputils busybox-extras \
      iptables curl tcpdump netcat-openbsd

# Quiet the nftables service manager warnings (we run it directly)
RUN mkdir -p /etc/nftables && true

# Default shell
SHELL ["/bin/sh","-lc"]

# Healthcheck (optional): list rules (will fail early if nft is broken)
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD nft list ruleset >/dev/null 2>&1 || exit 1

