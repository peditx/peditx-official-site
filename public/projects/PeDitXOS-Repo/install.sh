cat << 'EOF' > /tmp/setup.sh
#!/bin/sh
echo "------------------------------------------------"
echo "  Fixing PeDitXOS Repository Paths... "
echo "------------------------------------------------"

# ۱. پاکسازی
sed -i '/peditxdl.ir/d' /etc/opkg/*.conf
sed -i '/peditxrepo.ir/d' /etc/opkg/*.conf
sed -i '/repo.peditxos.ir/d' /etc/opkg/*.conf

# ۲. اصلاح فیدهای اصلی (OpenWrt Official)
# نکته: آدرس رو جوری ست می‌کنیم که مستقیم به دایرکتوری اصلی وصل بشه
sed -i 's|https://downloads.openwrt.org/releases|http://repo.peditxos.ir/openwrt|g' /etc/opkg/distfeeds.conf

# ۳. متغیرها
. /etc/openwrt_release
ARCH=$DISTRIB_ARCH
# تبدیل 23.05.3 به 23.05 برای مسیرهای Passwall
REL_SHORT=$(echo $DISTRIB_RELEASE | cut -d. -f1-2)

# ۴. اضافه کردن فیدهای Passwall با اسم درست فولدرها
BASE_PW="http://repo.peditxos.ir/passwall/releases/packages-$REL_SHORT/$ARCH"

# احتمال زیاد اسم فولدر اول passwall_luci هست نه passwall خالی
echo "src/gz peditxos_pw_luci $BASE_PW/passwall_luci" >> /etc/opkg/customfeeds.conf
echo "src/gz peditxos_pw_pkgs $BASE_PW/passwall_packages" >> /etc/opkg/customfeeds.conf
echo "src/gz peditxos_pw2 $BASE_PW/passwall2" >> /etc/opkg/customfeeds.conf

# ۵. آپدیت کلید
wget -qO /tmp/passwall.pub http://repo.peditxos.ir/passwall/passwall.pub && opkg-key add /tmp/passwall.pub

echo "Testing opkg update..."
EOF

sh /tmp/setup.sh && rm /tmp/setup.sh
