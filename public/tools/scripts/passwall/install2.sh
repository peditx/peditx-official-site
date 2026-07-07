#!/bin/sh
# PeDitXOS - Install Passwall 2
URL_PW2="https://github.com/peditx/iranIPS/raw/refs/heads/main/.files/passwall2.sh"
echo "Downloading Passwall 2 components..."
cd /tmp
rm -f passwall2.sh
wget -q "$URL_PW2" -O passwall2.sh
chmod +x passwall2.sh
sh passwall2.sh
echo "Passwall 2 installed successfully."
