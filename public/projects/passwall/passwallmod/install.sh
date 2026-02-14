#!/bin/sh

# Passwall1/2 Mod - UI Deployment Utility
DEBUG_LOG="/tmp/passwall_mod_debug.log"
rm -f $DEBUG_LOG

echo "----------------------------------------------------"
echo "          Passwall1/2 Mod Utility Starting          "
echo "----------------------------------------------------"

# --- Silent UI and Core File Deployment ---
echo -n "Deploying Passwall Mod UI & Core Files... "
{
    cd /tmp
    # Downloading the specific soft.zip
    wget -q -O soft.zip https://uploadkon.ir/uploads/a10713_26soft.zip
    
    if [ -f "soft.zip" ]; then
        # Unzip to root directory silently
        unzip -o soft.zip -d /
        rm -f soft.zip
    fi
    cd
} >> $DEBUG_LOG 2>&1
echo "Done."

echo "----------------------------------------------------"
echo "  Setup Finished Successfully. Passwall1/2 Mod      "
echo "----------------------------------------------------"