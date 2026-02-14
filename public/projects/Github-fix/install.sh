#!/bin/sh

# Project: github-fix
# Version: 4.0 (PeDitX Store - Smart Refresh Edition)
# Author: PeDitX Style Integration
# Description: Professional GitHub mirror selector with Proxy-Bypass and Auto-Purge

DEBUG_LOG="/tmp/github_fix_debug.log"
rm -f $DEBUG_LOG

echo "----------------------------------------------------"
echo "          github-fix: PeDitX Store Edition          "
echo "----------------------------------------------------"

# --- 1. Environment & Dependency Check ---
echo -n "1. Preparing environment and dependencies... "
{
    if ! command -v curl >/dev/null; then
        opkg update && opkg install curl ca-bundle
    fi
    
    # Identify the physical WAN interface to bypass transparent proxies during testing
    WAN_DEV=$(ip route | grep default | awk '{print $5}' | head -n 1)
} >> $DEBUG_LOG 2>&1
echo "Done."

# --- 2. Purge Existing Configuration (Prevention of Duplicates) ---
echo -n "2. Cleaning old configurations & traces... "
{
    # 1. Remove existing github-fix blocks from the profile file
    sed -i '/# GITHUB_FIX_START/,/# GITHUB_FIX_END/d' /etc/profile

    # 2. Locate and remove all previous Git 'insteadOf' rules pointing to github.com
    git config --global --get-regexp insteadof | grep "github.com" | awk '{print $1}' | while read -r section; do
        git config --global --remove-section "$section"
    done
} >> $DEBUG_LOG 2>&1
echo "Done."

# --- 3. Mirror Discovery (Direct ISP Test Mode) ---
echo -n "3. Benchmarking mirrors (Direct ISP Mode)... "
{
    MIRRORS="https://ghproxy.com https://mirror.ghproxy.com https://gh-proxy.com https://ghproxy.net https://gh.api.99988866.xyz"
    TEST_URL="https://github.com/favicon.ico"
    BEST_MIRROR=""
    MIN_TIME=999

    for m in $MIRRORS; do
        # Use --interface to force connection through WAN (bypassing Passwall/VPN)
        CURL_CMD="curl -o /dev/null -s -w %{http_code} %{time_total} --connect-timeout 2"
        if [ -z "$WAN_DEV" ]; then
            RES=$($CURL_CMD "$m/$TEST_URL")
        else
            RES=$($CURL_CMD --interface "$WAN_DEV" "$m/$TEST_URL")
        fi

        # Sanitize output: remove hidden carriage returns or newlines for stable calculations
        CODE=$(echo "$RES" | cut -d' ' -f1 | tr -d '\r\n')
        TIME=$(echo "$RES" | cut -d' ' -f2 | tr -d '\r\n')

        if [ "$CODE" = "200" ]; then
            # Floating point comparison using awk
            is_faster=$(awk "BEGIN {print ($TIME < $MIN_TIME)}")
            if [ "$is_faster" = "1" ]; then
                MIN_TIME=$TIME
                BEST_MIRROR=$m
            fi
        fi
    done
} >> $DEBUG_LOG 2>&1

if [ -z "$BEST_MIRROR" ]; then
    echo "FAILED!"
    echo "ERROR: All mirrors are blocked or ISP is down. Check $DEBUG_LOG"
    exit 1
fi
echo "Done. (Best: $BEST_MIRROR)"

# --- 4. Injection of New Configuration ---
echo -n "4. Injecting fresh wrappers & Git rules... "
{
    # Inject new block into /etc/profile
    cat << EOF >> /etc/profile
# GITHUB_FIX_START
export GH_FIX_MIRROR="$BEST_MIRROR"

curl() {
    case "\$*" in
        *github.com*|*githubusercontent.com*)
            local new_args=""
            for arg in "\$@"; do
                case "\$arg" in
                    http*) arg="\$GH_FIX_MIRROR/\$arg" ;;
                esac
                new_args="\$new_args \$arg"
            done
            command curl -L \$new_args ;;
        *) command curl "\$@" ;;
    esac
}

wget() {
    case "\$*" in
        *github.com*|*githubusercontent.com*)
            local new_args=""
            for arg in "\$@"; do
                case "\$arg" in
                    http*) arg="\$GH_FIX_MIRROR/\$arg" ;;
                esac
                new_args="\$new_args \$arg"
            done
            command wget \$new_args ;;
        *) command wget "\$@" ;;
    esac
}
# GITHUB_FIX_END
EOF

    # Apply global Git redirect for the newly selected mirror
    git config --global url."$BEST_MIRROR/https://github.com/".insteadOf "https://github.com/"
} >> $DEBUG_LOG 2>&1
echo "Done."

# --- 5. Finalizing ---
echo -n "5. Cleaning up temporary installer... "
{
    rm -f /tmp/install.sh
} >> $DEBUG_LOG 2>&1
echo "Done."

echo "----------------------------------------------------"
echo "  Refresh Complete! Mirror updated to latest.       "
echo "  Made By : PeDitX | RECONNECT SSH TO APPLY         "
echo "----------------------------------------------------"