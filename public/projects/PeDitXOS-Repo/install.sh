cat << 'EOF' > /tmp/setup.sh
#!/bin/sh
echo "------------------------------------------------"
echo "  Starting PeDitXOS Repository Migration... "
echo "------------------------------------------------"

# ۱. پاکسازی آثار دامین‌های قدیمی
sed -i '/peditxdl.ir/d' /etc/opkg/distfeeds.conf
sed -i '/peditxdl.ir/d' /etc/opkg/customfeeds.conf
sed -i '/peditxrepo.ir/d' /etc/opkg/customfeeds.conf
sed -i '/repo.peditxos.ir/d' /etc/opkg/customfeeds.conf

# ۲. تغییر فیدهای اصلی به پروکسی جدید (برای دور زدن اختلال مخابرات)
sed -i 's|https://downloads.openwrt.org|http://repo.peditxos.ir/openwrt|g' /etc/opkg/distfeeds.conf

# ۳. استخراج نسخه و معماری دستگاه
read release arch << EOX
$(. /etc/openwrt_release ; echo ${DISTRIB_RELEASE%.*} $DISTRIB_ARCH)
EOX

# ۴. اضافه کردن فیدهای Passwall (اصلاح شده برای شامل شدن هر ۳ مخزن)
# آدرس‌ها مطابق ساختار جدید سورس‌فورج و آپاچی تو ست شده‌اند
BASE_URL="http://repo.peditxos.ir/passwall/releases/packages-$release/$arch"

echo "src/gz peditxos_passwall $BASE_URL/passwall" >> /etc/opkg/customfeeds.conf
echo "src/gz peditxos_passwall_pkgs $BASE_URL/passwall_packages" >> /etc/opkg/customfeeds.conf
echo "src/gz peditxos_passwall2 $BASE_URL/passwall2" >> /etc/opkg/customfeeds.conf

# ۵. آپدیت کلید امنیتی از آدرس جدید
wget -qO /tmp/passwall.pub http://repo.peditxos.ir/passwall/passwall.pub && opkg-key add /tmp/passwall.pub > /dev/null 2>&1

echo "Updating package lists (please wait)..."
opkg update > /dev/null 2>&1

echo "------------------------------------------------"
echo "  SUCCESS: Migrated to PeDitXOS Repository! "
echo "  All Passwall feeds (1, 2 & pkgs) Added. "
echo "------------------------------------------------"
EOF

sh /tmp/setup.sh && rm /tmp/setup.sh
