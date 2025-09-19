FROM debian:stable-slim

RUN apt-get update \
    && apt-get install -y --no-install-recommends openssl ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Install Squid + rsyslog + basic tools
RUN apt-get update && apt-get install -y --no-install-recommends \
    squid-openssl rsyslog ca-certificates curl iproute2 iputils-ping netcat-traditional \
    gettext-base \
    && rm -rf /var/lib/apt/lists/*


# Copy configs and entrypoint
COPY squid.conf /etc/squid/squid.conf
COPY rsyslog.conf /etc/rsyslog.conf
COPY entrypoint.sh /entrypoint.sh

# Ensure entrypoint is executable
RUN chmod +x /entrypoint.sh

# Default entrypoint: our wrapper starts rsyslog + squid
ENTRYPOINT ["/entrypoint.sh"]
