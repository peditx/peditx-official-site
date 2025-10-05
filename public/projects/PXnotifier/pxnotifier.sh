#!/bin/sh

# =================================================================================
# Professional LuCI App Builder Script (v60 - THE REAL FINAL VERSION)
# =================================================================================
# This version fixes the final critical bug where the latency was calculated
# using the wrong curl variable ('time_connect' instead of 'time_starttransfer').
# This ensures a real-world latency is measured, fixing the "incorrect ping" issue.
# This is the definitive, final, stable, and correct implementation.
# =================================================================================

# --- Helper Functions ---
log_info() { echo "INFO: $1"; }
log_success() { echo "SUCCESS: $1"; }
log_error() { echo "ERROR: $1"; exit 1; }

# --- Main Logic ---
log_info "Starting the PXNotifier application builder (v60 - The Real Final Version)..."
echo "--------------------------------------------------"

# 1. Install Dependencies
log_info "Installing dependencies (curl, luci)..."
opkg update >/dev/null
opkg install curl luci
log_success "Dependencies installed."
echo ""

# 2. Create UCI configuration file
UCI_CONFIG_PATH="/etc/config/pxnotifier"
log_info "Creating UCI configuration file at $UCI_CONFIG_PATH..."
cat << EOF > "$UCI_CONFIG_PATH"
config notifier 'global'
	option enabled '0'
	option service 'ntfy'
	option ntfy_topic ''
	option telegram_bot_token ''
	option telegram_chat_id ''
	option whatsapp_phone_num ''
	option whatsapp_api_key ''

EOF
log_success "UCI config file created."
echo ""

# 3. Create a NEW, INDEPENDENT LuCI Controller file
CONTROLLER_PATH="/usr/lib/lua/luci/controller/pxnotifier.lua"
log_info "Creating new, independent LuCI controller at $CONTROLLER_PATH..."
mkdir -p $(dirname "$CONTROLLER_PATH")
cat << 'EOF' > "$CONTROLLER_PATH"
module("luci.controller.pxnotifier", package.seeall)

function index()
	entry({"admin", "peditxos"}, nil, "PeDitXOS Tools", 40).dependent = false
	entry({"admin", "peditxos", "pxnotifier"}, cbi("peditxos/pxnotifier"), "PXNotifier", 99).dependent = true
	entry({"admin", "peditxos", "pxnotifier", "test"}, call("action_test")).leaf = true
end

function action_test()
    -- We call the monitor script with a 'test' argument
    luci.sys.call("/usr/bin/monitor_passwall.sh test >/dev/null 2>&1 &")
    luci.http.redirect(luci.dispatcher.build_url("admin", "peditxos", "pxnotifier"))
end
EOF
log_success "Independent LuCI controller created successfully."
echo ""

# 4. Create LuCI CBI Model/View file
CBI_PATH="/usr/lib/lua/luci/model/cbi/peditxos/pxnotifier.lua"
log_info "Creating LuCI settings page model at $CBI_PATH..."
mkdir -p $(dirname "$CBI_PATH")
cat << 'EOF' > "$CBI_PATH"
m = Map("pxnotifier", "PXNotifier Settings",
"Configure how you want to receive alerts about your internet connection status. After saving, the system will check the connection every minute.<br/><strong>Note:</strong> ntfy and WhatsApp alerts are sent via your main internet connection (WAN) to ensure delivery during outages.")

s = m:section(TypedSection, "notifier", "")
s.addremove = false
s.anonymous = true

enabled = s:option(Flag, "enabled", "Enable Notifier Service")
enabled.rmempty = false

service = s:option(ListValue, "service", "Notification Service")
service:value("ntfy", "ntfy (Recommended for outage alerts)")
service:value("whatsapp", "WhatsApp (Recommended for outage alerts)")
service:value("telegram", "Telegram Bot")
service.rmempty = false

ntfy_topic = s:option(Value, "ntfy_topic", "ntfy Topic")
ntfy_topic:depends("service", "ntfy")
ntfy_topic.description = "Enter your unique ntfy.sh topic name. If you leave this blank, a random one will be generated for you on save. Visit <a href='https://ntfy.sh' target='_blank'>ntfy.sh</a> to learn more."

telegram_bot_token = s:option(Value, "telegram_bot_token", "Telegram Bot Token")
telegram_bot_token:depends("service", "telegram")
telegram_bot_token.description = "Create a new bot with <a href='https://t.me/BotFather' target='_blank'>@BotFather</a> on Telegram to get your token."

telegram_chat_id = s:option(Value, "telegram_chat_id", "Telegram Chat ID")
telegram_chat_id:depends("service", "telegram")
telegram_chat_id.description = "Get your personal Chat ID from <a href='https://t.me/userinfobot' target='_blank'>@userinfobot</a> on Telegram."

whatsapp_phone_num = s:option(Value, "whatsapp_phone_num", "WhatsApp Phone Number")
whatsapp_phone_num:depends("service", "whatsapp")
whatsapp_phone_num.description = "Your phone number including the country code (e.g., 989123456789)."

whatsapp_api_key = s:option(Value, "whatsapp_api_key", "CallMeBot API Key")
whatsapp_api_key:depends("service", "whatsapp")
whatsapp_api_key.description = "Follow the instructions on the <a href='https://www.callmebot.com/blog/whatsapp-text-messages/' target='_blank'>CallMeBot website</a> to get your API key."

-- Test Button Section
local test_url = luci.dispatcher.build_url("admin", "peditxos", "pxnotifier", "test")
local test_button = s:option(DummyValue, "_test_section", "<h3>Test Settings</h3>")
test_button.nolabel = true
test_button.description = string.format([[
<p><strong>Important:</strong> You must click 'Save & Apply' below to save any changes before testing.</p>
<a href="%s" class="cbi-button cbi-button-apply">Send Test Notification</a>
<p style="font-size: 0.8em; color: #666; margin-top: 10px;">This will send a notification with the <strong>current live status</strong> of your connection.</p>
]], test_url)


function m.on_after_commit(self)
    -- Auto-generate ntfy topic if empty
    local uci = require "luci.model.uci".cursor()
    local service = uci:get("pxnotifier", "global", "service")
    local topic = uci:get("pxnotifier", "global", "ntfy_topic")
    if service == "ntfy" and (topic == nil or topic == "") then
        topic = "passwall-alert-" .. luci.sys.uniqueid(8)
        uci:set("pxnotifier", "global", "ntfy_topic", topic)
        uci:commit("pxnotifier")
    end
end

return m
EOF
log_success "LuCI settings page model created."
echo ""

# 5. Create the SINGLE, UNIFIED backend script with the FINAL, CORRECT, user-approved logic
MONITOR_SCRIPT_PATH="/usr/bin/monitor_passwall.sh"
log_info "Creating unified backend script with final correct logic..."

cat << 'EOF' > "$MONITOR_SCRIPT_PATH"
#!/bin/sh
HIGH_PING_THRESHOLD=1500
STATUS_FILE="/tmp/passwall_last_status.log"
CONFIG="pxnotifier"
UCI_CMD="/sbin/uci"
CURL_CMD="/usr/bin/curl"
PGREP_CMD="/usr/bin/pgrep"
AWK_CMD="/usr/bin/awk"
CUT_CMD="/usr/bin/cut"
TR_CMD="/usr/bin/tr"

# urlencode function for APIs
urlencode() {
    data_string="${1}"; result_string=""; c=""
    while [ -n "$data_string" ]; do
        c=${data_string%"${data_string#?}"}; data_string=${data_string#?}
        case $c in
            [-_.~a-zA-Z0-9] ) result_string="$result_string$c" ;;
            * ) result_string="$result_string$(printf '%%%02x' "'$c")" ;;
        esac
    done
    echo "$result_string"
}

send_notification() {
    message="$1"; full_status="$2"; is_test="$3"
    enabled=$($UCI_CMD get $CONFIG.global.enabled 2>/dev/null)
    if [ "$enabled" != "1" ]; then return; fi
    service=$($UCI_CMD get $CONFIG.global.service)
    message_enc=$(urlencode "$message")
    wan_iface=$($UCI_CMD get network.wan.ifname 2>/dev/null)
    curl_opts=""
    if [ -n "$wan_iface" ]; then
        curl_opts="--interface $wan_iface"
    fi
    case "$service" in
        "ntfy")
            topic=$($UCI_CMD get $CONFIG.global.ntfy_topic)
            [ -n "$topic" ] && $CURL_CMD $curl_opts -s -d "$message" "ntfy.sh/$topic" >/dev/null ;;
        "telegram")
            token=$($UCI_CMD get $CONFIG.global.telegram_bot_token)
            chat_id=$($UCI_CMD get $CONFIG.global.telegram_chat_id)
            [ -n "$token" ] && [ -n "$chat_id" ] && $CURL_CMD -s -X POST "https://api.telegram.org/bot${token}/sendMessage" -d "chat_id=${chat_id}" -d "text=${message_enc}" >/dev/null ;;
        "whatsapp")
            phone=$($UCI_CMD get $CONFIG.global.whatsapp_phone_num)
            apikey=$($UCI_CMD get $CONFIG.global.whatsapp_api_key)
            [ -n "$phone" ] && [ -n "$apikey" ] && $CURL_CMD $curl_opts -s "https://api.callmebot.com/whatsapp.php?phone=${phone}&text=${message_enc}&apikey=${apikey}" >/dev/null ;;
    esac
    # Only update the status file if it's not a test run
    if [ "$is_test" != "1" ]; then
        echo -n "$full_status" >"$STATUS_FILE"
    fi
}

check_passwall_running() {
    if $PGREP_CMD -f "xray" >/dev/null || $PGREP_CMD -f "v2ray" >/dev/null || $PGREP_CMD -f "sing-box" >/dev/null; then
        return 0
    fi
    return 1
}

get_current_node_id() {
    node=""
    node=$($UCI_CMD get passwall2.@global[0].node 2>/dev/null)
    if [ -z "$node" ]; then return 1; fi
    default_node=""
    default_node=$($UCI_CMD get passwall2."$node".default_node 2>/dev/null)
    if [ -n "$default_node" ]; then
        echo "$default_node"
    else
        echo "$node"
    fi
}

# --- Main Logic ---
IS_TEST_RUN=0
if [ "$1" = "test" ]; then
    IS_TEST_RUN=1
fi

if [ -f "$STATUS_FILE" ]; then
    LAST_STATUS_FULL=$(cat "$STATUS_FILE")
else
    LAST_STATUS_FULL="UNKNOWN"
fi

CURRENT_STATUS=""
display_name="N/A"
PING_MS=""

if ! check_passwall_running; then
    CURRENT_STATUS="SERVICE_DOWN"
else
    final_node=$(get_current_node_id)
    if [ -z "$final_node" ]; then
        CURRENT_STATUS="NO_NODE_SELECTED"
    else
        node_remarks=$($UCI_CMD get passwall2."$final_node".remarks 2>/dev/null)
        server_address=$($UCI_CMD get passwall2."$final_node".address 2>/dev/null)
        if [ -n "$node_remarks" ]; then
            display_name="$node_remarks"
        else
            display_name="$server_address"
        fi

        # The REAL connection test, using the user's proven logic
        tmp_port=$(/usr/share/passwall2/app.sh get_new_port 61080 tcp,udp)
        /usr/share/passwall2/app.sh run_socks flag="pxnotifier_monitor" node=${final_node} bind=127.0.0.1 socks_port=${tmp_port} config_file=pxnotifier_monitor.json >/dev/null 2>&1 &
        sleep 1
        
        test_url=$($UCI_CMD get passwall2.@global[0].url_test_node 2>/dev/null)
        if [ -z "$test_url" ]; then test_url="https://www.google.com/generate_204"; fi

        # THIS IS THE CORRECTED CURL COMMAND WITH time_starttransfer
        result=$($CURL_CMD --connect-timeout 5 -o /dev/null -I -skL -w "%{http_code}:%{time_starttransfer}" -x "socks5h://127.0.0.1:${tmp_port}" "$test_url")
        
        # Cleanup
        $PGREP_CMD -af "pxnotifier_monitor" | $AWK_CMD '{print $1}' | xargs kill -9 >/dev/null 2>&1
        rm -f "/tmp/etc/passwall2/pxnotifier_monitor.json"

        http_code=$(echo "$result" | $CUT_CMD -d':' -f1)
        latency_sec=$(echo "$result" | $TR_CMD ',' '.' | $CUT_CMD -d':' -f2)

        if [ "$http_code" = "204" ] || [ "$http_code" = "200" ]; then
            PING_MS=$($AWK_CMD -v n="$latency_sec" 'BEGIN { printf "%.0f", n * 1000 }')
            if [ "$PING_MS" -gt "$HIGH_PING_THRESHOLD" ]; then
                CURRENT_STATUS="HIGH_PING"
            else
                CURRENT_STATUS="CONNECTED"
            fi
        else
            CURRENT_STATUS="CONNECTION_FAILED"
        fi
    fi
fi

CURRENT_STATUS_FULL="${CURRENT_STATUS}:${display_name}"

# If this is a test run, ALWAYS send the notification
if [ "$IS_TEST_RUN" = "1" ]; then
    case "$CURRENT_STATUS" in
        "SERVICE_DOWN")
            send_notification "ℹ️ Test: Passwall service is currently STOPPED." "$CURRENT_STATUS_FULL" 1 ;;
        "NO_NODE_SELECTED")
            send_notification "ℹ️ Test: Passwall is running but no server is selected." "$CURRENT_STATUS_FULL" 1 ;;
        "CONNECTION_FAILED")
            send_notification "ℹ️ Test: Current connection via '$display_name' is FAILED." "$CURRENT_STATUS_FULL" 1 ;;
        "HIGH_PING")
            send_notification "ℹ️ Test: Current connection via '$display_name' is SLOW (Latency: ${PING_MS}ms)." "$CURRENT_STATUS_FULL" 1 ;;
        "CONNECTED")
            send_notification "ℹ️ Test: Current connection via '$display_name' is OK (Latency: ${PING_MS}ms)." "$CURRENT_STATUS_FULL" 1 ;;
    esac
else
    # This is a regular run, so only notify on status change
    if [ "$LAST_STATUS_FULL" != "$CURRENT_STATUS_FULL" ]; then
        case "$CURRENT_STATUS" in
            "SERVICE_DOWN")
                send_notification "❌ Passwall service is STOPPED!" "$CURRENT_STATUS_FULL" 0 ;;
            "NO_NODE_SELECTED")
                send_notification "⚠️ Passwall is running but no server is selected!" "$CURRENT_STATUS_FULL" 0 ;;
            "CONNECTION_FAILED")
                send_notification "❌ Connection via '$display_name' FAILED!" "$CURRENT_STATUS_FULL" 0 ;;
            "HIGH_PING")
                send_notification "⚠️ Connection via '$display_name' is SLOW (Latency: ${PING_MS}ms)" "$CURRENT_STATUS_FULL" 0 ;;
            "CONNECTED")
                send_notification "✅ Connection via '$display_name' is OK (Latency: ${PING_MS}ms)" "$CURRENT_STATUS_FULL" 0 ;;
        esac
    fi
fi
EOF

# Make the single script executable
chmod +x "$MONITOR_SCRIPT_PATH"

log_success "Unified backend script created with the final correct logic."
echo ""

# 6. Set up the cron job
log_info "Setting up cron job..."
(crontab -l 2>/dev/null | grep -v "$MONITOR_SCRIPT_PATH") | crontab -
(crontab -l 2>/dev/null ; echo "*/1 * * * * $MONITOR_SCRIPT_PATH") | crontab -
log_success "Cron job set up successfully."
echo ""

# 7. Clear LuCI cache
log_info "Clearing LuCI cache..."
rm -rf /tmp/luci-cache/*
log_success "LuCI cache cleared."
echo ""

# --- Final Message ---
log_success "PXNotifier application has been successfully installed. All known issues are fixed."
log_info "Log out and log back into LuCI. The page, test button, and monitoring should now work correctly."
echo "--------------------------------------------------"
