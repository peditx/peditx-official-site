#!/bin/sh

# Temporary file to store error messages
ERROR_LOG="/tmp/python_install_errors.log"
rm -f $ERROR_LOG

# Define packages for a complete Python environment
PACKAGES="python3 python3-pip python3-light"

echo "[1/3] Updating package database..."
# Run opkg update silently and capture errors
if ! opkg update > /dev/null 2>>$ERROR_LOG; then
    echo "  --> FAILED: Could not update package list."
else
    echo "  --> DONE: Package list updated."
fi

echo "[2/3] Checking system resources..."
# Check available space in /overlay (minimum 40MB recommended for Python)
FREE_SPACE=$(df /overlay | awk 'NR==2 {print $4}')
if [ -z "$FREE_SPACE" ]; then FREE_SPACE=0; fi

if [ "$FREE_SPACE" -lt 40000 ]; then
    echo "  --> WARNING: Low disk space ($((FREE_SPACE/1024)) MB). Installation might fail." >> $ERROR_LOG
fi
echo "  --> DONE: Resource check complete."

echo "[3/3] Installing Python and essential components..."
for pkg in $PACKAGES; do
    echo "  --> Installing $pkg..."
    # Install each package silently
    if ! opkg install "$pkg" > /dev/null 2>>$ERROR_LOG; then
        echo "      [!] ERROR: Failed to install $pkg"
    fi
done

echo "------------------------------------------"

# Final check: If error log is not empty, show errors
if [ -s "$ERROR_LOG" ]; then
    echo "Finished with the following issues/errors:"
    cat "$ERROR_LOG"
    echo "------------------------------------------"
else
    echo "SUCCESS: Python 3 and Pip have been installed successfully."
    echo "Version: $(python3 --version 2>/dev/null)"
fi

# Cleanup
rm -f $ERROR_LOG

# PeDitX Banner
echo ""
echo "##########################################"
echo "#         MADE BY PeDitX                 #"
echo "##########################################"
echo ""
