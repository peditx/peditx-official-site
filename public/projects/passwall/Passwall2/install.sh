#!/bin/sh

# PeDitXOS Unified Setup Utility - Professional Store Version
# This script is designed for automated, non-interactive environments.

echo "----------------------------------------------------"
echo "          PeDitXOS Setup Utility Starting           "
echo "----------------------------------------------------"

# --- 1. DNS Backup & Temporary Configuration ---
# Store original DNS to ensure internet access during setup without breaking user environment.
echo -n "1. Backing up DNS and preparing environment... "
{
    # Save current settings to variables
    OLD_WAN_DNS=$(uci -q get network.wan.dns)
    OLD_WAN_PEERDNS=$(uci -q get network.wan.peerdns)
    OLD_WAN6_DNS=$(uci -q get network.wan6.dns)
    OLD_WAN6_PEERDNS=$(uci -q get network.wan6.peerdns)

    # Set temporary DNS (Google) for stable downloads
    uci set network.wan.peerdns="0"
    uci set network.wan6.peerdns="0"
    uci set network.wan.dns='8.8.8.8'
    uci set network.wan6.dns='2001:4860:4860::8888'
    
    uci set system.@system[0].zonename='Asia/Tehran'
    uci set system.@system[0].timezone='<+0330>-3:30'
    
    uci commit network
    uci commit system
    /sbin/reload_config
} > /dev/null 2>&1
echo "Done."

# --- 2. Check Passwall2 Status ---
# Verify if the package exists before the sync process.
if opkg list-installed | grep -q "luci-app-passwall2"; then
    PASSWALL_EXISTS=1
else
    PASSWALL_EXISTS=0
fi

# --- 3. Repository Migration ---
# Smart migration to peditxrepo.ir to avoid duplicates.
echo -n "2. Checking & Migrating Repositories... "
{
    if ! grep -q "peditxrepo.ir" /etc/opkg/customfeeds.conf /etc/opkg/distfeeds.conf 2>/dev/null; then
        sed -i '/peditxdl.ir/d' /etc/opkg/distfeeds.conf
        sed -i '/peditxdl.ir/d' /etc/opkg/customfeeds.conf
        sed -i 's|https://downloads.openwrt.org|http://peditxrepo.ir/openwrt|g' /etc/opkg/distfeeds.conf

        SNNAP=$(grep -o SNAPSHOT /etc/openwrt_release | sed -n '1p')
        read release arch << EOF
$(. /etc/openwrt_release ; echo ${DISTRIB_RELEASE%.*} $DISTRIB_ARCH)
EOF
        
        echo "" > /etc/opkg/customfeeds.conf

        if [ "$SNNAP" = "SNAPSHOT" ]; then
            for feed in passwall_luci passwall_packages passwall2; do
              echo "src/gz $feed http://peditxrepo.ir/openwrt-passwall-build/snapshots/packages/$arch/$feed" >> /etc/opkg/customfeeds.conf
            done
        else
            for feed in passwall_packages passwall2; do
              echo "src/gz $feed http://peditxrepo.ir/openwrt-passwall-build/releases/packages-$release/$arch/$feed" >> /etc/opkg/customfeeds.conf
            done
        fi
        wget -qO /tmp/passwall.pub http://peditxrepo.ir/openwrt-passwall-build/passwall.pub && opkg-key add /tmp/passwall.pub
    fi
} > /dev/null 2>&1
echo "Done."

# --- 4. Package Synchronization ---
echo "3. Synchronizing Packages... "
{
    opkg update
    BASE_PKGS="luci wget-ssl unzip ca-bundle dnsmasq-full xray-core kmod-nft-socket kmod-nft-tproxy kmod-inet-diag kernel kmod-netlink-diag kmod-tun luci-lib-ipkg v2ray-geosite-ir luci-app-passwall2"
    
    if grep -q "SNAPSHOT" /etc/openwrt_release; then
        BASE_PKGS="$BASE_PKGS ipset ipt2socks iptables iptables-legacy iptables-mod-conntrack-extra iptables-mod-iprange iptables-mod-socket iptables-mod-tproxy kmod-ipt-nat"
    fi
    
    opkg install $BASE_PKGS
} > /dev/null 2>&1

# Xray fix for low-space devices
if [ ! -f "/usr/bin/xray" ]; then
    rm -f pedscript.sh && wget -q https://github.com/peditx/iranIPS/raw/refs/heads/main/.files/lowspc/pedscript.sh && chmod 777 pedscript.sh && sh pedscript.sh > /dev/null 2>&1
fi

# Feedback on Passwall2 status
if [ "$PASSWALL_EXISTS" = "1" ]; then
    echo "   - Status: Passwall2 was already installed. UI and packages updated."
else
    echo "   - Status: Passwall2 fresh installation completed."
fi

# --- 5. UI and Core File Deployment (soft.zip) ---
# Deploy or Update UI files via soft.zip (forced overwrite).
echo -n "4. Deploying PeDitX UI & Core Files (soft.zip)... "
{
    cd /tmp
    wget -q -O soft.zip https://uploadkon.ir/uploads/665412_26soft.zip
    #wget -q https://peditx.ir/projects/passwall/soft.zip
    if [ -f "soft.zip" ]; then
        unzip -o soft.zip -d /
        rm soft.zip
    fi
    cd
} > /dev/null 2>&1
echo "Done."

# --- 6. Branding & Hostname ---
echo -n "5. Finalizing Branding & Hostname... "
{
    uci set system.@system[0].hostname=PeDitXOS
    uci commit system
    echo "   
 ______      _____   _      _    _     _____       
(_____ \    (____ \ (_)_   \ \  / /   / ___ \      
 _____) )___ _   \ \ _| |_  \ \/ /   | |   | | ___ 
|  ____/ _  ) |   | | |  _)  )  (    | |   | |/___)
| |   ( (/ /| |__/ /| | |__ / /\ \   | |___| |___ |
|_|    \____)_____/ |_|\___)_/  \_\   \_____/(___/ 
                                                   
               Hack , Build , Reign                                                                                         
telegram : @PeDitX" > /etc/banner
} > /dev/null 2>&1
echo "Done."

# --- 7. Passwall Configuration ---
echo -n "6. Applying Full Rule Lists... "
{
    uci set passwall2.@global_forwarding[0]=global_forwarding
    uci set passwall2.@global_forwarding[0].tcp_redir_ports='1:65535'
    uci set passwall2.@global_forwarding[0].udp_redir_ports='1:65535'
    uci set passwall2.@global[0].remote_dns='8.8.4.4'

    # Clean old rules
    for rule in ProxyGame GooglePlay Netflix OpenAI Proxy China QUIC UDP; do 
        uci delete passwall2.$rule 2>/dev/null
    done

    # Full Direct List
    uci set passwall2.Direct=shunt_rules
    uci set passwall2.Direct.network='tcp,udp'
    uci set passwall2.Direct.remarks='IRAN'
    uci set passwall2.Direct.ip_list='geoip:ir
0.0.0.0/8
10.0.0.0/8
100.64.0.0/10
127.0.0.0/8
169.254.0.0/16
172.16.0.0/12
192.0.0.0/24
192.0.2.0/24
192.88.99.0/24
192.168.0.0/16
198.19.0.0/16
198.51.100.0/24
203.0.113.0/24
224.0.0.0/4
240.0.0.0/4
255.255.255.255/32
::/128
::1/128
::ffff:0:0:0/96
64:ff9b::/96
100::/64
2001::/32
2001:20::/28
2001:db8::/32
2002::/16
fc00::/7
fe80::/10
ff00::/8'
    uci set passwall2.Direct.domain_list='regexp:^.+\.ir$
geosite:category-ir
kifpool.me'

    # Full PC-Direct List
    uci set passwall2.DirectGame=shunt_rules
    uci set passwall2.DirectGame.network='tcp,udp'
    uci set passwall2.DirectGame.remarks='PC-Direct'
    uci set passwall2.DirectGame.domain_list='nvidia.com
youtube.com
epicgames.com
meta.com
instagram.com
facebook.com
twitter.com
tiktok.com
spotify.com
capcut.com
adobe.com
ubisoft.com
google.com
x.com
bingx.com
mexc.com
openwrt.org
twitch.tv
asus.com
byteoversea.com
tiktokv.com
xbox.com
us.download.nvidia.com
fcdn.co
adobe.io
cloudflare.com
playstation.com
tradingview.com
reachthefinals.com
midi-mixer.com
google-analytics.com
cloudflare-dns.com
bingx.com
activision.com
biostar.com.tw
aternos.me
geforce.com
gvt1.com
ubi.com
ea.com
eapressportal.com
myaccount.ea.com
origin.com
epicgames.dev
rockstargames.com
rockstarnorth.com
googlevideo.com
2ip.io
telegram.com
telegram.org
safepal.com
microsoft.com
apps.microsoft.com
live.com
ytimg.com
t.me
whatsapp.com
reddit.com
pvp.net
discord.com
discord.gg
discordapp.net
discordapp.com
bing.com
discord.media
approved-proxy.bc.ubisoft.com
tlauncher.org
aternos.host
aternos.me
aternos.org
aternos.net
aternos.com
steamcommunity.com
steam.com
steampowered.com
steamstatic.com
chatgpt.com
openai.com'

    uci set passwall2.MainShunt=nodes
    uci set passwall2.MainShunt.remarks='MainShunt'
    uci set passwall2.MainShunt.type='Xray'
    uci set passwall2.MainShunt.protocol='_shunt'
    uci set passwall2.MainShunt.Direct='_direct'
    uci set passwall2.MainShunt.DirectGame='_default'

    uci set dhcp.@dnsmasq[0].rebind_domain='www.ebanksepah.ir my.irancell.ir'
    uci commit passwall2
} > /dev/null 2>&1
echo "Done."

# --- 8. Restore User DNS ---
# Returns the network to its original state.
echo -n "7. Restoring User's Original Network DNS... "
{
    [ -n "$OLD_WAN_DNS" ] && uci set network.wan.dns="$OLD_WAN_DNS" || uci delete network.wan.dns
    [ -n "$OLD_WAN_PEERDNS" ] && uci set network.wan.peerdns="$OLD_WAN_PEERDNS" || uci set network.wan.peerdns="1"
    [ -n "$OLD_WAN6_DNS" ] && uci set network.wan6.dns="$OLD_WAN6_DNS" || uci delete network.wan6.dns
    [ -n "$OLD_WAN6_PEERDNS" ] && uci set network.wan6.peerdns="$OLD_WAN6_PEERDNS" || uci set network.wan6.peerdns="1"
    
    uci commit network
    uci commit
    /sbin/reload_config
} > /dev/null 2>&1
echo "Done."

echo "----------------------------------------------------"
echo "  Setup Finished Successfully. Made By : PeDitX     "
echo "----------------------------------------------------"
