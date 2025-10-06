#!/bin/sh
# Auto install latest luci-theme-aurora for OpenWrt (BusyBox safe)

REPO="eamonxg/luci-theme-aurora"
TMP_DIR="/tmp/aurora"
mkdir -p "$TMP_DIR"
cd "$TMP_DIR" || exit 1

echo "[+] Fetching latest release info..."

LATEST_TAG=$(wget -qO- "https://api.github.com/repos/$REPO/releases/latest" | sed -n 's/.*"tag_name": *"\([^"]*\)".*/\1/p' | head -n1)
if [ -z "$LATEST_TAG" ]; then
    echo "[!] Failed to fetch latest version tag."
    exit 1
fi

echo "[+] Latest version: $LATEST_TAG"

DL_URL=$(wget -qO- "https://api.github.com/repos/$REPO/releases/tags/$LATEST_TAG" | sed -n 's/.*"\(https:\/\/github.com\/[^"]*\.ipk\)".*/\1/p' | head -n1)
if [ -z "$DL_URL" ]; then
    echo "[!] No .ipk file found in release."
    exit 1
fi

FILE_NAME=$(basename "$DL_URL")

echo "[+] Downloading: $FILE_NAME"
wget -q "$DL_URL" -O "$FILE_NAME"

if [ ! -f "$FILE_NAME" ]; then
    echo "[!] Download failed."
    exit 1
fi

echo "[+] Installing package..."
opkg install "$FILE_NAME"

if [ $? -eq 0 ]; then
    echo "[✓] luci-theme-aurora installed successfully!"
else
    echo "[✗] Installation failed."
    exit 1
fi

echo "[i] You can select the Aurora theme from LuCI: System → System → Language and Style."

rm -rf "$TMP_DIR"
