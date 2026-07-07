#!/bin/sh
# PeDitXOS - Network Optimizations
echo "Applying Network optimizations..."
if command -v apk >/dev/null 2>&1; then
    apk update && apk install kmod-tcp-bbr
elif command -v opkg >/dev/null 2>&1; then
    opkg update && opkg install kmod-tcp-bbr
fi
sysctl -w net.ipv4.tcp_fastopen=3
sysctl -w net.ipv4.tcp_congestion_control=bbr
echo "Network optimizations applied."
