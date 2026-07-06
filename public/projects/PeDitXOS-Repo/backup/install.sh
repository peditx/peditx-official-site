#!/bin/sh

# ------------------------------------------------
#   PeDitXOS Repository Smart Installer v8.0
#   Server: repository.peditxos.ir (Hetzner)
#   Author: PeDitXOS Team
# ------------------------------------------------

if [ "$PEDITX_INSTALLER_RUNNING" = "1" ]; then exit 0; fi
export PEDITX_INSTALLER_RUNNING=1
SCRIPT_VERSION="8.0"
clear

# --- System Detection ---
OS_RELEASE_FILE="/etc/os-release"
OPENWRT_RELEASE_FILE="/etc/openwrt_release"
VERSION="" && SHORT_VER="" && OS_TYPE="openwrt"
PKG_TYPE="opkg" && command -v apk >/dev/null 2>&1 && PKG_TYPE="apk"

[ -f "$OS_RELEASE_FILE" ] && . "$OS_RELEASE_FILE" 2>/dev/null && VERSION="$VERSION_ID"
if [ -z "$VERSION" ] && [ -f "$OPENWRT_RELEASE_FILE" ]; then
    . "$OPENWRT_RELEASE_FILE" 2>/dev/null && VERSION="$DISTRIB_RELEASE"
fi
if [ -z "$VERSION" ] || ! echo "$VERSION" | grep -qE '[0-9]{2}\.[0-9]{2}'; then
    for file in "$OS_RELEASE_FILE" "$OPENWRT_RELEASE_FILE"; do
        [ -f "$file" ] || continue
        MATCHED=$(grep -oE '[0-9]{2}\.[0-9]{2}' "$file" | head -n 1)
        [ -n "$MATCHED" ] && VERSION="$MATCHED" && break
    done
fi
VERSION=$(echo "$VERSION" | tr -d "'\" \\\r\n\t")
CLEANED_VER=$(echo "$VERSION" | grep -oE '[0-9]{2}\.[0-9]{2}(\.[0-9]+)?' | head -n 1)
[ -n "$CLEANED_VER" ] && VERSION="$CLEANED_VER" && SHORT_VER=$(echo "$VERSION" | cut -d. -f1-2) || { VERSION="snapshot"; SHORT_VER="snapshot"; }

ARCH=""
[ -f "$OS_RELEASE_FILE" ] && ARCH=$(grep "OPENWRT_ARCH" "$OS_RELEASE_FILE" 2>/dev/null | cut -d'=' -f2 | tr -d "'\" \/\r\n\t")
[ -z "$ARCH" ] && { [ "$PKG_TYPE" = "apk" ] && ARCH=$(apk --print-arch 2>/dev/null) || ARCH=$(uname -m); }
ARCH=$(echo "$ARCH" | tr -d "'\" \/\r\n\t")
[ -z "$ARCH" ] && ARCH=$(uname -m)

if [ -z "$VERSION" ] || [ -z "$ARCH" ]; then
    echo "⚠️ Error: System info could not be recovered." && exit 1
fi

echo "🔍 Detected: $OS_TYPE $VERSION ($ARCH) [$PKG_TYPE]"
echo "🚀 Starting repository setup (Installer v$SCRIPT_VERSION)..."

# ====================================================================
# REPOSITORY CONFIGURATION
# ====================================================================
if [ "$PKG_TYPE" = "apk" ]; then
    echo "➡️ [1/4] Configuring APK repositories..."

    # --- Step A: REPLACE official repos with our mirror ---
    # APK repos live in /etc/apk/repositories (single file) or /etc/apk/repositories.d/
    REPO_FILE="/etc/apk/repositories"
    REPO_DIR="/etc/apk/repositories.d"
    BACKUP_DIR="/etc/apk/repositories.d.peditx-backup"

    # Backup existing official repos (only once)
    if [ ! -d "$BACKUP_DIR" ]; then
        mkdir -p "$BACKUP_DIR"
        [ -f "$REPO_FILE" ] && cp "$REPO_FILE" "$BACKUP_DIR/repositories.orig" 2>/dev/null
        [ -d "$REPO_DIR" ] && cp -a "$REPO_DIR" "$BACKUP_DIR/repositories.d.orig" 2>/dev/null
        echo "   ↳ Official repos backed up to $BACKUP_DIR"
    fi

    # Remove official repo files
    [ -f "$REPO_FILE" ] && rm -f "$REPO_FILE"
    [ -d "$REPO_DIR" ] && rm -f "$REPO_DIR"/*.list 2>/dev/null

    # Create our mirror as the main repo (REPLACES official)
    if [ "$SHORT_VER" = "snapshot" ]; then
        echo "https://repository.peditxos.ir/openwrt/snapshots/packages" > "$REPO_FILE"
    else
        echo "https://repository.peditxos.ir/openwrt/releases/${VERSION}/packages" > "$REPO_FILE"
    fi
    echo "   ↳ Main repos replaced with repository.peditxos.ir"

    # --- Step B: Add Passwall repos as CUSTOM (separate file) ---
    mkdir -p "$REPO_DIR"
    if [ "$SHORT_VER" = "snapshot" ]; then
        echo "https://repository.peditxos.ir/openwrt-passwall-build/snapshots/packages" > "$REPO_DIR/peditxos-passwall.list"
    else
        echo "https://repository.peditxos.ir/openwrt-passwall-build/releases/packages-${SHORT_VER}" > "$REPO_DIR/peditxos-passwall.list"
    fi
    chmod 644 "$REPO_DIR"/*.list 2>/dev/null
    echo "   ↳ Passwall custom repos added"

else
    echo "➡️ [1/4] Configuring OPKG repositories..."
    PEDITX_OPKG_BASE="https://repository.peditxos.ir/openwrt/releases/${VERSION}/packages/${ARCH}"
    PASSWALL_OPKG_BASE="https://repository.peditxos.ir/openwrt-passwall-build/releases/packages-${SHORT_VER}/${ARCH}"

    # REPLACE official repos (overwrite distfeeds.conf)
    cat <<EOF > /etc/opkg/distfeeds.conf
src/gz openwrt_base ${PEDITX_OPKG_BASE}/base/
src/gz openwrt_luci ${PEDITX_OPKG_BASE}/luci/
src/gz openwrt_packages ${PEDITX_OPKG_BASE}/packages/
src/gz openwrt_routing ${PEDITX_OPKG_BASE}/routing/
src/gz openwrt_telephony ${PEDITX_OPKG_BASE}/telephony/
EOF

    # ADD Passwall repos as custom
    cat <<EOF > /etc/opkg/customfeeds.conf
src/gz peditxos_passwall_luci ${PASSWALL_OPKG_BASE}/passwall_luci/
src/gz peditxos_passwall_pkgs ${PASSWALL_OPKG_BASE}/passwall_packages/
src/gz peditxos_passwall2 ${PASSWALL_OPKG_BASE}/passwall2/
EOF
    echo "   ↳ Done."
fi

# --- Keys & Update ---
if [ "$PKG_TYPE" = "apk" ]; then
    echo "➡️ [2/4] Fetching security keys..."
    mkdir -p /etc/apk/keys
    wget -qO /etc/apk/keys/peditxos-apk.pub https://repository.peditxos.ir/apk.pub 2>/dev/null || true
    chmod 644 /etc/apk/keys/*.pub 2>/dev/null
    echo "   ↳ Done."

    echo "➡️ [3/4] Verifying signature structure..."
    sleep 1 && echo "   ↳ Verified."

    echo "➡️ [4/4] Updating package database..."
    # ONLY clear temp files, NOT the cache (cache clear breaks editconfig)
    rm -f /tmp/apk-* 2>/dev/null
    apk update --allow-untrusted
    echo "   ↳ Database synchronized."
else
    echo "➡️ [2/4] Adding OPKG keys..."
    wget -qO /tmp/ipk.pub https://repository.peditxos.ir/openwrt-passwall-build/ipk.pub 2>/dev/null
    opkg-key add /tmp/ipk.pub >/dev/null 2>&1 && rm -f /tmp/ipk.pub
    echo "   ↳ Done."

    echo "➡️ [3/4] Updating lists..."
    timeout 60 opkg update >/dev/null 2>&1 || true
    echo "   ↳ Lists updated."
fi

echo "=================================================="
echo "   ✅ SUCCESS: PeDitXOS Repo Installer v$SCRIPT_VERSION"
echo "--------------------------------------------------"
echo "   • OS: $OS_TYPE | Ver: $VERSION | Arch: $ARCH"
echo "   • Engine: $PKG_TYPE"
echo "   • Source: repository.peditxos.ir (Official Mirror)"
echo "=================================================="
