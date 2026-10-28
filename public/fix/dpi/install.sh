#!/bin/sh

FILE="/etc/uci-defaults/98-peditxos-apk-settings"

if rm -f "$FILE" && [ ! -e "$FILE" ] && [ ! -L "$FILE" ]; then
    echo ""
    echo "✅ PeDitXOS: DPI & Configuration Persistence Fix"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "🎉 Success! The fix has been applied."
    echo "📶 Wi-Fi SSID and DHCP settings can now be customized."
    echo "💾 Configuration persistence has been addressed."
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    exit 0
else
    echo ""
    echo "❌ PeDitXOS: Fix Failed"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "⚠️ The issue may still persist on your device."
    echo "🔧 Please recompile PeDitXOS and try again."
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    exit 1
fi
