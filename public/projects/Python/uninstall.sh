#!/bin/sh

# Temporary file to store error messages
ERROR_LOG="/tmp/python_uninstall_errors.log"
rm -f $ERROR_LOG

# Packages to be removed (in order of dependency)
PACKAGES="python3-pip python3-light python3"

echo "[1/2] Preparing for uninstallation..."
# Check if python is even installed
if ! command -v python3 > /dev/null; then
    echo "  --> Python 3 is not found on this system. Nothing to do."
    exit 0
fi
echo "  --> DONE: Ready to remove components."

echo "[2/2] Removing Python and related packages..."
for pkg in $PACKAGES; do
    echo "  --> Removing $pkg..."
    # Perform removal silently. 
    # --autoremove is used to clean up unused dependencies automatically.
    if ! opkg remove "$pkg" --autoremove > /dev/null 2>>$ERROR_LOG; then
        echo "      [!] ERROR: Failed to remove $pkg"
    fi
done

echo "------------------------------------------"

# Final check: If error log is not empty, show errors
if [ -s "$ERROR_LOG" ]; then
    echo "Uninstallation finished with the following issues:"
    cat "$ERROR_LOG"
    echo "------------------------------------------"
else
    echo "SUCCESS: Python 3 and its components have been completely removed."
fi

# Cleanup
rm -f $ERROR_LOG

# PeDitX Banner
echo ""
echo "##########################################"
echo "#         MADE BY PeDitX                 #"
echo "##########################################"
echo ""
