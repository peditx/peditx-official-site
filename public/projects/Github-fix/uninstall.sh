#!/bin/sh

# Project: github-fix
# Version: 4.0
# Description: Professional Uninstaller (English Edition)

DEBUG_LOG="/tmp/github_fix_debug.log"

echo "----------------------------------------------------"
echo "          github-fix: Uninstalling...               "
echo "----------------------------------------------------"

# --- 1. Clean Profile Wrappers ---
echo -n "1. Removing system-wide profile wrappers... "
{
    # Delete the configuration block from /etc/profile
    sed -i '/# GITHUB_FIX_START/,/# GITHUB_FIX_END/d' /etc/profile
} >> $DEBUG_LOG 2>&1
echo "Done."

# --- 2. Clean Git Configurations ---
echo -n "2. Resetting global Git configurations... "
{
    # Identify and remove any url.*.insteadof that points to github.com
    git config --global --get-regexp insteadof | grep "github.com" | awk '{print $1}' | while read -r section; do
        git config --global --remove-section "$section"
    done
} >> $DEBUG_LOG 2>&1
echo "Done."

# --- 3. Cleanup ---
echo -n "3. Cleaning up uninstall traces... "
{
    rm -f /tmp/uninstall.sh
} >> $DEBUG_LOG 2>&1
echo "Done."

echo "----------------------------------------------------"
echo "  GitHub Fix removed. System restored to default.   "
echo "----------------------------------------------------"