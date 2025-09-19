create-net:
	@echo "Creating BlackIce Lab management network..."
	@docker network inspect blackice_lab_mgmt >/dev/null 2>&1 || \
	  docker network create --driver bridge --subnet 172.42.42.0/24 blackice_lab_mgmt
	@echo "Creating BlackIce Lab external network..."
	@docker network inspect blackice_lab_ext  >/dev/null 2>&1 || \
	  docker network create --driver bridge --subnet 172.42.10.0/24 blackice_lab_ext
	@echo "Creating BlackIce Lab DMZ network..."
	@docker network inspect blackice_lab_dmz  >/dev/null 2>&1 || \
	  docker network create --driver bridge --subnet 172.42.20.0/24 blackice_lab_dmz
	@echo "BlackIce Lab networks ready."


lab-start: syslog-start nftables-start squid-start nginx-start staticweb-start dvwa-start juice-start naxsi-start ws-start openaev-start packetbeat-start
	@echo "Labs started."

lab-stop: packetbeat-stop openaev-stop squid-stop nginx-stop staticweb-stop dvwa-stop juice-stop naxsi-stop ws-stop nftables-stop syslog-stop network-stop
	@echo "Lab stopped."

syslog-start: network-start
	@echo "Starting syslog server..."
	@LAB_ROOT=$$(pwd) docker compose -f ./syslog/docker-compose.yml up -d
	@echo "Syslog server started."

syslog-stop:
	@echo "Stopping syslog server..."
	@LAB_ROOT=$$(pwd) docker compose -f ./syslog/docker-compose.yml down
	@echo "Syslog server stopped."
	@echo "Clearing syslog data..."
	@rm -f ./syslog/logs/* 2>/dev/null || true
	@echo "Syslog data cleared."

nftables-start: network-start
	@echo "Starting nftables container..."
	@LAB_ROOT=$$(pwd) docker compose -f ./nftables/docker-compose.yml up -d
	@echo "nftables container started."

nftables-stop:
	@echo "Stopping nftables container..."
	@LAB_ROOT=$$(pwd) docker compose -f ./nftables/docker-compose.yml down
	@echo "nftables container stopped."

ws-start: network-start
	@echo "Starting worstation 1 and 2..."
	@LAB_ROOT=$$(pwd) docker compose -f ./ws/docker-compose.yml up -d
	@echo "Workstations started."

ws-stop:
	@echo "Stopping workstation 1 and 2..."
	@LAB_ROOT=$$(pwd) docker compose -f ./ws/docker-compose.yml down
	@echo "Workstations stopped."

nginx-start: network-start
	@echo "Starting nginx server..."
	@LAB_ROOT=$$(pwd) docker compose -f ./nginx/docker-compose.yml up -d
	@echo "nginx server started."

nginx-stop:
	@echo "Stopping nginx server..."
	@LAB_ROOT=$$(pwd) docker compose -f ./nginx/docker-compose.yml down
	@echo "nginx server stopped."

staticweb-start: network-start
	@echo "Starting static web server..."
	@LAB_ROOT=$$(pwd) docker compose -f ./staticweb/docker-compose.yml up -d
	@echo "Static web server started."

staticweb-stop:
	@echo "Stopping static web server..."
	@LAB_ROOT=$$(pwd) docker compose -f ./staticweb/docker-compose.yml down
	@echo "Static web server stopped."

dvwa-start: network-start
	@echo "Starting DVWA and database..."
	@LAB_ROOT=$$(pwd) docker compose -f ./dvwa/docker-compose.yml up -d
	@echo "DVWA started."

dvwa-stop:
	@echo "Stopping DVWA and database..."
	@LAB_ROOT=$$(pwd) docker compose -f ./dvwa/docker-compose.yml down
	@echo "DVWA stopped."

juice-start: network-start
	@echo "Starting Juice Shop..."
	@LAB_ROOT=$$(pwd) docker compose -f ./juice/docker-compose.yml up -d
	@echo "Juice Shop started."

juice-stop:
	@echo "Stopping Juice Shop..."
	@LAB_ROOT=$$(pwd) docker compose -f ./juice/docker-compose.yml down
	@echo "Juice Shop stopped."

naxsi-start: network-start
	@echo "Starting NAXSI WAF..."
	@LAB_ROOT=$$(pwd) docker compose -f ./naxsi/docker-compose.yml up -d
	@echo "NAXSI WAF started."

naxsi-stop:
	@echo "Stopping NAXSI WAF..."
	@LAB_ROOT=$$(pwd) docker compose -f ./naxsi/docker-compose.yml down
	@echo "NAXSI WAF stopped."

squid-start: network-start
	@echo "Starting Squid Proxy..."
	@LAB_ROOT=$$(pwd) docker compose -f ./squid/docker-compose.yml up -d
	@echo "Squid Proxy started."

squid-stop:
	@echo "Stopping Squid Proxy..."
	@LAB_ROOT=$$(pwd) docker compose -f ./squid/docker-compose.yml down
	@rm ./squid/ssl/* 2>/dev/null || true
	@echo "Squid Proxy stopped."

openaev-start: network-start
	@echo "Starting OpenAEV ..."
	@LAB_ROOT=$$(pwd) docker compose -f ./openaev/docker-compose.yml up -d
	@echo "OpenAEV started. Access at http://172.42.42.24:8080 or from host http://127.0.0.1:8080"

openaev-stop:
	@echo "Stopping OpenAEV..."
	@LAB_ROOT=$$(pwd) docker compose -f ./openaev/docker-compose.yml down
	@echo "OpenAEV stopped."

packetbeat-start:
	@echo "Starting Packetbeat monitoring on all containers..."
	@LAB_ROOT=$$(pwd) docker compose -f ./packetbeat/docker-compose.yml up -d
	@echo "Packetbeat monitoring started."

packetbeat-stop:
	@echo "Stopping Packetbeat monitoring..."
	@LAB_ROOT=$$(pwd) docker compose -f ./packetbeat/docker-compose.yml down
	@echo "Packetbeat monitoring stopped."

network-start: create-net
	@echo "Network started."
network-stop:
	@docker network rm blackice_lab_mgmt >/dev/null 2>&1 || true
	@docker network rm blackice_lab_ext  >/dev/null 2>&1 || true
	@docker network rm blackice_lab_dmz  >/dev/null 2>&1 || true
	@echo "Network stopped."
