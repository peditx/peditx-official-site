#!/bin/sh
# ============================================================
#  Portainer — PeDitXOS standalone uninstaller
#  Removes only the paths this installer created. Never globs.
# ============================================================

APP_NAME="portainer"
APP_TITLE="Portainer"

if command -v apk >/dev/null 2>&1; then
	PKG="apk"
	PKG_REMOVE="apk del"
elif command -v opkg >/dev/null 2>&1; then
	PKG="opkg"
	PKG_REMOVE="opkg remove"
else
	PKG=""
	PKG_REMOVE=""
fi

PKG_INSTALLED() {
	if [ "$PKG" = "apk" ]; then
		apk info -e "$1" >/dev/null 2>&1
	elif [ "$PKG" = "opkg" ]; then
		opkg status "$1" 2>/dev/null | grep -q '^Status:.*installed'
	else
		return 1
	fi
}

echo
echo ">>> Removing ${APP_TITLE}..."

# --- Container ---------------------------------------------------
if command -v docker >/dev/null 2>&1; then
	if docker ps -a --format '{{.Names}}' | grep -qx "portainer"; then
		docker stop "portainer" >/dev/null 2>&1
		docker rm "portainer" >/dev/null 2>&1
		echo "   - Container removed."
	else
		echo "   - Container not found."
	fi
else
	echo "   - Docker not installed, nothing to remove."
fi

# --- Firewall rules --------------------------------------------
FOUND=0
for rule in $(uci show firewall | grep -E "name='(Allow_Portainer)" | cut -d. -f2 | cut -d= -f1 | sort -u); do
	uci -q delete firewall.$rule
	FOUND=1
done
if [ "$FOUND" = "1" ]; then
	uci -q commit firewall
	/etc/init.d/firewall restart >/dev/null 2>&1
	echo "   - Firewall rules removed."
else
	echo "   - No firewall rules found."
fi

# --- LuCI files owned by this installer ------------------------
rm -f  "/usr/share/luci/menu.d/luci-app-${APP_NAME}.json"
rm -f  "/usr/share/rpcd/acl.d/luci-app-${APP_NAME}.json"
rm -rf "/www/luci-static/resources/view/${APP_NAME}"
rm -f  "/usr/bin/${APP_NAME}-backend.sh"
echo "   - LuCI page removed."

# --- files left by the previous (Lua) version -------------------
rm -f /usr/lib/lua/luci/controller/peditxos_portainer.lua
rm -f /usr/lib/lua/luci/view/peditxos/portainer.htm
rmdir /usr/lib/lua/luci/view/peditxos 2>/dev/null

# --- rpcd re-reads acl.d; ucode LuCI caches ---------------------
/etc/init.d/rpcd reload >/dev/null 2>&1
rm -f /tmp/luci-indexcache /tmp/luci-sessions/.root 2>/dev/null
rm -rf /tmp/luci-modulecache 2>/dev/null

echo "Note: the portainer_data volume was NOT deleted."

echo ">>> ${APP_TITLE} removed. Refresh your browser (and log out/in if the menu lingers)."
echo "------------------------------------------"
