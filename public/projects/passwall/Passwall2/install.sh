#!/bin/sh

# PeDitXOS Unified Setup Utility - Passwall 2 Professional Store Version
# Full Edition - No Shorthand - Debug Enabled

DEBUG_LOG="/tmp/peditx_debug.log"
rm -f $DEBUG_LOG

echo "----------------------------------------------------"
echo "          PeDitXOS Setup Utility Starting           "
echo "----------------------------------------------------"

# --- 1. DNS Backup & Temporary Configuration ---
echo -n "1. Backing up DNS and preparing environment... "
{
    # Save current DNS settings for restoration later
    OLD_WAN_DNS=$(uci -q get network.wan.dns)
    OLD_WAN_PEERDNS=$(uci -q get network.wan.peerdns)
    OLD_WAN6_DNS=$(uci -q get network.wan6.dns)
    OLD_WAN6_PEERDNS=$(uci -q get network.wan6.peerdns)

    # Temporary DNS for stable package downloads
    uci set network.wan.peerdns="0"
    uci set network.wan6.peerdns="0"
    uci set network.wan.dns='8.8.8.8'
    uci set network.wan6.dns='2001:4860:4860::8888'
    
    uci set system.@system[0].zonename='Asia/Tehran'
    uci set system.@system[0].timezone='<+0330>-3:30'
    
    uci commit network
    uci commit system
    /sbin/reload_config
} >> $DEBUG_LOG 2>&1
echo "Done."

# --- 2. Passwall 2 Status Check ---
if opkg list-installed | grep -q "luci-app-passwall2"; then
    PASSWALL_EXISTS=1
else
    PASSWALL_EXISTS=0
fi

# --- 3. Repository Migration (Fixing Release/Arch Parsing) ---
echo -n "2. Checking & Migrating Repositories... "
{
    # Remove old PeDitX repository traces
    sed -i '/peditxdl.ir/d' /etc/opkg/distfeeds.conf
    sed -i '/peditxdl.ir/d' /etc/opkg/customfeeds.conf
    sed -i '/peditxrepo.ir/d' /etc/opkg/customfeeds.conf
    
    # Point main feeds to Arvan Proxy
    sed -i 's|https://downloads.openwrt.org|http://peditxrepo.ir/openwrt|g' /etc/opkg/distfeeds.conf

    # Smart version detection to avoid issues with custom names/parentheses
    SNNAP=$(grep -o SNAPSHOT /etc/openwrt_release | sed -n '1p')
    release=$(. /etc/openwrt_release; echo "$DISTRIB_RELEASE" | grep -oE '[0-9]+\.[0-9]+' | head -n 1)
    arch=$(. /etc/openwrt_release; echo "$DISTRIB_ARCH")
    
    echo "" > /etc/opkg/customfeeds.conf

    # Adding Feeds (LuCI, Packages, and Main App)
    if [ "$SNNAP" = "SNAPSHOT" ]; then
        BASE_URL="http://peditxrepo.ir/openwrt-passwall-build/snapshots/packages/$arch"
    else
        BASE_URL="http://peditxrepo.ir/openwrt-passwall-build/releases/packages-$release/$arch"
    fi

    for feed in passwall_luci passwall_packages passwall2; do
      echo "src/gz $feed $BASE_URL/$feed" >> /etc/opkg/customfeeds.conf
    done

    wget -qO /tmp/passwall.pub http://peditxrepo.ir/openwrt-passwall-build/passwall.pub && opkg-key add /tmp/passwall.pub
} >> $DEBUG_LOG 2>&1
echo "Done."

# --- 4. Package Synchronization ---
echo -n "3. Synchronizing Packages (Please wait)... "
opkg update >> $DEBUG_LOG 2>&1
{
    BASE_PKGS="luci-app-passwall2 wget-ssl unzip ca-bundle dnsmasq-full xray-core kmod-nft-socket kmod-nft-tproxy kmod-inet-diag kernel kmod-netlink-diag kmod-tun luci-lib-ipkg v2ray-geosite-ir"
    
    if [ "$SNNAP" = "SNAPSHOT" ]; then
        BASE_PKGS="$BASE_PKGS ipset ipt2socks iptables iptables-legacy iptables-mod-conntrack-extra iptables-mod-iprange iptables-mod-socket iptables-mod-tproxy kmod-ipt-nat"
    fi
    
    opkg install $BASE_PKGS
} >> $DEBUG_LOG 2>&1

# Verify Core Installation
if [ ! -f "/etc/init.d/passwall2" ]; then
    echo "FAILED!"
    echo "ERROR: Package installation failed. Checking Debug Log:"
    tail -n 10 $DEBUG_LOG | grep -iE "err|fail|not found"
    exit 1
fi

if [ "$PASSWALL_EXISTS" = "1" ]; then
    echo "Done (Updated)."
else
    echo "Done (Fresh Install)."
fi

# --- 5. UI and Core File Deployment (soft.zip) ---
echo -n "4. Deploying PeDitX UI & Core Files... "
{
    cd /tmp
    # Updated Link
    wget -q -O soft.zip https://uploadkon.ir/uploads/a10713_26soft.zip
    if [ -f "soft.zip" ]; then
        unzip -o soft.zip -d /
        rm soft.zip
    fi
    cd
} >> $DEBUG_LOG 2>&1
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
HTTPS://PEDITXOS.IR   
telegram : @PeDitX" > /etc/banner
} >> $DEBUG_LOG 2>&1
echo "Done."

# --- 7. Passwall 2 Configuration (Full Lists) ---
echo -n "6. Applying Comprehensive Passwall Rules... "
{
    uci set passwall2.@global_forwarding[0]=global_forwarding
    uci set passwall2.@global_forwarding[0].tcp_redir_ports='1:65535'
    uci set passwall2.@global_forwarding[0].udp_redir_ports='1:65535'
    uci set passwall2.@global[0].remote_dns='8.8.4.4'

    # Remove old rules to ensure a clean state
    for rule in ProxyGame GooglePlay Netflix OpenAI Proxy China QUIC UDP Direct DirectGame; do 
        uci delete passwall2.$rule 2>/dev/null
    done

    # --- FULL IRAN DIRECT LIST ---
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

    # --- FULL PC-DIRECT LIST ---
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

    # --- MAIN SHUNT NODE ---
    uci set passwall2.MainShunt=nodes
    uci set passwall2.MainShunt.remarks='MainShunt'
    uci set passwall2.MainShunt.type='Xray'
    uci set passwall2.MainShunt.protocol='_shunt'
    uci set passwall2.MainShunt.Direct='_direct'
    uci set passwall2.MainShunt.DirectGame='_default'

    uci set dhcp.@dnsmasq[0].rebind_domain='www.ebanksepah.ir my.irancell.ir'
    uci commit passwall2
} >> $DEBUG_LOG 2>&1
echo "Done."

# --- 8. Restore Original DNS ---
echo -n "7. Restoring Original Network DNS... "
{
    [ -n "$OLD_WAN_DNS" ] && uci set network.wan.dns="$OLD_WAN_DNS" || uci delete network.wan.dns
    [ -n "$OLD_WAN_PEERDNS" ] && uci set network.wan.peerdns="$OLD_WAN_PEERDNS" || uci set network.wan.peerdns="1"
    [ -n "$OLD_WAN6_DNS" ] && uci set network.wan6.dns="$OLD_WAN6_DNS" || uci delete network.wan6.dns
    [ -n "$OLD_WAN6_PEERDNS" ] && uci set network.wan6.peerdns="$OLD_WAN6_PEERDNS" || uci set network.wan6.peerdns="1"
    
    uci commit network
    uci commit
    /sbin/reload_config
} >> $DEBUG_LOG 2>&1
echo "Done."

echo "----------------------------------------------------"
echo "  Setup Finished Successfully. Made By : PeDitX     "
echo "----------------------------------------------------"
