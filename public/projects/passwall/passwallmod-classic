#!/bin/sh

# Passwall1/2 PeDitXOS Classic Mod - UI Deployment Utility
DEBUG_LOG="/tmp/passwall_mod_debug.log"
rm -f "$DEBUG_LOG"

# Using a trap to ensure cleanup happens even if the script exits unexpectedly
cleanup() {
    rm -f /tmp/hard.zip
}
trap cleanup EXIT

echo "----------------------------------------------------"
echo "   Passwall1/2 PeDitXOS Classic Mod Starting        "
echo "----------------------------------------------------"

# --- Silent UI and Core File Deployment ---
echo -n "Deploying Passwall Mod UI & Core Files... "

{
    cd /tmp || exit 1
    
    # Downloading the specific hard.zip from GitHub (using raw URL for direct download)
    wget -q -O hard.zip https://github.com/PeDitXOS/PeDitXOS-passwall2/raw/main/files/hard.zip
    
    # Check if wget succeeded and file exists
    if [ $? -eq 0 ] && [ -f "hard.zip" ]; then
        # Unzip to root directory silently
        unzip -o hard.zip -d /
        echo "Deployment completed successfully inside the log."
    else
        echo "Error: Failed to download or locate hard.zip" >&2
        exit 1
    fi
    
    cd - > /dev/null || exit
} >> "$DEBUG_LOG" 2>&1

if [ $? -eq 0 ]; then
    echo "Done."
    echo "----------------------------------------------------"
    echo "  Setup Finished Successfully. PeDitXOS Classic     "
    echo "----------------------------------------------------"
else
    echo "Failed!"
    echo "----------------------------------------------------"
    echo "  Setup Failed. Check $DEBUG_LOG for details.       "
    echo "----------------------------------------------------"
fi
