#!/bin/sh
# PeDitX-AI single-file uninstaller for OpenWrt/PeDitXOS
# Usage: sh uninstall-peditx-ai.sh  (run as root over SSH)
# Keeps user data in /root/.config/peditx-ai and /root/.local/state/peditx-ai
set -eu

if [ "$(id -u)" -ne 0 ]; then
    echo "ERROR: Run as root over SSH." >&2; exit 2
fi
if [ ! -r /etc/openwrt_release ] && [ ! -r /etc/openwrt_version ]; then
    echo "ERROR: Targets OpenWrt/PeDitXOS only." >&2; exit 2
fi

# Stop and disable service
if [ -x /etc/init.d/peditx-ai ]; then
    /etc/init.d/peditx-ai stop 2>/dev/null || true
    /etc/init.d/peditx-ai disable 2>/dev/null || true
    rm -f /etc/init.d/peditx-ai
fi

# Remove LuCI integration
rm -f /usr/share/luci/menu.d/peditx-ai.json
rm -f /usr/share/rpcd/acl.d/peditx-ai.json
rm -f /www/luci-static/resources/view/peditx-ai/main.js
rmdir /www/luci-static/resources/view/peditx-ai 2>/dev/null || true

# Remove UCI config
rm -f /etc/config/peditx_ai

# Remove app files
rm -rf /opt/peditx-ai
rm -f /usr/bin/assist
rm -rf /var/run/peditx-ai

# Remove firewall rule
if uci -q get firewall.peditx_ai_wan >/dev/null 2>&1; then
    uci -q delete firewall.peditx_ai_wan
    uci -q commit firewall
    /etc/init.d/firewall reload >/dev/null 2>&1 || true
fi

# Clear LuCI caches
rm -rf /tmp/luci-modulecache/* 2>/dev/null || true
rm -f /tmp/luci-indexcache* 2>/dev/null || true
/etc/init.d/rpcd restart 2>/dev/null || true

echo ""
echo "========================================"
echo "  PeDitX-AI removed successfully."
echo "========================================"
echo "  Kept (delete manually if you want):"
echo "    /root/.config/peditx-ai"
echo "    /root/.local/state/peditx-ai"
echo "========================================"
