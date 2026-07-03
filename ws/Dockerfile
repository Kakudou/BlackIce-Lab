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

# Boot into a real systemd target instead of masked graphical.target
RUN ln -sfn /lib/systemd/system/multi-user.target /etc/systemd/system/default.target

# Recreate root's user systemd runtime dir on every boot
RUN printf '%s\n' \
  'd /run/user/0 0700 root root -' \
  > /etc/tmpfiles.d/root-user-runtime.conf

# Start root user systemd manager, then run the OpenAEV installer if present
RUN printf '%s\n' \
  '[Unit]' \
  'Description=Start root user systemd manager for user services' \
  'After=dbus.service systemd-tmpfiles-setup.service' \
  'Wants=dbus.service' \
  '' \
  '[Service]' \
  'Type=oneshot' \
  'RemainAfterExit=yes' \
  'ExecStart=/bin/mkdir -p /run/user/0' \
  'ExecStart=/bin/chmod 700 /run/user/0' \
  'ExecStart=/bin/systemctl start user@0.service' \
  '' \
  '[Install]' \
  'WantedBy=multi-user.target' \
  > /etc/systemd/system/root-user-bus.service

RUN systemctl enable root-user-bus.service

# Enable rsyslog service
RUN systemctl enable rsyslog

# Create necessary directories for systemd
VOLUME ["/sys/fs/cgroup", "/tmp", "/run", "/run/lock"]

# Use systemd as init system
CMD ["/sbin/init"]
