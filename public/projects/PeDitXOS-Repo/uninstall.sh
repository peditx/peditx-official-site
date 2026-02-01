cat << 'EOF' > /tmp/uninstall.sh
#!/bin/sh
echo "------------------------------------------------"
echo "  Uninstalling PeDitXOS Repository... "
echo "  Restoring official OpenWrt feeds... "
echo "------------------------------------------------"

# 1. Capture the current release and arch to rebuild the official links
. /etc/openwrt_release
RELEASE_NUM=${DISTRIB_RELEASE%.*}
ARCH=$DISTRIB_ARCH

# 2. Complete Rebuild of distfeeds.conf (The Safe Way)
# This will overwrite the file with official HTTPS links
cat << EOX > /etc/opkg/distfeeds.conf
src/gz openwrt_core https://downloads.openwrt.org/releases/$DISTRIB_RELEASE/targets/$DISTRIB_TARGET/packages
src/gz openwrt_base https://downloads.openwrt.org/releases/$DISTRIB_RELEASE/packages/$ARCH/base
src/gz openwrt_luci https://downloads.openwrt.org/releases/$DISTRIB_RELEASE/packages/$ARCH/luci
src/gz openwrt_packages https://downloads.openwrt.org/releases/$DISTRIB_RELEASE/packages/$ARCH/packages
src/gz openwrt_routing https://downloads.openwrt.org/releases/$DISTRIB_RELEASE/packages/$ARCH/routing
src/gz openwrt_telephony https://downloads.openwrt.org/releases/$DISTRIB_RELEASE/packages/$ARCH/telephony
EOX

# 3. Cleanup custom feeds from any PeDitX traces
sed -i '/peditxdl.ir/d' /etc/opkg/customfeeds.conf
sed -i '/peditxrepo.ir/d' /etc/opkg/customfeeds.conf

# 4. Remove the security key
rm -f /etc/opkg/keys/passwall.pub

echo "Updating package lists from official servers..."
# Use -v to see what's happening if it fails
opkg update

echo "------------------------------------------------"
echo "  SUCCESS: Reverted to Official Repository. "
echo "  Standard feeds have been restored. "
echo "------------------------------------------------"
EOF

sh /tmp/uninstall.sh && rm /tmp/uninstall.sh
