#!/bin/sh

# Project: github-fix
# Version: 2.0 (PeDitX Store Professional)
# Description: Professional Uninstaller

DEBUG_LOG="/tmp/github_fix_debug.log"

echo "----------------------------------------------------"
echo "          github-fix: Uninstalling...               "
echo "----------------------------------------------------"

# --- 1. Clean Profile Wrappers ---
echo -n "1. Removing system-wide profile wrappers... "
{
    sed -i '/# GITHUB_FIX_START/,/# GITHUB_FIX_END/d' /etc/profile
} >> $DEBUG_LOG 2>&1
echo "Done."

# --- 2. Clean Git Configurations ---
echo -n "2. Resetting global Git configurations... "
{
    # Identify and remove any url.*.insteadof that points to a mirror
    git config --global --get-regexp insteadof | grep "github.com" | while read -r line; do
        section=$(echo "$line" | awk '{print $1}')
        git config --global --unset "$section"
    done
} >> $DEBUG_LOG 2>&1
echo "Done."

# --- 3. Finalize ---
echo -n "3. Cleaning up uninstall traces... "
{
    rm -f /tmp/uninstall.sh
} >> $DEBUG_LOG 2>&1
echo "Done."

echo "----------------------------------------------------"
echo "  GitHub Fix Uninstalled Successfully. (PeDitX)     "
echo "----------------------------------------------------"