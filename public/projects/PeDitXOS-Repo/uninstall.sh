cat << 'EOF' > /tmp/uninstall.sh
#!/bin/sh
echo "------------------------------------------------"
echo "  Uninstalling PeDitXOS Repo (Worker Proxy)... "
echo "  Restoring Original Settings (peditxdl.ir) "
echo "------------------------------------------------"

# ۱. بارگذاری متغیرهای سیستم
. /etc/openwrt_release
ARCH=$DISTRIB_ARCH
RELEASE_NUM=${DISTRIB_RELEASE%.*}

# ۲. بازسازی کامل distfeeds.conf به حالت استاندارد (HTTPS)
# حذف پروکسی و بازگشت به سرورهای رسمی OpenWrt
cat << EOX > /etc/opkg/distfeeds.conf
src/gz openwrt_core https://downloads.openwrt.org/releases/$DISTRIB_RELEASE/targets/$DISTRIB_TARGET/packages
src/gz openwrt_base https://downloads.openwrt.org/releases/$DISTRIB_RELEASE/packages/$ARCH/base
src/gz openwrt_luci https://downloads.openwrt.org/releases/$DISTRIB_RELEASE/packages/$ARCH/luci
src/gz openwrt_packages https://downloads.openwrt.org/releases/$DISTRIB_RELEASE/packages/$ARCH/packages
src/gz openwrt_routing https://downloads.openwrt.org/releases/$DISTRIB_RELEASE/packages/$ARCH/routing
src/gz openwrt_telephony https://downloads.openwrt.org/releases/$DISTRIB_RELEASE/packages/$ARCH/telephony
EOX

# ۳. پاکسازی دامین‌های جدید و موقت از customfeeds
sed -i '/repo.peditxos.ir/d' /etc/opkg/customfeeds.conf
sed -i '/peditxrepo.ir/d' /etc/opkg/customfeeds.conf
sed -i '/peditxdl.ir/d' /etc/opkg/customfeeds.conf

# ۴. بازگرداندن فیدهای Passwall به دامین اصلی (peditxdl.ir)
# مطابق آدرسی که دادی: repo.peditxdl.ir/passwall-packages/
BASE_ORIGIN="https://repo.peditxdl.ir/passwall-packages/releases/packages-$RELEASE_NUM/$ARCH"

echo "src/gz passwall_luci $BASE_ORIGIN/passwall_luci" >> /etc/opkg/customfeeds.conf
echo "src/gz passwall_packages $BASE_ORIGIN/passwall_packages" >> /etc/opkg/customfeeds.conf
echo "src/gz passwall2 $BASE_ORIGIN/passwall2" >> /etc/opkg/customfeeds.conf

# ۵. بازگرداندن کلید امنیتی اصلی از دامین قبلی
echo "Restoring Original Security Key..."
wget -qO /tmp/passwall.pub https://repo.peditxdl.ir/passwall-packages/passwall.pub
if [ $? -eq 0 ]; then
    opkg-key add /tmp/passwall.pub > /dev/null 2>&1
    echo "Key restored successfully."
else
    echo "Warning: Could not fetch the original key from peditxdl.ir"
fi

echo "Updating package lists... (Please wait)"
opkg update > /dev/null 2>&1

echo "------------------------------------------------"
echo "  SUCCESS: Reverted to repo.peditxdl.ir "
echo "  System is now back to your original repository. "
echo "------------------------------------------------"
EOF

sh /tmp/uninstall.sh && rm /tmp/uninstall.sh
