#!/bin/sh

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "\n--- Adguard By PeDitX (Full Version) ---\n"

# Helper function for silent execution
log_step() {
    local msg="$1"
    shift
    printf "%-60s" "$msg..."
    if "$@" >/dev/null 2>&1; then
        echo -e "${GREEN}[OK]${NC}"
        return 0
    else
        echo -e "${RED}[FAILED]${NC}"
        return 1
    fi
}

# 0. Check for dnsmasq-full
if ! opkg list-installed | grep -q "dnsmasq-full"; then
    echo -e "${YELLOW}Warning: 'dnsmasq-full' not found! Passwall requires the full version.${NC}"
    echo "Proceeding, but please ensure your setup is correct."
else
    echo -e "${GREEN}Confirmed: dnsmasq-full is present.${NC}"
fi

# 0.1 Force DNS to Google (Temporary Fix for Update/Install)
# This prevents opkg failure due to bad ISP DNS
log_step "Setting temporary DNS (8.8.8.8)" sh -c "echo 'nameserver 8.8.8.8' > /tmp/resolv.conf"

# 1. Update and Install
log_step "Updating package lists" opkg update

if ! opkg list-installed | grep -q adguardhome; then
    # Try standard install first
    if ! log_step "Installing AdGuardHome package" opkg install adguardhome; then
        echo -e "${YELLOW}Standard install failed. Trying --nodeps to protect dnsmasq-full...${NC}"
        # Retry with --nodeps
        log_step "Installing AdGuardHome (No Deps)" opkg install adguardhome --nodeps
    fi
    
    # CRITICAL CHECK: Abort if install failed completely
    if ! opkg list-installed | grep -q adguardhome; then
        echo -e "\n${RED}CRITICAL ERROR: AdGuardHome failed to install.${NC}"
        echo "Even with Google DNS, the download failed."
        echo "Check if your router has internet access."
        exit 1
    fi
else
    log_step "AdGuardHome is already installed" true
fi

# 2. Configure Dnsmasq-full (Move to port 54)
log_step "Switching Dnsmasq-full to port 54" uci set dhcp.@dnsmasq[0].port='54'
log_step "Disabling local resolving in Dnsmasq" uci set dhcp.@dnsmasq[0].noresolv='1'
log_step "Committing DHCP changes" uci commit dhcp

# 3. Open Firewall Port 3000
if ! uci get firewall.AdGuardHomeWeb >/dev/null 2>&1; then
    log_step "Creating Firewall rule for Web UI (Port 3000)" uci add firewall rule
    
    uci set firewall.@rule[-1].name='AdGuardHomeWeb'
    uci set firewall.@rule[-1].src='lan'
    uci set firewall.@rule[-1].proto='tcp'
    uci set firewall.@rule[-1].dest_port='3000'
    uci set firewall.@rule[-1].target='ACCEPT'
    
    log_step "Committing Firewall changes" uci commit firewall
else
    log_step "Firewall rule already exists" true
fi

# 4. Generate Config
create_config() {
cat <<EOF > /etc/adguardhome.yaml
bind_host: 0.0.0.0
bind_port: 3000
auth_attempts: 5
block_auth_min: 15
http_proxy_port: 0
language: en
theme: auto
debug_pprof: false
web_session_ttl: 720
dns:
  bind_hosts:
  - 0.0.0.0
  port: 53
  statistics_interval: 1
  querylog_enabled: true
  querylog_file_enabled: true
  querylog_interval: 24h
  querylog_size_memory: 1000
  anonymize_client_ip: false
  protection_enabled: true
  blocking_mode: default
  blocking_ipv4: ""
  blocking_ipv6: ""
  blocked_response_ttl: 10
  parental_block_host: family-block.dns.adguard.com
  safebrowsing_block_host: standard-block.dns.adguard.com
  ratelimit: 20
  ratelimit_whitelist: []
  refuse_any: true
  upstream_dns:
  - 127.0.0.1:54
  upstream_dns_file: ""
  bootstrap_dns:
  - 127.0.0.1:54
  all_servers: false
  fastest_addr: false
  fastest_timeout: 1s
  allowed_clients: []
  disallowed_clients: []
  blocked_hosts: []
  cache_size: 4194304
  cache_ttl_min: 0
  cache_ttl_max: 0
  cache_optimistic: false
  bogus_nxdomain: []
  aaaa_disabled: false
  enable_dnssec: false
  edns_client_subnet: false
  max_goroutines: 300
  handle_ddr: true
  ipse_enabled: false
  win_config: {}
  socket_opts:
    reuse_port: false
    freebind: false
tls:
  enabled: false
  server_name: ""
  force_https: false
  port_https: 443
  port_dns_over_tls: 853
  port_dns_over_quic: 784
  port_dnscrypt: 0
  dnscrypt_config_file: ""
  allow_unencrypted_doh: false
  certificate_chain: ""
  private_key: ""
  certificate_path: ""
  private_key_path: ""
  strict_sni_check: false
filters:
- enabled: true
  url: https://adguardteam.github.io/HostlistsRegistry/assets/filter_1.txt
  name: AdGuard DNS filter
  id: 1
clients:
  runtime_sources:
    whois: true
    arp: true
    rdns: true
    dhcp: true
    hosts: true
log_file: ""
verbose: false
os:
  group: ""
  user: ""
schema_version: 14
EOF
}

log_step "Generating AdGuard Home Configuration" create_config

# 5. Restart Services
log_step "Restarting Dnsmasq-full" /etc/init.d/dnsmasq restart
log_step "Restarting Firewall" /etc/init.d/firewall restart
log_step "Enabling AdGuard Home autostart" /etc/init.d/adguardhome enable
log_step "Starting AdGuard Home Service" /etc/init.d/adguardhome restart

# Final Output
LAN_IP=$(uci get network.lan.ipaddr)
echo -e "\n${GREEN}Installation Completed Successfully!${NC}"
echo -e "Access Admin Panel: http://${LAN_IP}:3000"
echo -e "Passwall Integration: Active (AGH:53 -> Dnsmasq-full:54)"
