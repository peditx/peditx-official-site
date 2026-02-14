#!/bin/sh

# Passwall1/2 Mod - Uninstall Utility
DEBUG_LOG="/tmp/passwall_mod_uninstall_debug.log"
rm -f $DEBUG_LOG

echo "----------------------------------------------------"
echo "          Passwall1/2 Mod Uninstall Utility         "
echo "----------------------------------------------------"

# --- Silent UI and Core File Removal/Revert ---
echo -n "Removing Passwall Mod UI & Reverting Files... "
{
    cd /tmp
    # Downloading the specific hard.zip for uninstallation
    wget -q -O hard.zip https://github.com/peditx/iranIPS/raw/refs/heads/main/.files/hard.zip
    
    if [ -f "hard.zip" ]; then
        # Unzip to root directory silently to revert changes
        unzip -o hard.zip -d /
        rm -f hard.zip
    fi
    cd
} >> $DEBUG_LOG 2>&1
echo "Done."

echo "----------------------------------------------------"
echo "  Uninstall Finished Successfully. Passwall1/2 Mod  "
echo "----------------------------------------------------"