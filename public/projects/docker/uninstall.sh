#!/bin/sh
# ============================================================
#  Docker — PeDitXOS standalone uninstaller
#  Removes only the paths this installer created. Never globs.
# ============================================================

APP_NAME="docker"
APP_TITLE="Docker"

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

# --- Containers then daemon ---------------------------------------
if command -v docker >/dev/null 2>&1; then
	RUNNING=$(docker ps -q 2>/dev/null)
	if [ -n "$RUNNING" ]; then
		echo "   - Stopping running containers..."
		# shellcheck disable=SC2086
		docker stop $RUNNING >/dev/null 2>&1
	fi
fi

if [ -f /etc/init.d/dockerd ]; then
	/etc/init.d/dockerd stop >/dev/null 2>&1
	/etc/init.d/dockerd disable >/dev/null 2>&1
	echo "   - Docker service stopped."
fi

# --- Packages -------------------------------------------------------
if [ -n "$PKG_REMOVE" ]; then
	$PKG_REMOVE luci-app-dockerman docker-compose dockerd kmod-veth >/dev/null 2>&1 		|| $PKG_REMOVE docker-compose dockerd kmod-veth >/dev/null 2>&1
	echo "   - Packages removed."
fi

# --- Bridge interface -------------------------------------------------
ip link delete docker0 >/dev/null 2>&1
echo "   - docker0 removed."

# --- LuCI files owned by this installer ------------------------
rm -f  "/usr/share/luci/menu.d/luci-app-${APP_NAME}.json"
rm -f  "/usr/share/rpcd/acl.d/luci-app-${APP_NAME}.json"
rm -rf "/www/luci-static/resources/view/${APP_NAME}"
rm -f  "/usr/bin/${APP_NAME}-backend.sh"
echo "   - LuCI page removed."

# --- files left by the previous (Lua) version -------------------
# (no Lua files from a previous version)

# --- rpcd re-reads acl.d; ucode LuCI caches ---------------------
/etc/init.d/rpcd reload >/dev/null 2>&1
rm -f /tmp/luci-indexcache /tmp/luci-sessions/.root 2>/dev/null
rm -rf /tmp/luci-modulecache 2>/dev/null

echo "Note: image and volume data under /opt or /mnt was NOT deleted."

echo ">>> ${APP_TITLE} removed. Refresh your browser (and log out/in if the menu lingers)."
echo "------------------------------------------"
