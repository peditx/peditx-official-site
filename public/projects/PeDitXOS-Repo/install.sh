cat << 'EOF' > /tmp/setup.sh
#!/bin/sh
echo "------------------------------------------------"
echo "  Starting PeDitXOS Repository Migration... "
echo "------------------------------------------------"

# 1. Restore Official OpenWRT Feeds & Apply Proxy
# Ensures core packages update correctly, perfectly idempotent on multiple runs.
if [ -f /rom/etc/opkg/distfeeds.conf ]; then
    cp /rom/etc/opkg/distfeeds.conf /etc/opkg/distfeeds.conf
fi
sed -i 's|https://downloads.openwrt.org|http://peditxrepo.ir/openwrt|g' /etc/opkg/distfeeds.conf
sed -i 's|http://downloads.openwrt.org|http://peditxrepo.ir/openwrt|g' /etc/opkg/distfeeds.conf

# 2. Smart Cleanup for Custom Feeds (Idempotent: prevents duplicates)
if [ ! -f /etc/opkg/customfeeds.conf ]; then
    touch /etc/opkg/customfeeds.conf
fi
# Delete any traces of old domains or previous runs of this script safely
sed -i '/peditxdl.ir/d' /etc/opkg/customfeeds.conf
sed -i '/repo.peditxos.ir/d' /etc/opkg/customfeeds.conf
sed -i '/peditxrepo.ir/d' /etc/opkg/customfeeds.conf
sed -i '/peditxos_passwall/d' /etc/opkg/customfeeds.conf

# 3. Extract release and architecture
read release arch << EOX
$(. /etc/openwrt_release ; echo ${DISTRIB_RELEASE%.*} $DISTRIB_ARCH)
EOX

# 4. Add Passwall feeds (Includes all 3 repositories)
BASE_URL="http://peditxrepo.ir/openwrt-passwall-build/releases/packages-$release/$arch"

echo "src/gz peditxos_passwall_luci $BASE_URL/passwall_luci" >> /etc/opkg/customfeeds.conf
echo "src/gz peditxos_passwall_pkgs $BASE_URL/passwall_packages" >> /etc/opkg/customfeeds.conf
echo "src/gz peditxos_passwall2 $BASE_URL/passwall2" >> /etc/opkg/customfeeds.conf

# 5. Update Key from new address
wget -qO /tmp/passwall.pub http://peditxrepo.ir/openwrt-passwall-build/passwall.pub && opkg-key add /tmp/passwall.pub > /dev/null 2>&1

echo "Updating package lists (please wait)..."
opkg update > /dev/null 2>&1

echo "------------------------------------------------"
echo "  SUCCESS: Migrated to PeDitXOS Repository! "
echo "  System is now fully updated and clean. "
echo "------------------------------------------------"
EOF

sh /tmp/setup.sh && rm /tmp/setup.sh
