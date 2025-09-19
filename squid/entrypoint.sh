#!/bin/sh
set -eux
export PATH="/usr/sbin:/usr/bin:/sbin:/bin"

# Make default route go via DMZ gateway
ip route del default || true
ip route add default via "${DMZ_GATEWAY}" dev eth0

# normalize CRLF
sed -i 's/\r$//' /etc/rsyslog.conf /etc/squid/squid.conf || true

# dirs + perms
mkdir -p /var/log/squid /var/spool/squid /run/squid /var/lib/rsyslog
chown -R proxy:proxy /var/log/squid /var/spool/squid /run/squid

envsubst < /etc/rsyslog.conf > /etc/rsyslog.conf.tmp && mv /etc/rsyslog.conf.tmp /etc/rsyslog.conf

# empty logs with correct ownership
: > /var/log/squid/access.log
: > /var/log/squid/cache.log
chown proxy:proxy /var/log/squid/access.log /var/log/squid/cache.log

# rsyslog clean start
rm -f /run/rsyslogd.pid || true
pkill -9 rsyslogd 2>/dev/null || true
rsyslogd

# --- SSL Bump bootstrap (idempotent) ---
mkdir -p /etc/squid/ssl /var/spool/squid/
chown -R proxy:proxy /etc/squid/ssl /var/spool/squid/

# Create a lab CA if not present
if [ ! -s /etc/squid/ssl/ca.key ] || [ ! -s /etc/squid/ssl/ca.pem ]; then
  openssl req -new -newkey rsa:4096 -sha256 -days 3650 -nodes -x509 \
    -subj "/CN=BlackIce Squid Lab CA/O=BlackIce/OU=WAF-Lab" \
    -keyout /etc/squid/ssl/ca.key -out /etc/squid/ssl/ca.pem
  chown proxy:proxy /etc/squid/ssl/ca.key /etc/squid/ssl/ca.pem
  cat /etc/squid/ssl/ca.pem /etc/squid/ssl/ca.key >> /etc/squid/ssl/ca-key-cert.pem
  chown proxy:proxy /etc/squid/ssl/ca-key-cert.pem
  su -s /bin/sh -c "/usr/lib/squid/security_file_certgen -c -s /var/spool/squid/ssl_db -M 8MB" proxy
fi

# one-time cache init
if [ ! -d /var/spool/squid/00 ]; then
  su -s /bin/sh -c "/usr/sbin/squid -z -N -f /etc/squid/squid.conf" proxy || true
fi

# ensure no stale pid from -z
rm -f /run/squid/squid.pid || true

# ✅ START SQUID (foreground). If it dies, dump cache.log so `docker logs` shows why.
exec /usr/sbin/squid -N -f /etc/squid/squid.conf || {
  echo "=== squid exited with $?; dumping cache.log ==="
  tail -n 200 /var/log/squid/cache.log || true
  exit 1
}
