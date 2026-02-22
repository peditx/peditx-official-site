cat << 'EOF' > /tmp/setup.sh
#!/bin/sh
echo "------------------------------------------------"
echo "  Starting PeDitXOS Repository Migration... "
echo "------------------------------------------------"

# --- 0. Network & IPv6 Fix ---
# Temporarily disable IPv6 to prevent blackhole/hangs during opkg downloads
if [ -f /proc/sys/net/ipv6/conf/all/disable_ipv6 ]; then
    sysctl -w net.ipv6.conf.all.disable_ipv6=1 > /dev/null 2>&1
fi

# --- 1. Restore & Fix Official OpenWRT Feeds ---
# Using the custom ArvanCloud proxy domain since the origin settings are fixed (No HTTPS redirects)
if [ -f /rom/etc/opkg/distfeeds.conf ]; then
    cp /rom/etc/opkg/distfeeds.conf /etc/opkg/distfeeds.conf
fi
sed -i 's|https://downloads.openwrt.org|http://peditxrepo.ir/openwrt|g' /etc/opkg/distfeeds.conf
sed -i 's|http://downloads.openwrt.org|http://peditxrepo.ir/openwrt|g' /etc/opkg/distfeeds.conf

# Install curl and ca-bundle now that base feeds are strictly HTTP
echo "Preparing base packages (curl, ca-bundle) for secure downloads..."
opkg update > /dev/null 2>&1
opkg install curl ca-bundle > /dev/null 2>&1

# --- 2. Smart Cleanup for Custom Feeds ---
if [ ! -f /etc/opkg/customfeeds.conf ]; then
    touch /etc/opkg/customfeeds.conf
fi
sed -i '/peditxdl.ir/d' /etc/opkg/customfeeds.conf
sed -i '/repo.peditxos.ir/d' /etc/opkg/customfeeds.conf
sed -i '/peditxrepo.ir/d' /etc/opkg/customfeeds.conf
sed -i '/peditxos_passwall/d' /etc/opkg/customfeeds.conf

# --- 3. Extract release and architecture safely ---
if [ -f /etc/openwrt_release ]; then
    . /etc/openwrt_release
    release=${DISTRIB_RELEASE%.*}
    arch=$DISTRIB_ARCH
else
    release="unknown"
    arch="unknown"
fi

# --- 4. Add Passwall feeds ---
BASE_URL="http://peditxrepo.ir/openwrt-passwall-build/releases/packages-$release/$arch"

echo "src/gz peditxos_passwall_luci $BASE_URL/passwall_luci" >> /etc/opkg/customfeeds.conf
echo "src/gz peditxos_passwall_pkgs $BASE_URL/passwall_packages" >> /etc/opkg/customfeeds.conf
echo "src/gz peditxos_passwall2 $BASE_URL/passwall2" >> /etc/opkg/customfeeds.conf

# --- 5. Update Key (IPv4 forced, size check) ---
echo "Downloading Passwall repository key..."
rm -f /tmp/passwall.pub
if command -v curl >/dev/null 2>&1; then
    curl -4 -k -sS -L -o /tmp/passwall.pub http://peditxrepo.ir/openwrt-passwall-build/passwall.pub
else
    wget -4 --no-check-certificate -qO /tmp/passwall.pub http://peditxrepo.ir/openwrt-passwall-build/passwall.pub
fi

if [ -s /tmp/passwall.pub ]; then
    opkg-key add /tmp/passwall.pub > /dev/null 2>&1
    echo "Key added successfully."
else
    echo "------------------------------------------------"
    echo "  ERROR: Failed to download the key or file is empty! "
    echo "  Check your network. Aborting."
    echo "------------------------------------------------"
    [ -f /proc/sys/net/ipv6/conf/all/disable_ipv6 ] && sysctl -w net.ipv6.conf.all.disable_ipv6=0 > /dev/null 2>&1
    exit 1
fi

# --- 6. Final OPKG Update ---
echo "Updating package lists (please wait)..."
# Now that ca-bundle is installed & IPv6 is disabled, opkg can follow HTTPS redirects flawlessly!
if opkg update; then
    echo "------------------------------------------------"
    echo "  SUCCESS: Migrated to PeDitXOS Repository! "
    echo "  System is now fully updated and clean. "
    echo "------------------------------------------------"
else
    echo "------------------------------------------------"
    echo "  FAILED: opkg update encountered errors! "
    echo "  Please check the log above to see what went wrong. "
    echo "------------------------------------------------"
fi

# --- 7. Re-enable IPv6 ---
if [ -f /proc/sys/net/ipv6/conf/all/disable_ipv6 ]; then
    sysctl -w net.ipv6.conf.all.disable_ipv6=0 > /dev/null 2>&1
fi
EOF

sh /tmp/setup.sh && rm /tmp/setup.sh
