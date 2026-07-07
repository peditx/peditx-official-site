#!/bin/sh
# PeDitXOS - Install Passwall 1 + 2
URL_PW_DUE="https://github.com/peditx/iranIPS/raw/refs/heads/main/.files/passwalldue.sh"
echo "Downloading Passwall 1 & 2 components..."
cd /tmp
rm -f passwalldue.sh
wget -q "$URL_PW_DUE" -O passwalldue.sh
chmod +x passwalldue.sh
sh passwalldue.sh
echo "Both Passwall versions installed successfully."
