#!/bin/bash
# Using set -e to exit immediately if a command fails
set -e

# ==============================================================================
# Telegram VPN Bot Installer (Refactored for SQLAlchemy & Multi-file structure)
# This script automates the setup of the Python environment and systemd service.
# IMPORTANT: This script must be saved with UNIX (LF) line endings.
# ==============================================================================

# --- Variables ---
BOT_DIR="/opt/telegram_vpn_bot"
SERVICE_NAME="telegram_vpn_bot"
PYTHON_ALIAS="python3.10" # You can change this to python3, python3.11, etc. if needed

# --- Stop existing service to prevent issues ---
echo "--> Stopping any existing service..."
# Add '|| true' to prevent the script from exiting if the service doesn't exist
systemctl stop ${SERVICE_NAME}.service >/dev/null 2>&1 || true

# --- 1. System Dependencies ---
echo "--> [1/8] Updating package lists and installing dependencies..."
apt-get update
# Install all dependencies in one command, including the crucial python3-venv package
apt-get install -y --no-install-recommends ${PYTHON_ALIAS} ${PYTHON_ALIAS}-venv curl

# --- 2. Create Directory Structure ---
echo "--> [2/8] Creating bot directory at ${BOT_DIR}..."
mkdir -p ${BOT_DIR}

# --- 3. Create Python Virtual Environment ---
echo "--> [3/8] Creating Python virtual environment..."
${PYTHON_ALIAS} -m venv ${BOT_DIR}/venv

# --- 4. Install Python Libraries ---
echo "--> [4/8] Activating virtual environment and installing required libraries..."
# Use a subshell to avoid issues with activate/deactivate
(
  source ${BOT_DIR}/venv/bin/activate
  pip install --upgrade pip
  # Added SQLAlchemy for the new database structure
  pip install python-telegram-bot==21.0.1 requests jdatetime SQLAlchemy
)

# --- 5. Get Admin ID and Create Data Files ---
echo "--> [5/8] Setting up data files..."
# Get Root Admin ID first, as it's needed for admins.json
read -p "Enter your ROOT_ADMIN_CHAT_ID: " ROOT_ADMIN_CHAT_ID

echo "--> Creating required config files..."
# users.json and orders.json are no longer needed, they are in the database now.
touch ${BOT_DIR}/plans.json
touch ${BOT_DIR}/settings.json
touch ${BOT_DIR}/tickets.json

echo "--> Setting initial root admin in admins.json..."
echo "[${ROOT_ADMIN_CHAT_ID}]" > ${BOT_DIR}/admins.json

# --- 6. Get Bot Token and Create Service ---
echo "--> [6/8] Creating systemd service file..."
# Now get the bot token
read -p "Enter your BOT_TOKEN: " BOT_TOKEN

cat > /etc/systemd/system/${SERVICE_NAME}.service << EOL
[Unit]
Description=Telegram Bot Service (${SERVICE_NAME})
After=network.target

[Service]
User=root
Group=root
WorkingDirectory=${BOT_DIR}
# The main script is now main.py
ExecStart=${BOT_DIR}/venv/bin/python ${BOT_DIR}/main.py
Restart=always
RestartSec=5

# Environment variables for the bot
Environment="BOT_TOKEN=${BOT_TOKEN}"
Environment="ROOT_ADMIN_CHAT_ID=${ROOT_ADMIN_CHAT_ID}"

[Install]
WantedBy=multi-user.target
EOL

# --- 7. Copy Bot Scripts ---
echo "--> [7/8] Locating and copying bot project files..."
PROJECT_FILES=("main.py" "database_models.py" "db_utils.py" "panel_manager.py")
COPIED_COUNT=0

for FILE in "${PROJECT_FILES[@]}"; do
    if [ -f "$FILE" ]; then
        cp "$FILE" "${BOT_DIR}/$FILE"
        echo "    -> '$FILE' copied successfully."
        ((COPIED_COUNT++))
    else
        echo "    -> WARNING: '$FILE' not found in the current directory. Skipping."
    fi
done

if [ "$COPIED_COUNT" -ne "${#PROJECT_FILES[@]}" ]; then
    echo "--> CRITICAL WARNING: Not all project files were found."
    echo "--> Please ensure all four .py files are in the same directory as this script."
    echo "--> You may need to copy the missing files to ${BOT_DIR} manually!"
fi


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
echo "Your bot is now set up as a system service named '${SERVICE_NAME}'."
echo "The script has automatically configured your secrets and copied the project files."
echo "The database 'vpn_bot.db' will be created automatically on the first start."
echo ""
echo "You can start the bot with the command:"
echo "    sudo systemctl start ${SERVICE_NAME}"
echo ""
echo "Useful commands:"
echo "    - To check the bot's status: sudo systemctl status ${SERVICE_NAME}"
echo "    - To see live logs: sudo journalctl -u ${SERVICE_NAME} -f"
echo "    - To restart the bot after code changes: sudo systemctl restart ${SERVICE_NAME}"
echo ""
echo "Cleaning up installer script in 5 seconds..."

# --- Final Cleanup ---
# This runs in the background to allow the main script to exit cleanly.
# It deletes the installer script itself.
( sleep 5 && rm -- "$0" ) &

