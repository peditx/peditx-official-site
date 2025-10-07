#!/bin/sh

# PXNotifier - Uninstaller Script
echo ">>> Uninstalling PXNotifier..."

# --- 1. Remove the cron job ---
echo ">>> Removing cron job..."
(crontab -l 2>/dev/null | grep -v "/usr/bin/monitor_passwall.sh") | crontab -

# --- 2. Remove the backend monitor script ---
echo ">>> Removing backend script..."
rm -f /usr/bin/monitor_passwall.sh

# --- 3. Remove LuCI files ---
echo ">>> Removing LuCI files..."
rm -f /usr/lib/lua/luci/controller/pxnotifier.lua
rm -f /usr/lib/lua/luci/model/cbi/peditxos/pxnotifier.lua

# --- 4. Remove UCI configuration file ---
echo ">>> Removing UCI configuration..."
rm -f /etc/config/pxnotifier

# --- 5. Remove temporary status file ---
echo ">>> Removing temporary files..."
rm -f /tmp/passwall_last_status.log

# --- 6. Attempt to clean up empty directories ---
# This will only remove the directory if it's empty, so it's safe.
echo ">>> Cleaning up directories..."
rmdir /usr/lib/lua/luci/model/cbi/peditxos >/dev/null 2>&1

# --- 7. Clear LuCI cache to reflect UI changes ---
echo ">>> Clearing LuCI cache..."
rm -rf /tmp/luci-cache/*
rm -f /tmp/luci-indexcache

echo ""
echo ">>> PXNotifier has been successfully uninstalled."
echo ">>> Please log out and log back into LuCI to see the changes."
echo ""

exit 0
