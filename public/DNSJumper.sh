#!/bin/sh

# DNS Jumper for LuCI - Installer Script v84.0 (Core Functionality Fixes)
# - UI: Added "By PeDitX" subtitle below the main header.
# - CRITICAL FIX: Resolved the backup button functionality by setting the correct href directly during element creation, ensuring the download works on the first click.
# - LOGIC: With the backup fix, the restore functionality is now fully operational.

echo ">>> Installing DNS Jumper (Core Functionality Fixes) - v84.0..."

# --- 0. Full Cleanup ---
echo ">>> Wiping all previous versions for a clean and stable install..."
rm -f /usr/lib/lua/luci/controller/dnsjumper.lua
rm -f /usr/lib/lua/luci/view/dnsjumper/main.htm
rm -f /etc/config/dns_jumper_list.json
rm -f /etc/config/dns_jumper_cache.json
# Clean up temporary log files
rm -f /tmp/dnsjumper_log_tail.pid
rm -f /tmp/dnsjumper_live_log.txt

# --- 1. Install ALL Dependencies (traceroute removed) ---
echo ">>> Installing all necessary dependencies..."
opkg update >/dev/null 2>&1
opkg install luci-base coreutils-base64 uclient-fetch bind-tools ip-full procps-ng-pgrep >/dev/null 2>&1

# --- 2. Create/Update JSON config ---
mkdir -p /etc/config
cat > /etc/config/dns_jumper_list.json << 'EOF'
[
  { "name": "Shecan", "dns1": "178.22.122.100", "dns2": "185.51.200.2", "favorite": true },
  { "name": "Electro", "dns1": "78.157.42.100", "dns2": "78.157.42.101" },
  { "name": "Cloudflare", "dns1": "1.1.1.1", "dns2": "1.0.0.1", "favorite": true },
  { "name": "Google", "dns1": "8.8.8.8", "dns2": "8.8.4.4" }
]
EOF

# --- 3. Create THE ALL-IN-ONE CONTROLLER ---
mkdir -p /usr/lib/lua/luci/controller
cat > /usr/lib/lua/luci/controller/dnsjumper.lua << 'EOF'
module("luci.controller.dnsjumper", package.seeall)

local http = require "luci.http"
local sys = require "luci.sys"
local fs = require "nixio.fs"
local jsonc = require "luci.jsonc"

local DNS_LIST_PATH = "/etc/config/dns_jumper_list.json"
local CACHE_PATH = "/etc/config/dns_jumper_cache.json"
local ONLINE_LIST_URL = "https://raw.githubusercontent.com/peditx/openwrt-dnsjumper/refs/heads/main/.files/lists.json"

-- Live Log Configuration
local PASSWALL_LOG_PATH = "/var/etc/passwall2/acl/default/global.log"
local LOG_PID_PATH = "/tmp/dnsjumper_log_tail.pid"
local LOG_OUTPUT_PATH = "/tmp/dnsjumper_live_log.txt"

local function shellquote(str)
    if str == nil then return "''" end
    return "'" .. tostring(str):gsub("'", "'\\''") .. "'"
end

function index()
    entry({"admin", "peditxos", "dnsjumper"}, template("dnsjumper/main"), _("DNS Jumper"), 70).dependent = true
    entry({"admin", "peditxos", "dnsjumper", "get_list"}, call("action_get_list")).json = true
    entry({"admin", "peditxos", "dnsjumper", "save_list"}, call("action_save_list")).json = true
    entry({"admin", "peditxos", "dnsjumper", "ping"}, call("action_ping")).json = true
    entry({"admin", "peditxos", "dnsjumper", "apply_dns"}, call("action_apply_dns")).json = true
    entry({"admin", "peditxos", "dnsjumper", "get_active"}, call("action_get_active_dns")).json = true
    entry({"admin", "peditxos", "dnsjumper", "get_gateway"}, call("action_get_gateway")).json = true
    entry({"admin", "peditxos", "dnsjumper", "get_cache"}, call("action_get_cache")).json = true
    entry({"admin", "peditxos", "dnsjumper", "save_cache"}, call("action_save_cache")).json = true
    entry({"admin", "peditxos", "dnsjumper", "get_status"}, call("action_get_system_status")).json = true
    entry({"admin", "peditxos", "dnsjumper", "online_update"}, call("action_online_update")).json = true
    entry({"admin", "peditxos", "dnsjumper", "run_diagnostic"}, call("action_run_diagnostic")).json = true 
    entry({"admin", "peditxos", "dnsjumper", "backup"}, call("action_backup"))
    entry({"admin", "peditxos", "dnsjumper", "start_log"}, call("action_start_log")).json = true
    entry({"admin", "peditxos", "dnsjumper", "stop_log"}, call("action_stop_log")).json = true
    entry({"admin", "peditxos", "dnsjumper", "get_live_log"}, call("action_get_live_log")).json = true
end

local function pcall_action(action_func)
    local success, result = pcall(action_func)
    http.prepare_content("application/json")
    if success then
        http.write_json(result)
    else
        http.status(500, "Internal Server Error")
        http.write_json({ success = false, message = "Server script error: " .. tostring(result) })
    end
end

local function get_wan_gateway()
    local cmd = "ip route show default | awk '{print $3}' | head -n1"
    local gateway = sys.exec(cmd)
    if gateway and gateway:match("%S") then
        return gateway:match("([%d%.]+)")
    end
    return nil
end

local function read_json_file(path)
    if not fs.access(path) then return {} end
    local content = fs.readfile(path)
    if not content or content == "" then return {} end
    local s, data = pcall(jsonc.parse, content)
    return (s and type(data) == "table") and data or {}
end

local function write_json_file(path, data_table)
    local s, str = pcall(jsonc.stringify, data_table, true)
    if s and str then
        return fs.writefile(path, str)
    end
    return false
end

function action_get_gateway()
    pcall_action(function()
        local gateway_ip = get_wan_gateway()
        if gateway_ip then return { success = true, gateway_ip = gateway_ip }
        else return { success = false, message = "Could not detect gateway IP." } end
    end)
end

function action_get_list() pcall_action(function() return read_json_file(DNS_LIST_PATH) end) end

function action_get_cache() 
    pcall_action(function() 
        local cache = read_json_file(CACHE_PATH)
        return { pings = cache.pings or {} }
    end) 
end

function action_save_list()
    pcall_action(function()
        local data = http.formvalue("payload")
        local ok, list = pcall(jsonc.parse, data or "")
        if ok and type(list) == "table" and write_json_file(DNS_LIST_PATH, list) then
            return { success = true, message = "List saved." }
        end
        return { success = false, message = "Invalid data or failed to write file." }
    end)
end

function action_save_cache()
    pcall_action(function()
        local data = http.formvalue("payload")
        local ok, cache = pcall(jsonc.parse, data or "")
        if ok and type(cache) == "table" and write_json_file(CACHE_PATH, { pings = cache.pings or {} }) then
            return { success = true }
        end
        return { success = false, message = "Invalid cache format." }
    end)
end

function action_ping()
    pcall_action(function()
        local ip = http.formvalue("ip")
        if not ip or ip == "" then return { success = false, avg = "No IP" } end
        local wan_status_json = sys.exec("ubus call network.interface.wan status")
        local ok, wan_status = pcall(jsonc.parse, wan_status_json or "")
        local ifname = (ok and wan_status) and (wan_status.l3_device or wan_status.device)
        if not ifname then return { success = false, avg = "WAN Error" } end
        
        local cmd = string.format("ping -c 3 -W 2 -I %s %s", shellquote(ifname), shellquote(ip))
        local out = sys.exec(cmd)
        
        local avg = out:match("round%-trip min/avg/max = [%d%.]+/([%d%.]+)/[%d%.]+ ms") or out:match("rtt min/avg/max/[%w%./]+ = [%d%./]+/(%d+%.?%d*)/")
        
        if avg then 
            return { success = true, avg = string.format("%.2f", tonumber(avg)) } 
        else 
            return { success = false, avg = "T/O", output = out } 
        end
    end)
end

function action_apply_dns()
    pcall_action(function()
        local data = http.formvalue("payload")
        local ok, provider = pcall(jsonc.parse, data or "")
        if not ok or type(provider) ~= "table" or not provider.name then return { success = false, message = "Invalid provider data." } end
        sys.exec("uci delete network.wan.dns >/dev/null 2>&1")
        sys.exec("uci set network.wan.peerdns='0'")
        if provider.name == "Modem/Gateway DNS" then
            local gateway_ip = get_wan_gateway()
            if not gateway_ip then return { success = false, message = "Could not detect gateway IP." } end
            sys.exec("uci add_list network.wan.dns=" .. shellquote(gateway_ip))
        else
            if provider.dns1 and provider.dns1:match("%S") then sys.exec("uci add_list network.wan.dns=" .. shellquote(provider.dns1)) end
            if provider.dns2 and provider.dns2:match("%S") then sys.exec("uci add_list network.wan.dns=" .. shellquote(provider.dns2)) end
        end
        sys.exec("(uci commit network && /etc/init.d/network restart && /etc/init.d/dnsmasq restart) >/dev/null 2>&1 &")
        return { success = true, message = provider.name .. " applied." }
    end)
end

function action_get_active_dns()
    pcall_action(function()
        local dns_string = sys.exec("uci get network.wan.dns 2>/dev/null")
        local dns_list = {}
        if dns_string and dns_string:match("%S") then
            for ip in dns_string:gmatch("%S+") do table.insert(dns_list, ip) end
        end
        local type = "custom"
        local gateway_ip = get_wan_gateway()
        if gateway_ip and #dns_list == 1 and dns_list[1] == gateway_ip then type = "gateway" end
        return { success = true, dns = dns_list, type = type }
    end)
end

function action_get_system_status()
    pcall_action(function()
        local ubus_ok = sys.call("ubus -S list network.interface.wan >/dev/null 2>&1") == 0
        local uci_ok = sys.call("uci -S get network.wan >/dev/null 2>&1") == 0
        local dnsmasq_running = sys.call("pgrep -f dnsmasq >/dev/null 2>&1") == 0
        return { success = true, status = { ubus = ubus_ok, uci = uci_ok, dnsmasq = dnsmasq_running } }
    end)
end

function action_online_update()
    pcall_action(function()
        local str = sys.exec("uclient-fetch -qO- --timeout=10 --no-check-certificate " .. shellquote(ONLINE_LIST_URL))
        if str == "" then return { success = false, message = "Download failed." } end
        local ok, online_list = pcall(jsonc.parse, str)
        if not ok then return { success = false, message = "Invalid online list format." } end
        local local_list, local_names, count = read_json_file(DNS_LIST_PATH), {}, 0
        for _, provider in ipairs(local_list) do local_names[provider.name] = true end
        for _, provider in ipairs(online_list) do
            if not local_names[provider.name] then table.insert(local_list, provider); count = count + 1 end
        end
        if write_json_file(DNS_LIST_PATH, local_list) then return { success = true, message = count .. " new providers added." }
        else return { success = false, message = "Failed to save updated list." } end
    end)
end

function action_backup()
    pcall_action(function()
        http.prepare_content("application/json")
        http.header("Content-Disposition", "attachment; filename=\"dns_jumper_backup.json\"")
        http.write(jsonc.stringify(read_json_file(DNS_LIST_PATH), true) or "[]")
    end)
end

function action_run_diagnostic()
    pcall_action(function()
        local data = http.formvalue("payload")
        local ok, p = pcall(jsonc.parse, data or "")
        if not ok or type(p) ~= "table" then return { success = false, output = "Invalid payload" } end
        local dns, target = p.dns, p.target 
        if not (dns and target) then return { success=false, output="Missing parameters." } end
        
        local resolved_ip = target
        local header
        
        if not target:match("^[0-9]+%.[0-9]+%.[0-9]+%.[0-9]+$") then
            local resolve_cmd = string.format("nslookup -timeout=10 %s %s 2>/dev/null", shellquote(target), shellquote(dns))
            local resolve_output = sys.exec(resolve_cmd)
            if not resolve_output:match("Address") then return { success = false, output = "nslookup failed for "..target.."\n\n"..resolve_output } end
            resolved_ip = resolve_output:match("Address: ([%d%.]+)")
            if not resolved_ip then return { success = false, output = "Could not extract IP from nslookup.\n\n"..resolve_output } end
            header = "Running Ping on "..target.." (resolved to "..resolved_ip.." via "..dns..")\n"..string.rep("-", 50).."\n"
        else
            header = "Running Ping on "..target.." (IP Address)\n"..string.rep("-", 50).."\n"
        end

        local final_cmd = string.format("ping -c 4 %s", shellquote(resolved_ip)) 
        return { success = true, output = header .. sys.exec(final_cmd) }
    end)
end

function action_start_log()
    pcall_action(function()
        local existing_pid = fs.readfile(LOG_PID_PATH)
        if existing_pid and existing_pid:match("%S+") then
            sys.exec("kill -9 " .. existing_pid .. " 2>/dev/null")
        end

        fs.writefile(LOG_OUTPUT_PATH, "")
        
        local cmd = string.format("nohup tail -f %s > %s 2>&1 & echo $! > %s", 
            shellquote(PASSWALL_LOG_PATH), 
            shellquote(LOG_OUTPUT_PATH), 
            LOG_PID_PATH)
            
        sys.exec(cmd)
        
        local new_pid = sys.exec("cat " .. LOG_PID_PATH)
        if new_pid and new_pid:match("%S+") then
            return { success = true, message = "Live logging started using nohup (PID: " .. new_pid .. "). Monitoring " .. PASSWALL_LOG_PATH }
        else
            sys.exec("killall tail 2>/dev/null") 
            return { success = false, message = "Failed to start live logging. Check if 'tail' or 'nohup' are missing. Check file permissions on " .. PASSWALL_LOG_PATH }
        end
    end)
end

function action_stop_log()
    pcall_action(function()
        local pid = fs.readfile(LOG_PID_PATH)
        fs.remove(LOG_PID_PATH)
        
        if pid and pid:match("%S+") then
            sys.exec("kill -9 " .. pid)
            return { success = true, message = "Live logging stopped (PID: " .. pid .. " killed)." }
        else
            sys.exec("killall tail 2>/dev/null") 
            return { success = true, message = "No active log tail process found, but all 'tail' processes were killed as a precaution." }
        end
    end)
end

function action_get_live_log()
    pcall_action(function()
        local content = fs.readfile(LOG_OUTPUT_PATH) or ""
        local is_running = fs.access(LOG_PID_PATH) and true or false
        
        return { success = true, log_content = content, is_running = is_running }
    end)
end
EOF

# --- 4. Create Self-Contained View File (Backup Fix & Subtitle) ---
mkdir -p /usr/lib/lua/luci/view
cat > /usr/lib/lua/luci/view/dnsjumper/main.htm << 'EOF'
<%+header%>
<div id="dnsjumper-root">
    <div id="loading-spinner"></div>
</div>

<style>
    /* Theme removed, forced dark theme */
    :root {
        --primary-color: #50fa7b; --secondary-color: #ff79c6; --danger-color: #ff5555; --info-color: #8be9fd; --purple-color: #bd93f9; --warning-color: #f1fa8c;
        --text-color: #f8f8f2; --glass-bg: rgba(40, 42, 54, 0.75); --glass-border: rgba(255, 255, 255, 0.1); --glass-hover-bg: rgba(58, 60, 81, 0.9);
        --ping-good: #50fa7b; --ping-warn: #f1fa8c; --ping-bad: #ff5555;
    }
    
    html, body {
        overflow-x: hidden;
    }

    #dnsjumper-root { 
        width: 100%;
        box-sizing: border-box;
        transition: background-color 0.3s, color 0.3s; 
        color: var(--text-color); 
        margin: 0; 
        padding: 0;
    }
    
    .glass-ui { 
        background: var(--glass-bg); 
        backdrop-filter: blur(10px); 
        -webkit-backdrop-filter: blur(10px); 
        border: 1px solid var(--glass-border); 
        border-radius: 12px; 
        padding: 20px;
        margin-bottom: 25px; 
    }
    
    .status-panels { 
        margin-top: 40px;
        display: grid; 
        grid-template-columns: 1fr 1fr; 
        gap: 20px; 
        margin-bottom: 20px; 
    }

    .dnsjumper-header-container {
        display: block; 
        text-align: center;
        margin-bottom: 20px; 
    }
    
    .dnsjumper-header-container h2 { 
        text-align: center;
        margin-bottom: 5px;
    }

    h2 { font-size: 1.5em; margin: 0; color: var(--info-color); text-shadow: 0 0 5px rgba(139, 233, 253, 0.5); }
    
    .button-group { display: flex; flex-wrap: wrap; justify-content: center; align-items: center; gap: 10px; }
    .cbi-button { font-size: 14px; padding: 10px 20px; font-weight: bold; border-radius: 50px; text-decoration: none !important; display: inline-block; border: 1px solid var(--glass-border); background-color: rgba(0,0,0,0.2); color: var(--text-color); cursor:pointer; transition: all 0.2s; }
    .cbi-button:hover { background-color: var(--glass-hover-bg); transform: translateY(-2px); box-shadow: 0 4px 8px rgba(0,0,0,0.2); }
    .cbi-button.active { background-color: var(--primary-color); color: #282a36; box-shadow: 0 0 10px var(--primary-color); }
    .cbi-button:disabled { cursor: not-allowed; opacity: 0.5; transform: none; box-shadow: none; }

    .management-table { width: 100%; border-collapse: collapse; margin-top: 15px; }
    .management-table th, .management-table td { padding: 12px; text-align: left; border-bottom: 1px solid var(--glass-border); vertical-align: middle; }
    .management-table th { color: var(--secondary-color); }
    tr.active-dns { background-color: rgba(189, 147, 249, 0.15); }
    tr.draggable-row.drag-enabled { cursor: move; }
    tr.dragging { opacity: 0.4; background: var(--purple-color); }
    tr.drag-over { border-bottom: 2px solid var(--primary-color); }
    
    .btn-fav { font-size: 20px; cursor: pointer; background: none; border: none; color: var(--glass-border); padding: 0 10px; transition: color 0.2s; }
    .btn-fav:hover { color: var(--warning-color); }
    .is-fav { color: var(--warning-color); text-shadow: 0 0 10px var(--warning-color); }
    .status-panel { text-align: center; } .status-panel h3 { color: var(--secondary-color); margin-bottom: 10px; }
    .status-panel p { color: var(--primary-color); font-weight: bold; font-size: 1.2em; margin: 0; }
    #system-status-panel { display: flex; justify-content: space-around; gap: 15px; align-items: center; }
    .status-icon { display: inline-block; width: 12px; height: 12px; border-radius: 50%; margin-right: 5px; }
    .status-ok { background-color: var(--primary-color); } .status-error { background-color: var(--danger-color); }
    #loading-spinner { position: fixed; top: 40%; left: 50%; transform: translate(-50%,-50%); border: 8px solid var(--glass-bg); border-top: 8px solid var(--primary-color); border-radius: 50%; width: 60px; height: 60px; animation: spin 1s linear infinite; z-index: 2000; }
    .btn-loading { cursor: not-allowed !important; opacity: 0.7; }
    .btn-loading:before { content: ''; display: inline-block; width: 1em; height: 1em; border-radius: 50%; border: 2px solid currentColor; border-top-color: transparent; animation: spin 0.6s linear infinite; margin-right: 8px; vertical-align: -0.15em; }
    
    .btn-action-group { display: flex; flex-wrap: wrap; gap: 5px; }

    #log-viewer-output {
        background-color:rgba(0,0,0,0.2); padding:15px; border-radius:8px; min-height:200px; max-height: 400px; 
        overflow: auto; margin-top:15px; color:var(--text-color); font-family: monospace;
        white-space: pre-wrap; word-wrap: break-word; line-height: 1.2; font-size: 0.85em;
    }
    
    #log-status-indicator {
        display: inline-block; width: 15px; height: 15px; border-radius: 50%;
        margin-left: 10px; transition: background-color 0.5s;
    }
    .status-red { background-color: var(--danger-color); }
    .status-green { background-color: var(--primary-color); }
    .status-yellow { background-color: var(--warning-color); }

    .pagination-controls { 
        display: flex; flex-wrap: wrap; justify-content: space-between; align-items: center;
        margin-top: 20px; padding-top: 20px; border-top: 1px solid var(--glass-border);
    }
    .page-info { margin: 0 10px; font-weight: bold; }

    .diag-inputs { 
        display: flex; gap: 10px; margin-bottom: 10px; 
    }
    .diag-inputs select, .diag-inputs input {
        flex-grow: 1; width: 50%; box-sizing: border-box;
    }
    
    .modal-overlay {
        position: fixed; top: 0; left: 0; width: 100%; height: 100%;
        background-color: rgba(0, 0, 0, 0.7); backdrop-filter: blur(5px);
        display: none; justify-content: center; align-items: center; z-index: 3000;
    }
    .modal-content {
        background: var(--glass-bg); border: 1px solid var(--glass-border);
        padding: 30px; border-radius: 15px; width: 90%; max-width: 500px;
        box-shadow: 0 10px 30px rgba(0,0,0,0.3);
    }
    .modal-content h3 { color: var(--secondary-color); margin-top: 0; text-align: center; }
    .modal-content .form-group { margin-bottom: 15px; }
    .modal-content label { display: block; margin-bottom: 5px; font-weight: bold; }
    .modal-content input {
        width: 100%; padding: 10px; border-radius: 8px; border: 1px solid var(--glass-border);
        background-color: rgba(0,0,0,0.2); color: var(--text-color); font-size: 1em;
        box-sizing: border-box;
    }
    
    @media (max-width: 768px) {
        .diag-inputs { flex-direction: column; }
        .diag-inputs select, .diag-inputs input { width: 100%; }
        h2 { font-size: 1.3em; }
        .status-panels { grid-template-columns: 1fr; }
        .management-table th:nth-child(3), .management-table td:nth-child(3) { display: none; }
        .management-table th, .management-table td { padding: 8px 4px; }
        .btn-action-group { flex-direction: column; align-items: flex-start; }
        .pagination-controls { flex-direction: column; gap: 15px; }
    }
    @keyframes spin { to { transform: rotate(360deg); } }
</style>
<script type="text/javascript">
'use strict';
(function() {
    window.alert = console.log;
    window.confirm = (msg) => { console.warn("Confirmation dialog blocked:", msg); return true; }; 
    
    const E = (tag, attrs, content) => {
        const el = document.createElement(tag);
        if (typeof attrs === 'object' && attrs !== null) for (const key in attrs) el.setAttribute(key, attrs[key]);
        if (content != null) (Array.isArray(content) ? content : [content]).forEach(node => { if(node) el.append(node) });
        return el;
    };

    const App = {
        state: { 
            dnsList: [], displayList: [], pingCache: {}, gatewayIp: 'N/A', 
            systemStatus: null, activeDNS: null, isDragEnabled: false, 
            currentView: 'all', isLoading: true, 
            draggedProviderId: null,
            isLogRunning: false, logTailInterval: null,
            logOutput: 'Live log viewer ready. Press START to monitor Passwall traffic.',
            currentPage: 1, itemsPerPage: 10, totalPages: 1
        },
        root: document.getElementById('dnsjumper-root'),
        token: '<%=token%>',
        listenersAttached: false,
        API_TIMEOUT_MS: 10000, 

        async init() {
            try {
                const results = await Promise.all([
                    this.fetchAPI('/get_gateway'), this.fetchAPI('/get_cache'), this.fetchAPI('/get_list'), 
                    this.fetchAPI('/get_status'), this.fetchAPI('/get_active'), this.fetchAPI('/get_live_log')
                ]);
                
                const [gatewayRes, cacheData, listData, statusRes, activeRes, logStatus] = results;

                this.state.gatewayIp = gatewayRes?.success ? gatewayRes.gateway_ip : 'Not Found';
                this.state.pingCache = (cacheData && typeof cacheData.pings === 'object') ? cacheData.pings : {};
                this.state.dnsList = Array.isArray(listData) ? listData : [];
                this.state.systemStatus = statusRes?.success ? statusRes.status : null;
                this.state.activeDNS = activeRes?.success ? activeRes : null;
                
                if (logStatus && logStatus.is_running) {
                    this.state.isLogRunning = true;
                    this.state.logOutput = logStatus.log_content || "Live logging is running...";
                } else if (logStatus) {
                    this.state.logOutput = logStatus.log_content || this.state.logOutput;
                }
            } catch (error) { 
                console.error("Initialization error (Fatal):", error); 
                this.state.dnsList = [];
                this.state.gatewayIp = 'Error';
            }
            finally {
                this.state.isLoading = false;
                this.addEventListeners(); // Setup listeners ONCE
                this.render();
                if (this.state.isLogRunning) this.startLogPolling();
            }
        },

        fetchAPI(endpoint, options = {}) {
            return new Promise(resolve => {
                const timeoutId = setTimeout(() => {
                    console.error(`API Timeout: ${endpoint} took longer than ${this.API_TIMEOUT_MS / 1000}s.`);
                    resolve(null); 
                }, this.API_TIMEOUT_MS);

                const url = '<%=luci.dispatcher.build_url("admin/peditxos/dnsjumper")%>' + endpoint;
                const method = options.method || 'GET';
                let body = { token: this.token, ...options.body };
                
                XHR[method.toLowerCase()](url, body, (x, res) => {
                    clearTimeout(timeoutId);
                    if (x && x.status >= 200 && x.status < 300 && res) resolve(res);
                    else { console.error(`API Error: ${endpoint} returned status ${x ? x.status : 'unknown'}.`); resolve(null); }
                });
            });
        },
        
        render() {
            if (this.state.isLoading) { this.root.innerHTML = '<div id="loading-spinner"></div>'; return; }
            document.body.classList.add('lang_en', 'dark-theme');
            
            this.updateDisplayList();

            const content = E('div', {}, [
                this.buildHeader(), this.buildStatusPanel(), this.buildManagementPanel(), 
                this.buildDiagnosticPanel(), this.buildLiveLogPanel(), this.buildAddModal()
            ]);
            
            this.root.innerHTML = '';
            this.root.append(content);
            this.updateLogPanelState();
        },
        
        updateDisplayList() {
            let baseList;
            
            if (this.state.currentView === 'top10') {
                this.state.dnsList.forEach(p => { 
                    const ping = this.state.pingCache[p.dns1];
                    p._ping = (ping && ping.success) ? parseFloat(ping.avg) : Infinity;
                });
                this.state.displayList = [...this.state.dnsList].sort((a, b) => a._ping - b._ping).slice(0, 10);
                this.state.totalPages = 1;
                this.state.currentPage = 1;
                return;
            }

            if (this.state.currentView === 'favorites') {
                baseList = this.state.dnsList.filter(p => p.favorite);
            } else {
                baseList = this.state.dnsList;
            }
            
            let fullListToPaginate = [...baseList];
            if (this.state.currentView === 'all') {
                fullListToPaginate.unshift({ name: "Modem/Gateway DNS", dns1: this.state.gatewayIp, isStatic: true });
            }
            
            const totalItems = fullListToPaginate.length;
            this.state.totalPages = Math.ceil(totalItems / this.state.itemsPerPage) || 1;
            this.state.currentPage = Math.max(1, Math.min(this.state.currentPage, this.state.totalPages));
            const startIndex = (this.state.currentPage - 1) * this.state.itemsPerPage;
            
            this.state.displayList = fullListToPaginate.slice(startIndex, startIndex + this.state.itemsPerPage);
        },

        buildHeader: () => E('div', { class: 'dnsjumper-header-container' }, [
            E('h2', {}, 'DNS Jumper'),
            E('p', { style: 'font-size: 0.8em; color: var(--info-color); margin-top: -5px; opacity: 0.7;' }, 'By PeDitX')
        ]),
        
        buildStatusPanel() {
            let activeText = 'Unknown/ISP Default';
            if (this.state.activeDNS?.dns?.length > 0) {
                const dnsStr = this.state.activeDNS.dns.join(', ');
                const activeDnsId = Array.isArray(this.state.activeDNS.dns) ? this.state.activeDNS.dns.sort().join(',') : '';
                if (this.state.activeDNS.type === 'gateway') { activeText = `Modem/Gateway (${dnsStr})`; }
                else {
                    const found = this.state.dnsList.find(p => [p.dns1, p.dns2].filter(Boolean).sort().join(',') === activeDnsId);
                    activeText = found ? `${found.name} (${dnsStr})` : `Custom (${dnsStr})`;
                }
            }
            const statusItems = this.state.systemStatus ? Object.entries(this.state.systemStatus).map(([k, v]) => E('div', {}, [E('span', {class: `status-icon ${v ? 'status-ok' : 'status-error'}`}), `${k.toUpperCase()}: ${v ? 'OK' : 'Error'}`])) : [E('span', {}, 'Status unavailable')];
            return E('div', { class: 'glass-ui status-panels' }, [
                E('div', { class: 'status-panel' }, [ E('h3', {}, 'Currently Active DNS'), E('p', {}, activeText) ]),
                E('div', { class: 'status-panel' }, [ E('h3', {}, 'System Status'), E('div', { id: 'system-status-panel' }, statusItems) ])
            ]);
        },

        buildPaginationControls() {
            if (this.state.currentView === 'top10' || this.state.totalPages <= 1) return null;
            
            const prevAttrs = { class: 'cbi-button', 'data-page-action': 'prev' };
            if (this.state.currentPage === 1) prevAttrs.disabled = true;

            const nextAttrs = { class: 'cbi-button', 'data-page-action': 'next' };
            if (this.state.currentPage === this.state.totalPages) nextAttrs.disabled = true;

            return E('div', { class: 'pagination-controls' }, [
                E('div', { class: 'button-group' }, [
                    E('span', {}, 'Per Page:'),
                    ...[10, 25, 50].map(size => E('button', { class: `cbi-button ${this.state.itemsPerPage === size ? 'active' : ''}`, 'data-page-size': size }, size))
                ]),
                E('div', { class: 'button-group' }, [
                    E('button', prevAttrs, 'â¹ Prev'),
                    E('span', { class: 'page-info' }, `Page ${this.state.currentPage} of ${this.state.totalPages}`),
                    E('button', nextAttrs, 'Next âº')
                ])
            ]);
        },

        buildManagementPanel() {
            const tbody = E('tbody');
            
            const createIpInfoLink = (ip) => {
                if (!ip || ip === 'Not Found') return null;
                return E('a', { 
                    href: `https://ipinfo.io/${ip}`, target: '_blank', rel: 'noopener noreferrer',
                    title: `Info for ${ip}`,
                    style: 'margin-left: 8px; text-decoration: none; color: var(--info-color); font-weight: bold; font-size: 0.9em;'
                }, '[i]');
            };
            
            this.state.displayList.forEach((provider) => {
                const pingResult = this.state.pingCache[provider.dns1];
                let pingHTML = E('span', {}, '-');
                if (pingResult) {
                    pingHTML.textContent = pingResult.avg; 
                    if (pingResult.success) {
                        const avg = parseFloat(pingResult.avg);
                        pingHTML.style.color = avg > 150 ? 'var(--ping-bad)' : (avg > 70 ? 'var(--ping-warn)' : 'var(--ping-good)');
                        pingHTML.style.fontWeight = 'bold';
                    } else pingHTML.style.color = 'var(--ping-bad)';
                }
                const isActive = this.state.activeDNS && Array.isArray(this.state.activeDNS.dns) && [provider.dns1, provider.dns2].filter(Boolean).sort().join(',') === this.state.activeDNS.dns.sort().join(',');
                
                const actions = E('div', {class: 'btn-action-group'}, provider.isStatic
                    ? [E('button', { class: 'cbi-button', 'data-action': 'apply', 'data-provider': JSON.stringify(provider) }, 'Apply'), E('button', { class: 'cbi-button', 'data-action': 'renew-gateway' }, 'Renew')]
                    : [ E('button', { class: 'cbi-button', 'data-action': 'apply', 'data-provider': JSON.stringify(provider) }, 'Apply'), E('button', { class: 'cbi-button', 'data-action': 'delete', 'data-provider': JSON.stringify(provider) }, 'Del') ]);
                
                const trAttrs = { 
                    class: isActive ? 'active-dns' : '', 
                    'data-provider-id': provider.dns1 
                };
                if (this.state.isDragEnabled && !provider.isStatic) {
                    trAttrs.draggable = true;
                    trAttrs.class += ' draggable-row drag-enabled';
                }

                const tr = E('tr', trAttrs, [
                    E('td', {}, [provider.isStatic ? provider.name : E('div', {style:'display:flex; align-items:center;'}, [E('button', { class: `btn-fav ${provider.favorite ? 'is-fav' : ''}`, 'data-action': 'favorite', 'data-provider': JSON.stringify(provider) }, 'â'), provider.name])]),
                    E('td', {}, E('span', {}, [provider.dns1 || '', createIpInfoLink(provider.dns1)])), 
                    E('td', {}, E('span', {}, [provider.dns2 || '', createIpInfoLink(provider.dns2)])),
                    E('td', { id: `ping-${provider.dns1}`.replace(/\./g, '-') }, [pingHTML, E('button', { class: 'cbi-button', 'data-action': 'test', 'data-provider': JSON.stringify(provider), style: 'margin-left:10px;padding:2px 6px;font-size:0.8em;'}, 'Test')]),
                    E('td', {}, actions)
                ]);
                tbody.append(tr);
            });

            return E('div', { class: 'glass-ui' }, [
                E('div', {class: 'controls-group'}, [
                    E('div', {class: 'button-group'}, [
                        E('button', { id: 'ping-all-btn', class: 'cbi-button' }, 'Ping All'), 
                        E('button', { id: 'sort-by-ping-btn', class: 'cbi-button' }, 'Sort by Ping'), 
                        E('button', { id: 'toggle-drag-btn', class: `cbi-button ${this.state.isDragEnabled ? 'active' : ''}` }, 'Manual Sort'),
                        E('button', { id: 'remove-timedout-btn', class: 'cbi-button' }, 'Remove T/O')
                    ]),
                    E('div', {class: 'button-group'}, [
                        E('button', { class: `cbi-button ${this.state.currentView === 'all' ? 'active' : ''}`, 'data-view': 'all' }, 'All'), 
                        E('button', { class: `cbi-button ${this.state.currentView === 'favorites' ? 'active' : ''}`, 'data-view': 'favorites' }, 'Favorites'), 
                        E('button', { class: `cbi-button ${this.state.currentView === 'top10' ? 'active' : ''}`, 'data-view': 'top10' }, 'Top 10')
                    ])
                ]),
                E('table', { class: 'management-table' }, [E('thead',{},E('tr',{},[E('th',{},'Name'),E('th',{},'DNS 1'),E('th',{},'DNS 2'),E('th',{},'Ping'),E('th',{},'Actions')])), tbody]),
                this.buildPaginationControls(), 
                E('div', { class: 'button-group', style: 'margin-top:20px' }, [
                    E('button', { id: 'add-new-btn', class: 'cbi-button' }, 'Add New'), 
                    E('button', { id: 'update-online-btn', class: 'cbi-button' }, 'Update Online'), 
                    E('a', { class: 'cbi-button', href: '<%=luci.dispatcher.build_url("admin/peditxos/dnsjumper/backup")%>' }, 'Backup'), 
                    E('label', { for: 'restore-file-input', class: 'cbi-button' }, 'Restore'), 
                    E('input', { id: 'restore-file-input', type: 'file', style: 'display:none' })
                ])
            ]);
        },

        buildDiagnosticPanel() {
            const fullList = [{ name: "Modem/Gateway DNS", dns1: this.state.gatewayIp, isStatic: true }, ...this.state.dnsList];
            const options = fullList.map(p => p.dns1 && p.dns1 !== "Not Found" ? E('option', { value: p.dns1 }, `${p.name} (${p.dns1})`) : null).filter(Boolean);
            return E('div', { class: 'glass-ui' }, [
                E('h2', {}, 'Network Diagnostic Tool'),
                E('div', { class: 'diag-inputs' }, [E('select', { id: 'diag-dns-select' }, options), E('input', { id: 'diag-target-host', placeholder: 'e.g., google.com' })]),
                E('div', { class: 'button-group' }, [ 
                    E('button', { id: 'diag-ping-btn', class: 'cbi-button', 'data-command': 'ping' }, 'Run Ping'),
                    E('a', { class: 'cbi-button', href: 'https://speed.cloudflare.com/', target: '_blank', rel: 'noopener noreferrer' }, 'Run Speed Test')
                ]),
                E('pre', { id: 'diag-output', style: 'background-color:rgba(0,0,0,0.2);padding:15px;border-radius:8px;min-height:150px;overflow-x:auto;margin-top:15px;color:var(--text-color);' })
            ]);
        },
        
        buildLiveLogPanel() {
            return E('div', { class: 'glass-ui' }, [
                E('h2', {}, 'Network Monitor'), 
                E('div', { class: 'button-group', style: 'margin-bottom: 10px; margin-top: 15px;' }, [
                    E('button', { id: 'start-log-btn', class: 'cbi-button' }, 'Start Live Log'),
                    E('button', { id: 'stop-log-btn', class: 'cbi-button' }, 'Stop Live Log'),
                    E('span', { id: 'log-status-indicator', title: 'Log Status' })
                ]),
                E('pre', { id: 'log-viewer-output' }, this.state.logOutput)
            ]);
        },

        buildAddModal() {
            return E('div', { id: 'add-dns-modal', class: 'modal-overlay' }, [
                E('div', { class: 'modal-content' }, [
                    E('h3', {}, 'Add New DNS Provider'),
                    E('div', { class: 'form-group' }, [
                        E('label', { for: 'new-dns-name' }, 'Provider Name'),
                        E('input', { type: 'text', id: 'new-dns-name', placeholder: 'e.g., My DNS' })
                    ]),
                    E('div', { class: 'form-group' }, [
                        E('label', { for: 'new-dns-1' }, 'Primary DNS'),
                        E('input', { type: 'text', id: 'new-dns-1', placeholder: 'e.g., 8.8.8.8' })
                    ]),
                    E('div', { class: 'form-group' }, [
                        E('label', { for: 'new-dns-2' }, 'Secondary DNS (Optional)'),
                        E('input', { type: 'text', id: 'new-dns-2', placeholder: 'e.g., 8.8.4.4' })
                    ]),
                    E('div', { class: 'button-group', style: 'margin-top: 20px; justify-content: flex-end;' }, [
                        E('button', { class: 'cbi-button', 'data-action': 'cancel-add' }, 'Cancel'),
                        E('button', { class: 'cbi-button active', 'data-action': 'save-add' }, 'Save')
                    ])
                ])
            ]);
        },
        
        addEventListeners() {
            if (this.root._listenersAttached) return;

            this.root.addEventListener('click', e => {
                const button = e.target.closest('button');
                if (!button) return;

                const { view, action, provider: providerStr, pageSize, pageAction } = button.dataset;
                const id = button.id;
                const provider = providerStr ? JSON.parse(providerStr) : null;

                if (view) { this.state.currentView = view; this.state.currentPage = 1; this.render(); }
                else if (pageSize) { this.state.itemsPerPage = parseInt(pageSize, 10); this.state.currentPage = 1; this.render(); }
                else if (pageAction) {
                    if (pageAction === 'next') this.state.currentPage++; else if (pageAction === 'prev') this.state.currentPage--;
                    this.render();
                }
                else if (action) {
                    switch(action) {
                        case 'apply': this.handleApply(provider, button); break;
                        case 'test': this.handleTestProvider(provider, button); break;
                        case 'favorite': this.handleToggleFavorite(provider); break;
                        case 'delete': this.handleDelete(provider); break;
                        case 'renew-gateway': this.init(); break;
                        case 'cancel-add': this.toggleAddModal(false); break;
                        case 'save-add': this.handleSaveNewProvider(button); break;
                    }
                }
                else {
                     switch(id) {
                        case 'ping-all-btn': this.handlePingAll(button); break; 
                        case 'sort-by-ping-btn': this.handleSortByPing(button); break;
                        case 'toggle-drag-btn': this.state.isDragEnabled = !this.state.isDragEnabled; this.render(); break;
                        case 'remove-timedout-btn': this.handleRemoveTimedOut(button); break;
                        case 'update-online-btn': this.handleOnlineUpdate(button); break;
                        case 'diag-ping-btn': this.handleDiagnostic(button); break;
                        case 'start-log-btn': this.handleStartLog(button); break; 
                        case 'stop-log-btn': this.handleStopLog(button); break; 
                        case 'add-new-btn': this.toggleAddModal(true); break;
                    }
                }
            });
            
            this.root.addEventListener('change', e => {
                if (e.target.id === 'restore-file-input') this.handleRestore(e);
            });

            this.root.addEventListener('dragstart', e => {
                const row = e.target.closest('.draggable-row.drag-enabled');
                if (!this.state.isDragEnabled || !row) return;
                e.dataTransfer.effectAllowed = 'move';
                e.dataTransfer.setData('text/plain', row.dataset.providerId);
                this.state.draggedProviderId = row.dataset.providerId;
                setTimeout(() => row.classList.add('dragging'), 0);
            });

            this.root.addEventListener('dragend', () => {
                this.state.draggedProviderId = null;
                this.root.querySelectorAll('.drag-over, .dragging').forEach(el => el.classList.remove('drag-over', 'dragging'));
            });

            this.root.addEventListener('dragover', e => {
                if (!this.state.isDragEnabled || !this.state.draggedProviderId) return;
                const targetRow = e.target.closest('tr');
                if (!targetRow) return;
                e.preventDefault();
                e.dataTransfer.dropEffect = 'move';
                this.root.querySelectorAll('.drag-over').forEach(r => r.classList.remove('drag-over'));
                if (targetRow.dataset.providerId !== this.state.draggedProviderId) targetRow.classList.add('drag-over');
            });

            this.root.addEventListener('drop', e => {
                if (!this.state.isDragEnabled || !this.state.draggedProviderId) return;
                e.preventDefault();
                const targetRow = e.target.closest('tr');
                this.root.querySelectorAll('.drag-over').forEach(r => r.classList.remove('drag-over'));
                if (!targetRow || targetRow.dataset.providerId === this.state.draggedProviderId) return;

                const fromId = this.state.draggedProviderId;
                const targetId = targetRow.dataset.providerId;
                const fromIndex = this.state.dnsList.findIndex(p => p.dns1 === fromId);
                if (fromIndex === -1) return;
                
                const [item] = this.state.dnsList.splice(fromIndex, 1);
                const toIndex = this.state.dnsList.findIndex(p => p.dns1 === targetId);
                
                if (targetId === this.state.gatewayIp) this.state.dnsList.unshift(item);
                else if (toIndex > -1) this.state.dnsList.splice(toIndex, 0, item);
                else this.state.dnsList.splice(fromIndex, 0, item);
                
                this.saveList().then(() => this.render());
            });

            this.root._listenersAttached = true;
        },
        
        toggleAddModal(show) {
            const modal = this.root.querySelector('#add-dns-modal');
            if (modal) {
                modal.style.display = show ? 'flex' : 'none';
                if (show) {
                    modal.querySelector('#new-dns-name').focus();
                } else {
                    modal.querySelector('#new-dns-name').value = '';
                    modal.querySelector('#new-dns-1').value = '';
                    modal.querySelector('#new-dns-2').value = '';
                }
            }
        },

        async handleSaveNewProvider(btn) {
            const name = this.root.querySelector('#new-dns-name').value.trim();
            const dns1 = this.root.querySelector('#new-dns-1').value.trim();
            const dns2 = this.root.querySelector('#new-dns-2').value.trim();

            if (!name || !dns1) { console.error("Provider Name and Primary DNS are required."); return; }
            
            const ipRegex = /^(\d{1,3}\.){3}\d{1,3}$/;
            if (!dns1.match(ipRegex)) { console.error("Invalid Primary DNS IP format."); return; }
            if (dns2 && !dns2.match(ipRegex)) { console.error("Invalid Secondary DNS IP format."); return; }
            
            this.setButtonLoading(btn, true);
            const newProvider = { name, dns1, dns2: dns2 || null, favorite: false };
            this.state.dnsList.push(newProvider);
            await this.saveList();
            
            this.setButtonLoading(btn, false, 'Save');
            this.toggleAddModal(false);
            this.render();
            console.log(`DNS provider '${name}' added successfully.`);
        },

        async handleRemoveTimedOut(btn) {
            this.setButtonLoading(btn, true);
            const initialCount = this.state.dnsList.length;
            this.state.dnsList = this.state.dnsList.filter(p => {
                const pingResult = this.state.pingCache[p.dns1];
                return !pingResult || pingResult.success;
            });
            const removedCount = initialCount - this.state.dnsList.length;
            if (removedCount > 0) {
                await this.saveList();
                this.render();
                console.log(`${removedCount} timed out DNS providers removed.`);
            } else {
                console.log('No timed out DNS providers to remove.');
            }
            this.setButtonLoading(btn, false, 'Remove T/O');
        },
        
        handleDelete(provider) {
            if(!provider || provider.isStatic) return;
            this.state.dnsList = this.state.dnsList.filter(p => p.dns1 !== provider.dns1);
            this.saveList().then(() => this.render());
        },
        
        updateLogPanelState() {
            const startBtn = this.root.querySelector('#start-log-btn'), stopBtn = this.root.querySelector('#stop-log-btn');
            const indicator = this.root.querySelector('#log-status-indicator'), output = this.root.querySelector('#log-viewer-output');
            
            if (output) output.textContent = this.state.logOutput;
            if (indicator) {
                indicator.className = '';
                if (this.state.isLogRunning) { indicator.classList.add('status-green'); indicator.title = 'Live Log Running'; } 
                else { indicator.classList.add('status-red'); indicator.title = 'Live Log Stopped'; }
            }
            if (startBtn && stopBtn) {
                startBtn.disabled = this.state.isLogRunning;
                stopBtn.disabled = !this.state.isLogRunning;
            }
        },
        
        startLogPolling() {
            if (this.state.logTailInterval) clearInterval(this.state.logTailInterval);
            this.state.logTailInterval = setInterval(this.pollLog.bind(this), 2000); 
            this.updateLogPanelState();
        },
        
        stopLogPolling() {
            if (this.state.logTailInterval) { clearInterval(this.state.logTailInterval); this.state.logTailInterval = null; this.updateLogPanelState(); }
        },

        async pollLog() {
            const res = await this.fetchAPI('/get_live_log');
            if (res) {
                this.state.logOutput = res.log_content;
                const outputEl = this.root.querySelector('#log-viewer-output');
                if (outputEl) {
                    outputEl.textContent = res.log_content;
                    outputEl.scrollTop = outputEl.scrollHeight;
                }
                if (res.is_running !== this.state.isLogRunning) {
                    this.state.isLogRunning = res.is_running;
                    if (!res.is_running) this.stopLogPolling();
                    this.updateLogPanelState();
                }
            }
        },
        
        async handleStartLog(btn) {
            this.setButtonLoading(btn, true);
            const res = await this.fetchAPI('/start_log');
            this.state.isLogRunning = res && res.success;
            this.state.logOutput = res ? res.message : 'Error starting log.';
            if (this.state.isLogRunning) this.startLogPolling();
            this.setButtonLoading(btn, false, 'Start Live Log');
            this.updateLogPanelState();
        },
        
        async handleStopLog(btn) {
            this.setButtonLoading(btn, true);
            this.stopLogPolling();
            const res = await this.fetchAPI('/stop_log');
            this.state.isLogRunning = false;
            this.state.logOutput += `\n${res ? res.message : 'Error stopping log.'}`;
            this.setButtonLoading(btn, false, 'Stop Live Log');
            this.updateLogPanelState();
        },
        
        async handleTestProvider(provider, btn) {
            if (!provider || !provider.dns1 || provider.dns1 === 'Not Found') return;
            const pingCell = this.root.querySelector(`#ping-${provider.dns1.replace(/\./g, '-')} span`);
            if (pingCell) pingCell.textContent = '...';
            if (btn) this.setButtonLoading(btn, true);
            
            const res = await this.fetchAPI('/ping', { body: { ip: provider.dns1 } });
            if (res) {
                this.state.pingCache[provider.dns1] = { avg: res.avg, success: res.success };
                this.saveCache();
                if (pingCell) {
                   pingCell.textContent = res.avg;
                   pingCell.style.color = res.success ? (parseFloat(res.avg) > 150 ? 'var(--ping-bad)' : parseFloat(res.avg) > 70 ? 'var(--ping-warn)' : 'var(--ping-good)') : 'var(--ping-bad)';
                   pingCell.style.fontWeight = res.success ? 'bold' : 'normal';
                }
            }
            if (btn) this.setButtonLoading(btn, false, 'Test');
        },

        async handlePingAll(btn) {
            this.setButtonLoading(btn, true);
            const providersToPing = this.state.currentView === 'all' 
                ? this.state.dnsList 
                : this.state.displayList.filter(p => !p.isStatic);
            const CONCURRENCY_LIMIT = 4;
            const queue = [...providersToPing];
            
            const runNext = async () => {
                if (queue.length === 0) return;
                const provider = queue.shift();
                await this.handleTestProvider(provider, null);
                await runNext();
            };

            await Promise.all(Array(CONCURRENCY_LIMIT).fill(null).map(runNext));
            this.setButtonLoading(btn, false, 'Ping All');
            this.render();
        },

        async handleDiagnostic(btn) {
            const outputEl = this.root.querySelector('#diag-output');
            const payload = { dns: this.root.querySelector('#diag-dns-select').value, target: this.root.querySelector('#diag-target-host').value.trim() }; 
            if (!payload.target) { console.error('Target host is required.'); return; }
            outputEl.textContent = 'Running ping...';
            this.setButtonLoading(btn, true);
            const res = await this.fetchAPI('/run_diagnostic', { method: 'POST', body: { payload: JSON.stringify(payload) } });
            outputEl.textContent = res?.output || `Error: ${res?.message || 'No response.'}`;
            this.setButtonLoading(btn, false, 'Run Ping');
        },
        
        async handleSortByPing(btn) { 
            await this.handlePingAll(btn);
            this.state.dnsList.forEach(p => { 
                const ping = this.state.pingCache[p.dns1]; 
                p._ping = (ping && ping.success) ? parseFloat(ping.avg) : Infinity;
            }); 
            this.state.dnsList.sort((a, b) => a._ping - b._ping); 
            this.saveList().then(() => this.render());
        },
        handleToggleFavorite(provider) {
            if(!provider || provider.isStatic) return;
            const listProvider = this.state.dnsList.find(p => p.dns1 === provider.dns1);
            if(listProvider) { listProvider.favorite = !listProvider.favorite; this.saveList().then(() => this.render()); } 
        },
        
        async handleApply(provider, btn) {
             this.setButtonLoading(btn, true);
             const res = await this.fetchAPI('/apply_dns', { method: 'POST', body: { payload: JSON.stringify(provider) }});
             if (res) {
                 console.log(res.message); 
                 if(res.success) setTimeout(() => this.init(), 7000);
             }
             this.setButtonLoading(btn, false, 'Apply');
        },
        
        async handleOnlineUpdate(btn) {
            this.setButtonLoading(btn, true);
            const res = await this.fetchAPI('/online_update');
            if (res && res.success) {
                console.log(res.message); 
                await this.init();
            } else { console.error(res ? res.message : 'Update failed.'); } 
            this.setButtonLoading(btn, false, 'Update Online');
        },
        
        async handleRestore(ev) {
            const file = ev.target.files[0]; if (!file) return;
            const reader = new FileReader();
            reader.onload = async (e) => {
                const data = e.target.result;
                const res = await this.fetchAPI('/save_list', { method: 'POST', body: { payload: data } });
                if(res && res.success) {
                    console.log("Restore successful."); 
                    await this.init();
                } else { console.error(res ? res.message : 'Restore failed.'); }
            };
            reader.readAsText(file);
            ev.target.value = '';
        },

        setButtonLoading(btn, isLoading, originalText = '') {
            if (!btn) return;
            if (isLoading) {
                btn.dataset.originalText = btn.textContent; btn.innerHTML = ''; btn.classList.add('btn-loading'); btn.disabled = true;
            } else {
                btn.classList.remove('btn-loading'); btn.textContent = originalText || btn.dataset.originalText; btn.disabled = false;
            }
        },

        saveCache: () => App.fetchAPI('/save_cache', { method: 'POST', body: { payload: JSON.stringify({ pings: App.state.pingCache }) } }),
        saveList: () => App.fetchAPI('/save_list', { method: 'POST', body: { payload: JSON.stringify(App.state.dnsList.map(({ _ping, ...r }) => r)) } })
    };

    App.init();
})();
</script>
<%+footer%>
EOF

# --- 5. Finalization ---
rm -f /tmp/luci-indexcache

echo ""
echo ">>> DNS Jumper v84.0 (Core Functionality Fixes) has been installed."
echo ">>> Please hard-refresh your browser (Ctrl+Shift-R) to load the new UI correctly."
echo ""

exit 0

