cat << 'EOF' > /tmp/uninstall.sh
#!/bin/sh
echo "------------------------------------------------"
echo "  Uninstalling PeDitXOS Repository... "
echo "  Restoring Original Settings (peditxdl.ir) "
echo "------------------------------------------------"

# 1. Load system variables
. /etc/openwrt_release
ARCH=$DISTRIB_ARCH

# 2. Complete Rebuild of distfeeds.conf (Safe Way)
# Restore official OpenWrt HTTPS links
cat << EOX > /etc/opkg/distfeeds.conf
src/gz openwrt_core https://downloads.openwrt.org/releases/$DISTRIB_RELEASE/targets/$DISTRIB_TARGET/packages
src/gz openwrt_base https://downloads.openwrt.org/releases/$DISTRIB_RELEASE/packages/$ARCH/base
src/gz openwrt_luci https://downloads.openwrt.org/releases/$DISTRIB_RELEASE/packages/$ARCH/luci
src/gz openwrt_packages https://downloads.openwrt.org/releases/$DISTRIB_RELEASE/packages/$ARCH/packages
src/gz openwrt_routing https://downloads.openwrt.org/releases/$DISTRIB_RELEASE/packages/$ARCH/routing
src/gz openwrt_telephony https://downloads.openwrt.org/releases/$DISTRIB_RELEASE/packages/$ARCH/telephony
EOX

# 3. Restore Passwall feeds to Original Domain (peditxdl.ir)
# First cleanup, then add original links
sed -i '/peditxrepo.ir/d' /etc/opkg/customfeeds.conf
sed -i '/peditxdl.ir/d' /etc/opkg/customfeeds.conf

RELEASE_NUM=${DISTRIB_RELEASE%.*}
for feed in passwall_luci passwall_packages passwall2; do
  echo "src/gz $feed https://repo.peditxdl.ir/passwall-packages/releases/packages-$RELEASE_NUM/$ARCH/$feed" >> /etc/opkg/customfeeds.conf
done

# 4. Restore Original Security Key
echo "Restoring Original Security Key..."
wget -qO /tmp/passwall.pub https://repo.peditxdl.ir/passwall-packages/passwall.pub
if [ $? -eq 0 ]; then
    opkg-key add /tmp/passwall.pub > /dev/null 2>&1
    echo "Key restored successfully."
fi

echo "Updating package lists... (Please wait)"
opkg update > /dev/null 2>&1

echo "------------------------------------------------"
echo "  SUCCESS: Reverted to peditxdl.ir "
echo "  System is now in its original safe state. "
echo "------------------------------------------------"
EOF

sh /tmp/uninstall.sh && rm /tmp/uninstall.sh
