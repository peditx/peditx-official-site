#!/bin/sh
# PeDitXOS - Install Sing-Box
echo "=== Installing Sing-Box ==="
if command -v apk >/dev/null 2>&1; then
    apk update && apk install sing-box
elif command -v opkg >/dev/null 2>&1; then
    opkg update && opkg install sing-box
else
    echo "ERROR: No package manager found."
    exit 1
fi
echo "=== Sing-Box Installation Complete ==="
