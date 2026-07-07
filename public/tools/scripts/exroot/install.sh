#!/bin/sh
# PeDitXOS - Easy Exroot Script
# Source: peditx/ezexroot
URL_EZEXROOT="https://github.com/peditx/ezexroot/raw/refs/heads/main/ezexroot.sh"

echo "Downloading Easy Exroot script..."
cd /tmp
rm -f ezexroot.sh
curl -ksSL "$URL_EZEXROOT" -o ezexroot.sh
sh ezexroot.sh
echo "Easy Exroot script finished."
