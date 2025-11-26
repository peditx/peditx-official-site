#!/bin/sh

# =======================================================
# OpenWrt OpenVPN + SOCKS5 (Port 2012) Setup Script
# =======================================================

echo ">>> [1/5] Updating package lists..."
if opkg update >/dev/null 2>&1; then
    echo "✔ Package lists updated successfully."
else
    echo "✘ Error: Failed to update package lists. Check internet connection."
    exit 1
fi

echo ">>> [2/5] Installing OpenVPN, Luci App, and dependencies..."
# Installing silently
if opkg install openvpn-openssl luci-app-openvpn curl wget-ssl resolveip >/dev/null 2>&1; then
    echo "✔ OpenVPN packages installed successfully."
else
    echo "✘ Error: Failed to install OpenVPN packages."
    exit 1
fi

echo ">>> [3/5] Installing Microsocks to act as SOCKS5 Server on Port 2012..."
if opkg install microsocks >/dev/null 2>&1; then
    # Silently configuring Microsocks
    {
        uci set microsocks.@microsocks[0]=microsocks
        uci set microsocks.@microsocks[0].enabled='1'
        uci set microsocks.@microsocks[0].port='2012'
        uci set microsocks.@microsocks[0].listenip='127.0.0.1'
        uci commit microsocks
        /etc/init.d/microsocks enable
        /etc/init.d/microsocks restart
    } >/dev/null 2>&1
    
    echo "✔ Microsocks is running on 127.0.0.1:2012"
else
    echo "✘ Error: Microsocks package not found. SOCKS5 setup failed."
fi

echo ">>> [4/5] Configuring Passwall/Passwall2 Node..."

# =======================================================
# User provided Logic for Passwall Configuration (Silent)
# =======================================================

if uci show passwall2 >/dev/null 2>&1; then
    {
        uci set passwall2.ovpnnode=nodes
        uci set passwall2.ovpnnode.remarks='OpenVPN'
        uci set passwall2.ovpnnode.type='Xray'
        uci set passwall2.ovpnnode.protocol='socks'
        uci set passwall2.ovpnnode.server='127.0.0.1'
        uci set passwall2.ovpnnode.port='2012'
        uci set passwall2.ovpnnode.address='127.0.0.1'
        uci set passwall2.ovpnnode.tls='0'
        uci set passwall2.ovpnnode.transport='tcp'
        uci set passwall2.ovpnnode.tcp_guise='none'
        uci set passwall2.ovpnnode.tcpMptcp='0'
        uci set passwall2.ovpnnode.tcpNoDelay='0'
        uci commit passwall2
    } >/dev/null 2>&1
    echo "✔ Passwall2 configured with detailed settings."

elif uci show passwall >/dev/null 2>&1; then
    {
        uci set passwall.ovpnnode=nodes
        uci set passwall.ovpnnode.remarks='OpenVPN'
        uci set passwall.ovpnnode.type='Xray'
        uci set passwall.ovpnnode.protocol='socks'
        uci set passwall.ovpnnode.server='127.0.0.1'
        uci set passwall.ovpnnode.port='2012'
        uci set passwall.ovpnnode.address='127.0.0.1'
        uci set passwall.ovpnnode.tls='0'
        uci set passwall.ovpnnode.transport='tcp'
        uci set passwall.ovpnnode.tcp_guise='none'
        uci set passwall.ovpnnode.tcpMptcp='0'
        uci set passwall.ovpnnode.tcpNoDelay='0'
        uci commit passwall
    } >/dev/null 2>&1
    echo "✔ Passwall configured with detailed settings."

else
    echo "! Warning: Neither Passwall nor Passwall2 found. Node configuration skipped."
fi

echo ">>> [5/5] Setup Complete. Made by PeDitX"
