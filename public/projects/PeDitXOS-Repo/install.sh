cat << 'EOF' > /tmp/setup.sh
#!/bin/sh
echo "------------------------------------------------"
echo "  Starting PeDitXOS Repository Migration... "
echo "------------------------------------------------"

# 1. Cleanup old traces
sed -i '/peditxdl.ir/d' /etc/opkg/distfeeds.conf
sed -i '/peditxdl.ir/d' /etc/opkg/customfeeds.conf
sed -i '/peditxrepo.ir/d' /etc/opkg/customfeeds.conf

# 2. Set main feeds to Arvan proxy
sed -i 's|https://downloads.openwrt.org|http://peditxrepo.ir/openwrt|g' /etc/opkg/distfeeds.conf

# 3. Add Passwall feeds (Edited to use SourceForge via Arvan Proxy)
read release arch << EOX
$(. /etc/openwrt_release ; echo ${DISTRIB_RELEASE%.*} $DISTRIB_ARCH)
EOX
# فیدها مطابق سورس اصلی (passwall_packages و passwall2)
for feed in passwall_packages passwall2; do
  echo "src/gz $feed http://peditxrepo.ir/openwrt-passwall-build/releases/packages-$release/$arch/$feed" >> /etc/opkg/customfeeds.conf
done

# 4. Update Key & OPKG (Edited to get key from SourceForge via Arvan Proxy)
wget -qO /tmp/passwall.pub http://peditxrepo.ir/openwrt-passwall-build/passwall.pub && opkg-key add /tmp/passwall.pub > /dev/null 2>&1

echo "Updating package lists (please wait)..."
opkg update > /dev/null 2>&1

echo "------------------------------------------------"
echo "  SUCCESS: Migrated to PeDitXOS Repository! "
echo "  Source: Official Passwall via Arvan Proxy "
echo "------------------------------------------------"
EOF

sh /tmp/setup.sh && rm /tmp/setup.sh
