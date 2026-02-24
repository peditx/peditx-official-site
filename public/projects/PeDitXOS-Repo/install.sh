cat << 'EOF' > /tmp/setup.sh
#!/bin/sh
echo "------------------------------------------------"
echo "  Starting PeDitXOS Repository Migration... "
echo "------------------------------------------------"

# 1. Restore Official OpenWRT Feeds & Apply Proxy
if [ -f /rom/etc/opkg/distfeeds.conf ]; then
    cp /rom/etc/opkg/distfeeds.conf /etc/opkg/distfeeds.conf
fi
sed -i 's|https://downloads.openwrt.org|http://peditxrepo.ir/openwrt|g' /etc/opkg/distfeeds.conf
sed -i 's|http://downloads.openwrt.org|http://peditxrepo.ir/openwrt|g' /etc/opkg/distfeeds.conf

# 2. Smart Cleanup for Custom Feeds
if [ ! -f /etc/opkg/customfeeds.conf ]; then
    touch /etc/opkg/customfeeds.conf
fi
sed -i '/peditxdl.ir/d' /etc/opkg/customfeeds.conf
sed -i '/repo.peditxos.ir/d' /etc/opkg/customfeeds.conf
sed -i '/peditxrepo.ir/d' /etc/opkg/customfeeds.conf
sed -i '/peditxos_passwall/d' /etc/opkg/customfeeds.conf

# 3. Extract release and architecture Safely
if [ -f /etc/openwrt_release ]; then
    . /etc/openwrt_release
    release=${DISTRIB_RELEASE%.*}
    arch=$DISTRIB_ARCH
else
    release="23.05"
    arch="x86_64"
fi

# 4. Add Passwall feeds
BASE_URL="http://peditxrepo.ir/openwrt-passwall-build/releases/packages-$release/$arch"

echo "src/gz peditxos_passwall_luci $BASE_URL/passwall_luci" >> /etc/opkg/customfeeds.conf
echo "src/gz peditxos_passwall_pkgs $BASE_URL/passwall_packages" >> /etc/opkg/customfeeds.conf
echo "src/gz peditxos_passwall2 $BASE_URL/passwall2" >> /etc/opkg/customfeeds.conf

# 5. Optimize opkg to prevent hangs & signature errors
if [ -f /etc/opkg.conf ]; then
    sed -i 's/option check_signature/# option check_signature/g' /etc/opkg.conf
    sed -i '/option connect_timeout/d' /etc/opkg.conf
    echo "option connect_timeout 20" >> /etc/opkg.conf
    sed -i '/option download_timeout/d' /etc/opkg.conf
    echo "option download_timeout 20" >> /etc/opkg.conf
fi

# 6. Update Key
wget -qO /tmp/passwall.pub http://peditxrepo.ir/openwrt-passwall-build/passwall.pub && opkg-key add /tmp/passwall.pub > /dev/null 2>&1

# 7. Update package lists
echo "Updating package lists (please wait)..."
rm -rf /var/opkg-lists/*
opkg update

echo "------------------------------------------------"
echo "  SUCCESS: Migrated to PeDitXOS Repository! "
echo "  System is now fully updated and clean. "
echo "------------------------------------------------"
EOF

sh /tmp/setup.sh && rm /tmp/setup.sh
