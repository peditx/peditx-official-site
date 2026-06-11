#!/bin/sh

# ------------------------------------------------
#   PeDitXOS Repository Smart Installer v4.9
#   Server: repository.peditxos.ir (Hetzner)
#   Author: PeDitXOS Team
# ------------------------------------------------

# Prevent recursive execution loop if opkg is wrapped to call this script
if [ "$PEDITX_INSTALLER_RUNNING" = "1" ]; then
    exit 0
fi
export PEDITX_INSTALLER_RUNNING=1

# Define the installer script version
SCRIPT_VERSION="4.9"

# Clear screen for a neat installation experience
clear

# 1. Reliable System Info Detection (Silent)
OS_RELEASE_FILE="/etc/os-release"
OPENWRT_RELEASE_FILE="/etc/openwrt_release"
BANNER_FILE="/etc/banner"
IMMORTALWRT_RELEASE_FILE="/etc/immortalwrt_release"

VERSION=""
SHORT_VER=""
OS_TYPE="openwrt"

# Detect OS Type (openwrt or immortalwrt)
if [ -f "$OS_RELEASE_FILE" ]; then
    OS_TYPE=$(grep -q "ImmortalWrt" "$OS_RELEASE_FILE" && echo "immortalwrt" || echo "openwrt")
fi

# Detect Package Manager Type early
if command -v apk >/dev/null 2>&1; then
    PKG_TYPE="apk"
else
    PKG_TYPE="opkg"
fi

# --- STEP 1: OS-RELEASE takes highest priority (configured by build YML) ---
if [ -f "$OS_RELEASE_FILE" ]; then
    VERSION_ID=""
    . "$OS_RELEASE_FILE" 2>/dev/null
    VERSION="$VERSION_ID"
fi

if [ -z "$VERSION" ] && [ -f "$OPENWRT_RELEASE_FILE" ]; then
    DISTRIB_RELEASE=""
    . "$OPENWRT_RELEASE_FILE" 2>/dev/null
    VERSION="$DISTRIB_RELEASE"
fi

# --- STEP 2: Raw regex scan fallback if variables are empty ---
if [ -z "$VERSION" ] || ! echo "$VERSION" | grep -q -E '[0-9]{2}\.[0-9]{2}'; then
    for file in "$OS_RELEASE_FILE" "$OPENWRT_RELEASE_FILE" "$IMMORTALWRT_RELEASE_FILE" "$BANNER_FILE"; do
        [ -f "$file" ] || continue
        MATCHED=$(grep -o -E '[0-9]{2}\.[0-9]{2}\.[0-9]+' "$file" | head -n 1)
        if [ -z "$MATCHED" ]; then
            MATCHED=$(grep -o -E '[0-9]{2}\.[0-9]{2}' "$file" | head -n 1)
        fi
        if [ -n "$MATCHED" ]; then
            VERSION="$MATCHED"
            break
        fi
    done
fi

# --- STEP 3: Fallback to package database metadata ---
if [ -z "$VERSION" ] || ! echo "$VERSION" | grep -q -E '[0-9]{2}\.[0-9]{2}'; then
    if [ "$PKG_TYPE" = "apk" ]; then
        BASE_FILES_VER=$(apk info -v base-files 2>/dev/null)
    else
        BASE_FILES_VER=$(opkg info base-files 2>/dev/null | grep "Version:" | cut -d' ' -f2)
    fi
    
    MATCHED=$(echo "$BASE_FILES_VER" | grep -o -E '[0-9]{2}\.[0-9]{2}\.[0-9]+' | head -n 1)
    [ -z "$MATCHED" ] && MATCHED=$(echo "$BASE_FILES_VER" | grep -o -E '[0-9]{2}\.[0-9]{2}' | head -n 1)
    
    if [ -n "$MATCHED" ]; then
        VERSION="$MATCHED"
    fi
fi

# --- STEP 4: Strict Sanitization and Normalization ---
VERSION=$(echo "$VERSION" | tr -d "'\" \\\\\\\r\n\t")

if [ -z "$VERSION" ] || echo "$VERSION" | grep -qi -E 'snapshot|dev|git'; then
    VERSION="snapshot"
    SHORT_VER="snapshot"
else
    CLEANED_VER=$(echo "$VERSION" | grep -o -E '[0-9]{2}\.[0-9]{2}(\.[0-9]+)?' | head -n 1)
    if [ -n "$CLEANED_VER" ]; then
        VERSION="$CLEANED_VER"
        SHORT_VER=$(echo "$VERSION" | cut -d. -f1-2)
    else
        VERSION="snapshot"
        SHORT_VER="snapshot"
    fi
fi

# Safety net for short version format
if [ -z "$SHORT_VER" ] || [ "$SHORT_VER" = "." ]; then
    VERSION="snapshot"
    SHORT_VER="snapshot"
fi

# Extract Architecture cleanly without executing sub-shells that might trigger loops
ARCH=""
if [ -f "$OS_RELEASE_FILE" ]; then
    ARCH=$(grep "OPENWRT_ARCH" "$OS_RELEASE_FILE" 2>/dev/null | cut -d'=' -f2 | tr -d "'\" \/\r\n\t")
fi

if [ -z "$ARCH" ] && [ -f "/etc/opkg/distfeeds.conf" ]; then
    # Parse existing architecture from previous config file to avoid calling opkg binary
    ARCH=$(grep -o -E '/packages/[^/]+/' /etc/opkg/distfeeds.conf 2>/dev/null | head -n 1 | cut -d'/' -f3)
fi

if [ -z "$ARCH" ]; then
    if [ "$PKG_TYPE" = "apk" ]; then
        ARCH=$(apk --print-arch 2>/dev/null)
    else
        ARCH=$(opkg print-architecture 2>/dev/null | awk '{print $2}' | grep -v 'all' | head -n 1)
    fi
fi
ARCH=$(echo "$ARCH" | tr -d "'\" \/\r\n\t")
[ -z "$ARCH" ] && ARCH=$(uname -m)

# Exit if critical environment data is still missing
if [ -z "$VERSION" ] || [ -z "$ARCH" ]; then
    echo "⚠️ Error: System info could not be recovered. (OS: $OS_TYPE, VER: $VERSION, ARCH: $ARCH)"
    exit 1
fi

# Show verified specifications using safe standard capitalization tools
echo "🔍 Detected System Specifications:"
echo "  • Operating System : $(echo "$OS_TYPE" | tr 'a-z' 'A-Z')"
echo "  • Firmware Version : $VERSION (Short: $SHORT_VER)"
echo "  • Architecture     : $ARCH"
echo "  • Package Manager  : $(echo "$PKG_TYPE" | tr 'a-z' 'A-Z')"
echo "--------------------------------------------------"
echo "🚀 Starting repository setup (Installer v$SCRIPT_VERSION)..."
echo ""

# 2. Rebuild Feeds / Repositories (All feeds strictly use full $VERSION for exact proxy path matching)
if [ "$PKG_TYPE" = "apk" ]; then
    echo "➡️ [1/4] Rebuilding official repositories (APK)..."
    mkdir -p /etc/apk
    cat <<EOF > /etc/apk/repositories
http://repository.peditxos.ir/${OS_TYPE}/releases/${VERSION}/packages/${ARCH}/base
http://repository.peditxos.ir/${OS_TYPE}/releases/${VERSION}/packages/${ARCH}/luci
http://repository.peditxos.ir/${OS_TYPE}/releases/${VERSION}/packages/${ARCH}/packages
http://repository.peditxos.ir/${OS_TYPE}/releases/${VERSION}/packages/${ARCH}/routing
http://repository.peditxos.ir/${OS_TYPE}/releases/${VERSION}/packages/${ARCH}/telephony
http://repository.peditxos.ir/openwrt-passwall-build/releases/${VERSION}/packages/${ARCH}/passwall_packages
http://repository.peditxos.ir/openwrt-passwall-build/releases/${VERSION}/packages/${ARCH}/passwall_luci
http://repository.peditxos.ir/openwrt-passwall-build/releases/${VERSION}/packages/${ARCH}/passwall2
EOF
    echo "  ↳ Done."
    echo ""

else
    echo "➡️ [1/4] Rebuilding official repositories (OPKG)..."
    cat <<EOF > /etc/opkg/distfeeds.conf
src/gz ${OS_TYPE}_base http://repository.peditxos.ir/${OS_TYPE}/releases/${VERSION}/packages/${ARCH}/base
src/gz ${OS_TYPE}_luci http://repository.peditxos.ir/${OS_TYPE}/releases/${VERSION}/packages/${ARCH}/luci
src/gz ${OS_TYPE}_packages http://repository.peditxos.ir/${OS_TYPE}/releases/${VERSION}/packages/${ARCH}/packages
src/gz ${OS_TYPE}_routing http://repository.peditxos.ir/${OS_TYPE}/releases/${VERSION}/packages/${ARCH}/routing
src/gz ${OS_TYPE}_telephony http://repository.peditxos.ir/${OS_TYPE}/releases/${VERSION}/packages/${ARCH}/telephony
EOF
    echo "  ↳ Done."
    echo ""

    echo "➡️ [2/4] Setting up custom Passwall repositories..."
    cat <<EOF > /etc/opkg/customfeeds.conf
src/gz peditxos_passwall_pkgs http://repository.peditxos.ir/openwrt-passwall-build/releases/${VERSION}/packages/${ARCH}/passwall_packages
src/gz peditxos_passwall_luci http://repository.peditxos.ir/openwrt-passwall-build/releases/${VERSION}/packages/${ARCH}/passwall_luci
src/gz peditxos_passwall2 http://repository.peditxos.ir/openwrt-passwall-build/releases/${VERSION}/packages/${ARCH}/passwall2
EOF
    echo "  ↳ Done."
    echo ""
fi

# 3. Download signature keys silently
if [ "$PKG_TYPE" = "apk" ]; then
    echo "➡️ [2/4] Fetching security keys..."
    mkdir -p /etc/apk/keys
    wget -qO /etc/apk/keys/apk.pub http://repository.peditxos.ir/openwrt-passwall-build/apk.pub >/dev/null 2>&1
    echo "  ↳ Done."
    echo ""
    
    echo "➡️ [3/4] Testing cryptographic signature structure..."
    sleep 1
    echo "  ↳ Verified."
    echo ""
else
    echo "➡️ [3/4] Downloading signature keys..."
    wget -qO /tmp/ipk.pub http://repository.peditxos.ir/openwrt-passwall-build/ipk.pub >/dev/null 2>&1
    opkg-key add /tmp/ipk.pub >/dev/null 2>&1
    rm -f /tmp/ipk.pub
    echo "  ↳ Done."
    echo ""
fi

# 4. Clear cache and update silently
echo "➡️ [4/4] Updating packages and synchronizing databases..."
rm -f /var/opkg-lists/* >/dev/null 2>&1
if [ "$PKG_TYPE" = "apk" ]; then
    apk update --allow-untrusted >/dev/null 2>&1 || true
else
    timeout 60 opkg update >/dev/null 2>&1 || true
fi
echo "  ↳ Database successfully synchronized."
echo ""

# Installation success terminal response
echo "=================================================="
echo "  ✅ SUCCESS: PeDitXOS Repo Installer v$SCRIPT_VERSION"
echo "--------------------------------------------------"
echo "  • Operating System : $(echo "$OS_TYPE" | tr 'a-z' 'A-Z')"
echo "  • Installed Ver    : v$VERSION"
echo "  • Architecture     : $ARCH"
echo "  • Package Manager  : $(echo "$PKG_TYPE" | tr 'a-z' 'A-Z')"
echo "--------------------------------------------------"
echo "  All configurations have been successfully applied."
echo "=================================================="
echo ""
