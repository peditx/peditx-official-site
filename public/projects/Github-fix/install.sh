#!/bin/sh

# Project: github-fix
# Version: 2.0 (PeDitX Store Professional)
# Author: PeDitX Style Integration

DEBUG_LOG="/tmp/github_fix_debug.log"
rm -f $DEBUG_LOG

echo "----------------------------------------------------"
echo "          github-fix: PeDitX Store Edition          "
echo "----------------------------------------------------"

# --- 1. Environment & Dependency Check ---
echo -n "1. Preparing environment and dependencies... "
{
    # Update certs and install curl if missing
    if ! command -v curl >/dev/null; then
        opkg update && opkg install curl ca-bundle
    fi
} >> $DEBUG_LOG 2>&1
echo "Done."

# --- 2. Mirror Discovery & Benchmarking ---
echo -n "2. Benchmarking GitHub mirrors (Silent Mode)... "
{
    MIRRORS="https://ghproxy.com https://mirror.ghproxy.com https://gh-proxy.com https://ghproxy.net https://gh.api.99988866.xyz"
    TEST_URL="https://github.com/favicon.ico"
    BEST_MIRROR=""
    MIN_TIME=999

    for m in $MIRRORS; do
        # Test each mirror with 3s timeout
        RES=$(curl -o /dev/null -s -w "%{http_code} %{time_total}" --connect-timeout 3 "$m/$TEST_URL")
        CODE=$(echo "$RES" | cut -d' ' -f1)
        TIME=$(echo "$RES" | cut -d' ' -f2)

        if [ "$CODE" = "200" ]; then
            # Compare speeds using awk (Standard OpenWrt tool)
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
    echo "ERROR: No working GitHub mirror found. See $DEBUG_LOG"
    exit 1
fi
echo "Done."
echo "   Selected: $BEST_MIRROR"

# --- 3. Persistent Alias Injection ---
echo -n "3. Injecting smart wrappers into /etc/profile... "
{
    # Remove any existing github-fix blocks to prevent duplicates
    sed -i '/# GITHUB_FIX_START/,/# GITHUB_FIX_END/d' /etc/profile

    # Write the high-performance wrapper
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
} >> $DEBUG_LOG 2>&1
echo "Done."

# --- 4. Git Global Configuration ---
echo -n "4. Optimizing Git core redirect rules... "
{
    # Clean previous git configs
    git config --global --remove-section url."$BEST_MIRROR/https://github.com/" 2>/dev/null
    
    # Apply new redirect
    git config --global url."$BEST_MIRROR/https://github.com/".insteadOf "https://github.com/"
} >> $DEBUG_LOG 2>&1
echo "Done."

# --- 5. Cleanup ---
echo -n "5. Finalizing setup and cleaning temporary files... "
{
    rm -f /tmp/install.sh
} >> $DEBUG_LOG 2>&1
echo "Done."

echo "----------------------------------------------------"
echo "  Setup Finished Successfully. Made By : PeDitX     "
echo "  RECONNECT SSH or run: source /etc/profile         "
echo "----------------------------------------------------"