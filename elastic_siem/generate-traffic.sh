#!/usr/bin/env bash
# generate-traffic.sh — Synthetic traffic generator for BlackIce Lab
# Exercises all lab services to produce Packetbeat → Logstash → Elastic SIEM events.
# Run from repo root: ./elastic_siem/generate-traffic.sh
#
# Generates: HTTP, DNS, ICMP, TLS, SQL, and suspicious patterns
# that trigger SIEM detection rules.

set -euo pipefail

# Lab IPs (mgmt network)
NGINX=172.42.42.100
STATICWEB=172.42.42.110
DVWA=172.42.42.122
DVWA_DB=172.42.42.121
JUICE=172.42.42.130
NAXSI=172.42.42.90
SQUID=172.42.42.95
NFTABLES=172.42.42.254
WS1=172.42.42.101
WS2=172.42.42.102
SYSLOG=172.42.42.10
ES_SIEM=172.42.42.60

ROUNDS=${1:-3}
DELAY=${2:-1}

echo "╔══════════════════════════════════════════════╗"
echo "║  BlackIce Lab — Traffic Generator            ║"
echo "║  Rounds: $ROUNDS | Delay: ${DELAY}s between bursts  ║"
echo "╚══════════════════════════════════════════════╝"
echo ""

# ---------- HTTP: Normal browsing ----------
http_normal() {
  echo "[*] HTTP normal traffic — browsing web services..."
  # Static web
  curl -sf -o /dev/null "http://${STATICWEB}:80/" && echo "    ✓ staticweb index"
  curl -sf -o /dev/null "http://${STATICWEB}:80/" -H "User-Agent: Mozilla/5.0" && echo "    ✓ staticweb with UA"
  # Nginx
  curl -sf -o /dev/null "http://${NGINX}:80/" && echo "    ✓ nginx index"
  curl -sf -o /dev/null "http://${NGINX}:80/nonexistent" || echo "    ✓ nginx 404"
  # DVWA
  curl -sf -o /dev/null "http://${DVWA}:80/" && echo "    ✓ dvwa index"
  curl -sf -o /dev/null "http://${DVWA}:80/login.php" && echo "    ✓ dvwa login page"
  # Juice Shop
  curl -sf -o /dev/null "http://${JUICE}:3000/" && echo "    ✓ juice shop index"
  curl -sf -o /dev/null "http://${JUICE}:3000/api/Products" && echo "    ✓ juice shop API"
}

# ---------- HTTP: Suspicious patterns (SQLi, XSS, path traversal) ----------
http_suspicious() {
  echo "[!] HTTP suspicious traffic — attack signatures..."
  # SQL injection attempts (will be caught by NAXSI/detection rules)
  curl -sf -o /dev/null "http://${DVWA}:80/vulnerabilities/sqli/?id=1'+OR+1=1--&Submit=Submit" || true
  echo "    ⚠ SQLi attempt on DVWA"
  curl -sf -o /dev/null "http://${DVWA}:80/vulnerabilities/sqli/?id=1'+UNION+SELECT+null,table_name+FROM+information_schema.tables--" || true
  echo "    ⚠ UNION-based SQLi on DVWA"

  # XSS attempts
  curl -sf -o /dev/null "http://${DVWA}:80/vulnerabilities/xss_r/?name=<script>alert('xss')</script>" || true
  echo "    ⚠ Reflected XSS attempt on DVWA"
  curl -sf -o /dev/null "http://${JUICE}:3000/api/Products?q=<img+src=x+onerror=alert(1)>" || true
  echo "    ⚠ XSS attempt on Juice Shop"

  # Path traversal
  curl -sf -o /dev/null "http://${NGINX}:80/../../../../etc/passwd" || true
  echo "    ⚠ Path traversal on nginx"
  curl -sf -o /dev/null "http://${STATICWEB}:80/../../../etc/shadow" || true
  echo "    ⚠ Path traversal on staticweb"

  # Command injection pattern
  curl -sf -o /dev/null "http://${DVWA}:80/vulnerabilities/exec/?ip=127.0.0.1;cat+/etc/passwd&Submit=Submit" || true
  echo "    ⚠ Command injection attempt on DVWA"

  # WAF trigger via NAXSI
  curl -sf -o /dev/null "http://${NAXSI}:80/?a=<script>" || true
  echo "    ⚠ WAF trigger on NAXSI (XSS)"
  curl -sf -o /dev/null "http://${NAXSI}:80/?id=1+OR+1=1" || true
  echo "    ⚠ WAF trigger on NAXSI (SQLi)"
}

# ---------- HTTP: Brute-force pattern ----------
http_bruteforce() {
  echo "[!] HTTP brute-force pattern — login attempts..."
  for i in $(seq 1 10); do
    curl -sf -o /dev/null -X POST "http://${DVWA}:80/login.php" \
      -d "username=admin&password=wrong${i}&Login=Login" \
      -H "Content-Type: application/x-www-form-urlencoded" || true
  done
  echo "    ⚠ 10 failed login attempts on DVWA"

  for i in $(seq 1 5); do
    curl -sf -o /dev/null -X POST "http://${JUICE}:3000/rest/user/login" \
      -H "Content-Type: application/json" \
      -d "{\"email\":\"admin@juice.sh\",\"password\":\"wrong${i}\"}" || true
  done
  echo "    ⚠ 5 failed login attempts on Juice Shop"
}

# ---------- DNS: Lookups ----------
dns_traffic() {
  echo "[*] DNS traffic — resolution attempts..."
  # These generate DNS queries visible to packetbeat
  docker exec ws1 nslookup google.com 8.8.8.8 >/dev/null 2>&1 && echo "    ✓ ws1 → google.com" || echo "    ~ ws1 DNS (may be blocked)"
  docker exec ws2 nslookup evil-c2-server.malware.test 8.8.8.8 >/dev/null 2>&1 || echo "    ⚠ ws2 → suspicious domain lookup"
  docker exec ws1 nslookup update.microsoft.com 8.8.8.8 >/dev/null 2>&1 && echo "    ✓ ws1 → microsoft update" || true
  docker exec ws2 nslookup crypto-miner-pool.io 8.8.8.8 >/dev/null 2>&1 || echo "    ⚠ ws2 → crypto miner domain"
}

# ---------- ICMP: Ping sweep ----------
icmp_traffic() {
  echo "[*] ICMP traffic — ping sweep..."
  for target in $NGINX $STATICWEB $DVWA $JUICE $NAXSI $SQUID; do
    docker exec ws1 ping -c 1 -W 1 "$target" >/dev/null 2>&1 && echo "    ✓ ws1 → $target" || true
  done
  # Suspicious: rapid ping from ws2 to all hosts (scan pattern)
  echo "[!] ICMP scan pattern from ws2..."
  for target in $NGINX $STATICWEB $DVWA $DVWA_DB $JUICE $NAXSI $SQUID $NFTABLES $WS1 $SYSLOG $ES_SIEM; do
    docker exec ws2 ping -c 1 -W 1 "$target" >/dev/null 2>&1 || true
  done
  echo "    ⚠ ws2 pinged 11 hosts rapidly (scan behavior)"
}

# ---------- Proxy: Traffic through Squid ----------
proxy_traffic() {
  echo "[*] Proxy traffic through Squid..."
  docker exec ws1 sh -c "http_proxy=http://${SQUID}:3128 curl -sf -o /dev/null http://${STATICWEB}:80/" 2>/dev/null && echo "    ✓ ws1 → squid → staticweb" || echo "    ~ proxy request (may need curl in ws1)"
  docker exec ws1 sh -c "http_proxy=http://${SQUID}:3128 curl -sf -o /dev/null http://${DVWA}:80/" 2>/dev/null && echo "    ✓ ws1 → squid → dvwa" || true
}

# ---------- Port scan simulation ----------
port_scan() {
  echo "[!] Port scan simulation from ws2..."
  # Connect to multiple ports on a target (scan pattern)
  for port in 21 22 23 25 80 110 143 443 445 993 995 3306 3389 5432 8080 8443; do
    docker exec ws2 sh -c "echo '' | nc -w1 ${DVWA} ${port}" >/dev/null 2>&1 || true
  done
  echo "    ⚠ ws2 scanned 16 ports on DVWA"
}

# ---------- Main loop ----------
for round in $(seq 1 "$ROUNDS"); do
  echo ""
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "  Round $round / $ROUNDS"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo ""

  http_normal
  sleep "$DELAY"

  http_suspicious
  sleep "$DELAY"

  http_bruteforce
  sleep "$DELAY"

  dns_traffic
  sleep "$DELAY"

  icmp_traffic
  sleep "$DELAY"

  proxy_traffic
  sleep "$DELAY"

  port_scan
  sleep "$DELAY"
done

echo ""
echo "╔══════════════════════════════════════════════╗"
echo "║  Traffic generation complete!                ║"
echo "║                                              ║"
echo "║  Check Kibana SIEM:                          ║"
echo "║    http://localhost:5601                     ║"
echo "║    → Security → Overview                     ║"
echo "║    → Discover (index: packetbeat-*)          ║"
echo "╚══════════════════════════════════════════════╝"
