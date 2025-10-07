#!/bin/sh

# DNS Jumper - Uninstaller Script
echo ">>> Uninstalling DNS Jumper..."

# --- 1. Remove created files ---
echo ">>> Removing main files..."
rm -f /usr/lib/lua/luci/controller/dnsjumper.lua
rm -f /etc/config/dns_jumper_list.json
rm -f /etc/config/dns_jumper_cache.json

# --- 2. Remove the view directory and its contents ---
echo ">>> Removing view directory..."
rm -rf /usr/lib/lua/luci/view/dnsjumper

# --- 3. Remove temporary log files ---
echo ">>> Cleaning up temporary files..."
rm -f /tmp/dnsjumper_log_tail.pid
rm -f /tmp/dnsjumper_live_log.txt

# --- 4. Clear LuCI cache to reflect changes ---
echo ">>> Clearing LuCI cache..."
rm -f /tmp/luci-indexcache

echo ""
echo ">>> DNS Jumper has been successfully uninstalled."
echo ">>> You may need to reboot your router for all changes to take full effect."
echo ""

exit 0
