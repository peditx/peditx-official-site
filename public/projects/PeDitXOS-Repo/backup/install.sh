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

# 3. Add Passwall feeds
read release arch << EOX
$(. /etc/openwrt_release ; echo ${DISTRIB_RELEASE%.*} $DISTRIB_ARCH)
EOX
for feed in passwall_luci passwall_packages passwall2; do
  echo "src/gz $feed http://peditxrepo.ir/passwall-packages/releases/packages-$release/$arch/$feed" >> /etc/opkg/customfeeds.conf
done

# 4. Update Key & OPKG
wget -qO /tmp/passwall.pub http://peditxrepo.ir/passwall-packages/passwall.pub && opkg-key add /tmp/passwall.pub > /dev/null 2>&1

echo "Updating package lists (please wait)..."
opkg update > /dev/null 2>&1

echo "------------------------------------------------"
echo "  SUCCESS: Migrated to PeDitXOS Repository! "
echo "  You can now install your packages. "
echo "------------------------------------------------"
EOF

sh /tmp/setup.sh && rm /tmp/setup.sh
