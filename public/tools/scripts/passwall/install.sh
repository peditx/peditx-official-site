#!/bin/sh
# PeDitXOS - Install Passwall 1
URL_PW1="https://github.com/peditx/iranIPS/raw/refs/heads/main/.files/passwall.sh"
echo "Downloading Passwall 1 components..."
cd /tmp
rm -f passwall.sh
wget -q "$URL_PW1" -O passwall.sh
chmod +x passwall.sh
sh passwall.sh
echo "Passwall 1 installed successfully."
