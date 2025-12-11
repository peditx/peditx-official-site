#!/bin/sh

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "\n--- Adguard By PeDitX (Uninstall) ---\n"

log_step() {
    local msg="$1"
    shift
    printf "%-60s" "$msg..."
    if "$@" >/dev/null 2>&1; then
        echo -e "${GREEN}[OK]${NC}"
    else
        echo -e "${RED}[FAILED]${NC}"
    fi
}

echo "Uninstalling AdGuard Home & Reverting Dnsmasq-full..."

# 1. Stop Service
if [ -f /etc/init.d/adguardhome ]; then
    log_step "Stopping AdGuard Home service" /etc/init.d/adguardhome stop
    log_step "Disabling AdGuard Home service" /etc/init.d/adguardhome disable
else
    log_step "Service not running" true
fi

# 2. Remove Package (No internet needed, local removal)
if opkg list-installed | grep -q adguardhome; then
    log_step "Removing AdGuard Home package" opkg remove adguardhome
else
    log_step "Package not installed, skipping removal" true
fi

# 3. Revert Dnsmasq-full
log_step "Reverting Dnsmasq-full to port 53" uci set dhcp.@dnsmasq[0].port='53'

# CRITICAL FIX: Re-enable ISP DNS usage so internet works after uninstall
log_step "Re-enabling ISP DNS resolving" uci -q delete dhcp.@dnsmasq[0].noresolv

log_step "Committing DHCP changes" uci commit dhcp

# 4. Remove Firewall Rule
if uci get firewall.AdGuardHomeWeb >/dev/null 2>&1; then
    log_step "Removing Firewall rules" uci delete firewall.AdGuardHomeWeb
    log_step "Committing Firewall changes" uci commit firewall
else
    log_step "Firewall rule already removed" true
fi

# 5. Clean Files
cleanup_files() {
    rm -f /etc/adguardhome.yaml
    rm -rf /var/adguardhome
    rm -rf /usr/bin/AdGuardHome
}
log_step "Cleaning up configuration and data files" cleanup_files

# 6. Restart Services
log_step "Restarting Dnsmasq-full (Restoring Network)" /etc/init.d/dnsmasq restart
log_step "Restarting Firewall" /etc/init.d/firewall restart

echo -e "\n${GREEN}Uninstallation Complete.${NC}"
echo "System restored to default Passwall/Dnsmasq state."
