#!/bin/sh
# PeDitXOS - Expand Root Partition
# WARNING: THIS WILL WIPE ALL DATA!
URL_EXPAND="https://raw.githubusercontent.com/peditx/PeDitXOs/refs/heads/main/.files/expand.sh"

echo "---"
echo "CRITICAL WARNING: Expanding root partition... THIS WILL WIPE ALL DATA!"
echo "---"
echo "Downloading and preparing the expansion script..."
cd /tmp
wget -q "$URL_EXPAND" -O expand.sh
chmod +x expand.sh
sh expand.sh
echo "Expansion script initiated."
