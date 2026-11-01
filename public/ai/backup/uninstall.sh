#!/bin/sh
# Removes PeDitX-AI from an OpenWrt/PeDitXOS router. Idempotent.
# Keeps the assistant's own data in /root/.config and /root/.local/state.
set -eu

BASE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)

if [ "$(id -u)" -ne 0 ]; then
    echo "Run the uninstaller as root over SSH." >&2
    exit 2
fi

if [ ! -r /etc/openwrt_release ] && [ ! -r /etc/openwrt_version ]; then
    echo "This uninstaller targets OpenWrt/PeDitXOS only." >&2
    exit 2
fi

if [ -f "$BASE/luci-app-peditx-ai/uninstall.sh" ]; then
    sh "$BASE/luci-app-peditx-ai/uninstall.sh"
fi

if [ -x /etc/init.d/peditx-ai ]; then
    /etc/init.d/peditx-ai stop 2>/dev/null || true
    /etc/init.d/peditx-ai disable 2>/dev/null || true
    rm -f /etc/init.d/peditx-ai
fi

rm -rf /opt/peditx-ai /usr/bin/assist /var/run/peditx-ai

if uci -q get firewall.peditx_ai_wan >/dev/null 2>&1; then
    uci -q delete firewall.peditx_ai_wan
    uci -q commit firewall
    /etc/init.d/firewall reload >/dev/null 2>&1 || true
fi

rm -rf /tmp/luci-modulecache/* 2>/dev/null || true
rm -f /tmp/luci-indexcache* 2>/dev/null || true
/etc/init.d/rpcd restart

echo "PeDitX-AI removed."
echo "Kept: /root/.config/peditx-ai and /root/.local/state/peditx-ai"
echo "Delete them yourself if you want the settings and conversations gone too."
