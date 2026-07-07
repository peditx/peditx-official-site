#!/bin/sh
# PeDitXOS - Self Update UI
# Updates tools.json AND all scripts from remote

REMOTE_BASE="https://raw.githubusercontent.com/peditx/peditx-official-site/main/tools"
LOCAL_PATH="/etc/peditxos/scripts"
TOOLS_JSON="/etc/peditxos/tools.json"

echo "=== PeDitXOS Self Update ==="

# Update tools.json
echo "Updating tools.json..."
if wget -q "$REMOTE_BASE/tools.json" -O "$TOOLS_JSON.new"; then
    mv "$TOOLS_JSON.new" "$TOOLS_JSON"
    echo "tools.json updated."
else
    echo "ERROR: Failed to download tools.json"
    rm -f "$TOOLS_JSON.new"
    exit 1
fi

# Parse scripts to update from tools.json
if ! command -v jq >/dev/null 2>&1; then
    echo "ERROR: jq is required but not installed."
    exit 1
fi

SCRIPTS=$(jq -r '.tools[] | select(.script != null) | .script' "$TOOLS_JSON")
UPDATED=0
FAILED=0

for script in $SCRIPTS; do
    echo -n "Updating $script... "
    REMOTE_URL="$REMOTE_BASE/$script"
    LOCAL_DIR="$LOCAL_PATH/$(dirname "$script")"
    LOCAL_FILE="$LOCAL_PATH/$script"
    
    mkdir -p "$LOCAL_DIR"
    if wget -q "$REMOTE_URL" -O "$LOCAL_FILE.tmp"; then
        chmod +x "$LOCAL_FILE.tmp"
        mv "$LOCAL_FILE.tmp" "$LOCAL_FILE"
        echo "OK"
        UPDATED=$((UPDATED + 1))
    else
        echo "FAILED"
        rm -f "$LOCAL_FILE.tmp"
        FAILED=$((FAILED + 1))
    fi
done

echo ""
echo "=== Update Complete ==="
echo "Updated: $UPDATED scripts"
echo "Failed: $FAILED scripts"
