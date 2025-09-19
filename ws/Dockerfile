FROM ubuntu:22.04

# Prevent interactive prompts during package installation
ENV DEBIAN_FRONTEND=noninteractive

# Install systemd and required packages
RUN apt-get update && apt-get install -y \
    systemd systemd-sysv \
    rsyslog iproute2 iputils-ping dnsutils curl wget \
    nmap netcat-openbsd kmod \
    && rm -rf /var/lib/apt/lists/*

# Remove unnecessary systemd services to reduce overhead
RUN systemctl mask \
    systemd-resolved \
    systemd-networkd \
    systemd-timesyncd \
    systemd-logind \
    getty.target \
    graphical.target \
    systemd-remount-fs.service \
    dev-hugepages.mount \
    sys-fs-fuse-connections.mount

# Enable rsyslog service
RUN systemctl enable rsyslog

# Create necessary directories for systemd
VOLUME ["/sys/fs/cgroup", "/tmp", "/run", "/run/lock"]

# Use systemd as init system
CMD ["/sbin/init"]
