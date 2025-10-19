#!/bin/bash
# Using set -e to exit immediately if a command fails
set -e

# ==============================================================================
# Telegram VPN Bot Installer (Self-Downloading Version)
# This script downloads all necessary project files from a predefined URL
# and then sets up the Python environment and systemd service.
# ==============================================================================

# --- Variables (Restored original project names) ---
BOT_DIR="/opt/peditx_bot"
SERVICE_NAME="peditx_bot"
PYTHON_ALIAS="python3.10"
# --- URL for project files ---
BASE_URL="https://peditx.ir/projects/bot"

# --- Stop existing service to prevent issues ---
echo "--> Stopping any existing service..."
systemctl stop ${SERVICE_NAME}.service >/dev/null 2>&1 || true

# --- 1. System Dependencies ---
echo "--> [1/8] Updating package lists and installing dependencies..."
apt-get update
apt-get install -y --no-install-recommends ${PYTHON_ALIAS} ${PYTHON_ALIAS}-venv curl

# --- 2. Create Directory Structure ---
echo "--> [2/8] Creating bot directory at ${BOT_DIR}..."
mkdir -p ${BOT_DIR}

# --- 3. Create Python Virtual Environment ---
echo "--> [3/8] Creating Python virtual environment..."
${PYTHON_ALIAS} -m venv ${BOT_DIR}/venv

# --- 4. Install Python Libraries ---
echo "--> [4/8] Activating virtual environment and installing required libraries..."
(
  source ${BOT_DIR}/venv/bin/activate
  pip install --upgrade pip
  pip install python-telegram-bot==21.0.1 requests jdatetime SQLAlchemy
)

# --- 5. Get Admin ID and Create Data Files ---
echo "--> [5/8] Setting up data files..."
read -p "Enter your ROOT_ADMIN_CHAT_ID: " ROOT_ADMIN_CHAT_ID

echo "--> Creating required config files... (users.json and orders.json are now in the database)"
touch ${BOT_DIR}/plans.json
touch ${BOT_DIR}/settings.json
touch ${BOT_DIR}/tickets.json

echo "--> Setting initial root admin in admins.json..."
echo "[${ROOT_ADMIN_CHAT_ID}]" > ${BOT_DIR}/admins.json

# --- 6. Get Bot Token and Create Service ---
echo "--> [6/8] Creating systemd service file..."
read -p "Enter your BOT_TOKEN: " BOT_TOKEN

cat > /etc/systemd/system/${SERVICE_NAME}.service << EOL
[Unit]
Description=PeDitX Telegram Bot Maker
After=network.target

[Service]
User=root
Group=root
WorkingDirectory=${BOT_DIR}
ExecStart=${BOT_DIR}/venv/bin/python ${BOT_DIR}/main.py
Restart=always
RestartSec=5

Environment="BOT_TOKEN=${BOT_TOKEN}"
Environment="ROOT_ADMIN_CHAT_ID=${ROOT_ADMIN_CHAT_ID}"

[Install]
WantedBy=multi-user.target
EOL

# --- 7. Download Bot Scripts from URL ---
echo "--> [7/8] Downloading bot project files from the server..."
PROJECT_FILES=("main.py" "database_models.py" "db_utils.py" "panel_manager.py")
DOWNLOAD_COUNT=0

for FILE in "${PROJECT_FILES[@]}"; do
    FILE_URL="${BASE_URL}/${FILE}"
    DEST_PATH="${BOT_DIR}/${FILE}"
    echo "    -> Downloading '${FILE}'..."
    # Use curl to download the file. -sS for silent with errors, -f to fail on server errors, -L to follow redirects.
    if curl -sSfL "${FILE_URL}" -o "${DEST_PATH}"; then
        echo "    -> '${FILE}' downloaded successfully."
        ((DOWNLOAD_COUNT++))
    else
        echo "    -> CRITICAL ERROR: Failed to download '${FILE}' from ${FILE_URL}"
        echo "    -> Please check the URL and your internet connection. Aborting installation."
        exit 1
    fi
done

echo "--> All project files downloaded."

# --- 8. Final Steps ---
echo "--> [8/8] Reloading systemd daemon and enabling the service..."
systemctl daemon-reload
systemctl enable ${SERVICE_NAME}.service

# --- Completion Message ---
echo ""
echo "======================================================"
echo "✅ Installation Complete!"
echo "======================================================"
echo ""
echo "The script has downloaded all necessary files and configured the service."
echo "The database 'vpn_bot.db' will be created automatically on the first start."
echo ""
echo "You can start the bot with the command:"
echo "    sudo systemctl start ${SERVICE_NAME}"
echo ""
echo "Useful commands:"
echo "    - To check the bot's status: sudo systemctl status ${SERVICE_NAME}"
echo "    - To see live logs: sudo journalctl -u ${SERVICE_NAME} -f"
echo "    - To restart the bot: sudo systemctl restart ${SERVICE_NAME}"
echo ""
echo "Cleaning up installer script in 5 seconds..."

# --- Final Cleanup ---
# This runs in the background to delete the installer script itself after completion.
( sleep 5 && rm -- "$0" ) &


