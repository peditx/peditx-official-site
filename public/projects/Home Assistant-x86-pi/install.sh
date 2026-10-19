#!/bin/sh
# ============================================================
#  Home Assistant — PeDitXOS standalone installer
#
#  The package manager is detected at runtime, so this ONE script
#  covers OpenWrt 23.05 / 24.10 (opkg) and 25.12+ (apk).
#  JS view + menu.d + acl.d only: no Lua, no Makefile, no compile.
# ============================================================

# ---- 1. PACKAGE MANAGER DETECTION --------------------------
if command -v apk >/dev/null 2>&1; then
	PKG="apk"
	PKG_UPDATE="apk update"
	PKG_INSTALL="apk add"
elif command -v opkg >/dev/null 2>&1; then
	PKG="opkg"
	PKG_UPDATE="opkg update"
	PKG_INSTALL="opkg install"
else
	echo "ERROR: no supported package manager found (need opkg or apk)" >&2
	exit 1
fi

log_info()    { echo "INFO: $1"; }
log_success() { echo "SUCCESS: $1"; }
log_error()   { echo "ERROR: $1" >&2; }

APP_NAME="homeassistant"
APP_TITLE="Home Assistant"
APP_MODE="docker"          # docker | service
APP_TARGET="homeassistant"      # container name, or /etc/init.d/<name>
APP_PORT="8123"          # web UI port, 0 = no web UI

# render <outfile>  <<'EOF'  ...  EOF
#
# Heredocs MUST stay quoted: the templates contain shell syntax the installer
# must not expand, so @MARKERS@ are substituted instead of ${VARS}.
render() {
	# An unset variable silently becomes "" -> `"title": ""`, a menu entry you
	# can click but cannot read. Fail loudly instead.
	[ -n "$APP_NAME" ]   || { log_error "render: APP_NAME is empty";   exit 1; }
	[ -n "$APP_TITLE" ]  || { log_error "render: APP_TITLE is empty";  exit 1; }
	[ -n "$APP_MODE" ]   || { log_error "render: APP_MODE is empty";   exit 1; }
	[ -n "$APP_TARGET" ] || { log_error "render: APP_TARGET is empty"; exit 1; }
	[ -n "$APP_PORT" ]   || { log_error "render: APP_PORT is empty";   exit 1; }
	sed -e "s|@APP@|${APP_NAME}|g" \
	    -e "s|@TITLE@|${APP_TITLE}|g" \
	    -e "s|@MODE@|${APP_MODE}|g" \
	    -e "s|@TARGET@|${APP_TARGET}|g" \
	    -e "s|@PORT@|${APP_PORT}|g" > "$1"
	if grep -q '@[A-Z][A-Z_0-9]*@' "$1"; then
		log_error "render: unsubstituted marker left in $1"
		exit 1
	fi
}

# ---- 2. DEPENDENCIES — install only what is MISSING ----------
#    luci-base = JS view framework + fs/uci modules
#    rpcd      = ubus `file` object used by fs.exec_direct
#    *** never re-install an already-present luci-base/rpcd: a custom
#        firmware's copy is load-bearing for the theme and every other app. ***
PKG_INSTALLED() {
	if [ "$PKG" = "apk" ]; then
		apk info -e "$1" >/dev/null 2>&1
	else
		opkg status "$1" 2>/dev/null | grep -q '^Status:.*installed'
	fi
}

MISSING=""
for p in luci-base rpcd ; do
	PKG_INSTALLED "$p" || MISSING="$MISSING $p"
done

if [ -n "$MISSING" ]; then
	log_info "Installing missing dependencies via $PKG:$MISSING"
	$PKG_UPDATE >/dev/null 2>&1
	$PKG_INSTALL $MISSING >/dev/null 2>&1 || $PKG_INSTALL $MISSING
	log_success "Dependencies installed:$MISSING"
else
	log_info "All dependencies already present — nothing installed."
fi

# apk note: OpenWrt 25.12 ships apk-tools 3.0.5 (no `--no-cache`, that is
# Alpine v2 syntax) — plain `apk add` is what $PKG_INSTALL uses above.

echo
echo "--- Home Assistant by PeDitX ---"
echo

# --- Docker (required by this app) --------------------------------
if command -v docker >/dev/null 2>&1; then
	log_info "Docker already installed: $(docker -v 2>/dev/null)"
else
	log_info "Installing Docker via $PKG..."
	$PKG_UPDATE >/dev/null 2>&1
	$PKG_INSTALL dockerd docker-compose kmod-veth >/dev/null 2>&1 \
		|| $PKG_INSTALL dockerd docker-compose kmod-veth \
		|| log_error "Docker packages could not be installed"
	modprobe veth >/dev/null 2>&1
	/etc/init.d/dockerd enable >/dev/null 2>&1
	/etc/init.d/dockerd start >/dev/null 2>&1
	log_info "Waiting for the Docker daemon..."
	sleep 5
fi

# The Docker Manager page is a convenience, never a hard dependency.
if ! PKG_INSTALLED luci-app-dockerman; then
	$PKG_INSTALL luci-app-dockerman >/dev/null 2>&1 \
		|| log_info "luci-app-dockerman not in this feed (skipped)."
fi


# --- Firewall: Web UI on 8123 -------------------------------------
# --- Firewall ----------------------------------------------------
for rule in $(uci show firewall | grep -E "name='(Allow_HomeAssistant)" | cut -d. -f2 | cut -d= -f1 | sort -u); do
	uci -q delete firewall.$rule
done
uci -q add firewall rule
uci -q set firewall.@rule[-1].name='Allow_HomeAssistant'
uci -q set firewall.@rule[-1].src='lan'
uci -q set firewall.@rule[-1].proto='tcp'
uci -q set firewall.@rule[-1].dest_port='8123'
uci -q set firewall.@rule[-1].target='ACCEPT'
uci -q commit firewall
/etc/init.d/firewall restart >/dev/null 2>&1
log_info "Firewall configured."

# --- Data directory ------------------------------------------------
CONFIG_DIR="/opt/homeassistant/config"
mkdir -p "$CONFIG_DIR"
chmod -R 777 "$CONFIG_DIR"

# --- Container -----------------------------------------------------
docker stop homeassistant >/dev/null 2>&1
docker rm homeassistant >/dev/null 2>&1

docker run -d \
	--name homeassistant \
	--privileged \
	--restart=unless-stopped \
	-e TZ=Asia/Tehran \
	-v "$CONFIG_DIR":/config \
	--network=host \
	ghcr.io/home-assistant/home-assistant:stable >/dev/null 2>&1 \
	|| log_error "docker run failed — check 'docker logs homeassistant'"
log_info "Container deployed."

# ---- 3. MENU (menu.d JSON — replaces the old Lua controller) ----
# ponytail: no /etc/config/${APP_NAME} — nothing here has a setting worth
# persisting (the container/service IS the state, and depends.acl is omitted
# because this is single-admin firmware). Add both when that changes: a UCI
# section, uci.load() in load(), and "uci": ["${APP_NAME}"] in the ACL.
mkdir -p /usr/share/luci/menu.d
render "/usr/share/luci/menu.d/luci-app-${APP_NAME}.json" << 'JSONEOF'
{
	"admin/peditxos": {
		"title": "PeDitXOS Tools",
		"order": 50,
		"action": { "type": "firstchild" }
	},
	"admin/peditxos/@APP@": {
		"title": "@TITLE@",
		"order": 10,
		"action": { "type": "view", "path": "@APP@/main" }
	}
}
JSONEOF
log_success "Menu registered."

# ---- 4. FRONTEND VIEW (vanilla JS, Light + Dark) -------------
mkdir -p "/www/luci-static/resources/view/${APP_NAME}"
render "/www/luci-static/resources/view/${APP_NAME}/main.js" << 'JSEOF'
'use strict';
'require view';
'require fs';
'require ui';
'require poll';

var CSS = [
	/* ===== DARK (default) ===== */
	':root, [data-theme="dark"] {',
	'  --p:#00d4aa; --p2:#00b894; --bg:#1a1d23; --card:#23272f;',
	'  --border:#333; --text:#e4e7ec; --muted:#889; --input-bg:#1a1d23;',
	'  --danger:#ff5050; --warn:#f1fa8c; --log-bg:#0d1117; --log-text:#c9d1d9;',
	'  --switch-bg:#555; --switch-knob:#fff;',
	'  --msg-ok-bg:rgba(0,212,170,.15); --msg-ok-border:#00d4aa;',
	'  --msg-err-bg:rgba(255,80,80,.15); --msg-err-border:#ff5050;',
	'}',
	/* ===== LIGHT ===== */
	'[data-theme="light"] {',
	'  --p:#00897b; --p2:#00695c; --bg:#f0f2f5; --card:#ffffff;',
	'  --border:#ddd; --text:#1a1a2e; --muted:#666; --input-bg:#f8f9fa;',
	'  --danger:#d32f2f; --warn:#f9a825; --log-bg:#f5f5f5; --log-text:#333;',
	'  --switch-bg:#ccc; --switch-knob:#fff;',
	'  --msg-ok-bg:rgba(0,137,123,.1); --msg-ok-border:#00897b;',
	'  --msg-err-bg:rgba(211,47,47,.1); --msg-err-border:#d32f2f;',
	'}',
	'.peditx-app{padding:20px;max-width:860px;margin:0 auto;}',
	'.card{background:var(--card);border:1px solid var(--border);border-radius:12px;padding:20px;margin-bottom:16px;}',
	'.card h2{color:var(--text);margin:0 0 14px;font-size:1.35rem;}',
	'.card h3{color:var(--p);margin:0 0 14px;font-size:1.05rem;}',
	'.theme-switch{display:flex;align-items:center;gap:8px;position:fixed;top:12px;right:16px;z-index:100;background:var(--card);border:1px solid var(--border);border-radius:20px;padding:4px 12px;font-size:.85rem;}',
	'.theme-switch input{width:36px;height:20px;appearance:none;-webkit-appearance:none;background:var(--switch-bg);border-radius:10px;position:relative;cursor:pointer;transition:background .3s;border:none;outline:none;}',
	'.theme-switch input::after{content:"";position:absolute;top:2px;left:2px;width:16px;height:16px;border-radius:50%;background:var(--switch-knob);transition:transform .3s;}',
	'.theme-switch input:checked{background:var(--p);}',
	'.theme-switch input:checked::after{transform:translateX(16px);}',
	'.btn{display:inline-block;background:var(--p);color:#fff;border:none;padding:9px 18px;border-radius:8px;font-weight:600;cursor:pointer;transition:opacity .2s;margin:0 8px 8px 0;text-decoration:none;font-size:.95rem;}',
	'.btn:hover{opacity:.85;}',
	'.btn:disabled{opacity:.4;cursor:not-allowed;}',
	'.btn-secondary{background:var(--switch-bg);color:var(--text);}',
	'.msg{padding:12px;border-radius:8px;margin:12px 0;font-family:monospace;font-size:.9rem;display:none;word-break:break-word;}',
	'.msg.ok{display:block;background:var(--msg-ok-bg);border:1px solid var(--msg-ok-border);}',
	'.msg.err{display:block;background:var(--msg-err-bg);border:1px solid var(--msg-err-border);}',
	'.log-box{background:var(--log-bg);color:var(--log-text);border:1px solid var(--border);border-radius:8px;padding:16px;max-height:320px;overflow:auto;font-family:monospace;font-size:.85rem;white-space:pre-wrap;word-break:break-word;margin:0;}',
	'.badge{display:inline-block;padding:3px 10px;border-radius:10px;font-size:.78rem;font-weight:600;}',
	'.badge.ok{background:rgba(0,212,170,.2);color:var(--p);}',
	'.badge.err{background:rgba(255,80,80,.2);color:var(--danger);}',
	'.kv{font-family:monospace;font-size:.9rem;color:var(--muted);word-break:break-all;}'
].join('\n');

function applyTheme(light) {
	var el = document.documentElement;
	if (light) el.setAttribute('data-theme', 'light');
	else       el.removeAttribute('data-theme');
	localStorage.setItem('@APP@_theme', light ? 'light' : 'dark');
}

return view.extend({
	/* load() runs before render(); no DOM access here */
	load: function() {
		return Promise.all([ this.rpc('status'), this.rpc('logs') ]);
	},

	/* render() returns a node LuCI has NOT inserted yet: keep refs, never
	   document.getElementById(), and register the poll loop right here. */
	render: function(res) {
		var self = this;
		var saved = localStorage.getItem('@APP@_theme');

		this.el = {
			msg:     E('div', { 'class': 'msg' }),
			badge:   E('span', { 'class': 'badge' }, _('checking…')),
			url:     E('span', { 'class': 'kv' }, ''),
			open:    E('a', { 'class': 'btn', 'target': '_blank', 'href': '#' }, _('Open @TITLE@')),
			details: E('pre', { 'class': 'log-box' }, ''),
			log:     E('pre', { 'class': 'log-box' }, '')
		};

		this.paintStatus(res[0]);
		this.paintLog(res[1]);
		poll.add(L.bind(this.refreshLive, this), 5);

		return E([ E('style', { 'type': 'text/css' }, CSS),

			E('div', { 'class': 'theme-switch' }, [
				E('span', {}, '☀️'),
				E('input', { 'type': 'checkbox', 'id': 'theme-toggle',
					'checked': (saved === 'light') ? 'checked' : null,
					'change': function() { applyTheme(this.checked); } }),
				E('span', {}, '🌙')
			]),

			E('div', { 'class': 'peditx-app' }, [

				E('div', { 'class': 'card' }, [
					E('h2', {}, '@TITLE@'),
					E('div', {}, [ _('Status: '), this.el.badge ]),
					E('div', { 'style': 'margin-top:8px' }, [ this.el.url ]),
					E('div', { 'style': 'margin-top:16px' }, [
						this.el.open,
						E('button', { 'class': 'btn btn-secondary',
							'click': ui.createHandlerFn(self, 'handleStart') }, _('Start')),
						E('button', { 'class': 'btn btn-secondary',
							'click': ui.createHandlerFn(self, 'handleStop') }, _('Stop')),
						E('button', { 'class': 'btn',
							'click': ui.createHandlerFn(self, 'handleRestart') }, _('Restart'))
					]),
					this.el.msg
				]),

				E('div', { 'class': 'card' }, [
					E('h3', {}, _('Status details')),
					this.el.details
				]),

				E('div', { 'class': 'card' }, [
					E('h3', {}, _('Log')),
					E('div', { 'style': 'margin-bottom:10px' }, [
						E('button', { 'class': 'btn btn-secondary',
							'click': ui.createHandlerFn(self, 'handleRefreshLog') }, _('Refresh log'))
					]),
					this.el.log
				])
			])
		]);
	},

	showMsg: function(text, isErr) {
		var el = this.el.msg;
		el.textContent = text;
		el.className = 'msg ' + (isErr ? 'err' : 'ok');
		window.clearTimeout(this._msgTimer);
		this._msgTimer = window.setTimeout(function() { el.className = 'msg'; }, 5000);
	},

	/* always .catch() it: exec_direct rejects on 403, missing file, bad JSON */
	rpc: function(action) {
		return fs.exec_direct('/usr/bin/@APP@-backend.sh', [ action ], 'json');
	},

	paintStatus: function(st) {
		if (!st) st = {};
		var running = (st.running === true || st.running === 'true');
		this.el.badge.textContent = running ? _('running')
			: (st.state ? String(st.state) : _('unknown'));
		this.el.badge.className = 'badge ' + (running ? 'ok' : 'err');
		if (st.url) {
			this.el.url.textContent = st.url;
			this.el.open.href = st.url;
			this.el.open.hidden = false;
		} else {
			this.el.url.textContent = '';
			this.el.open.hidden = true;
		}
		this.el.details.textContent = JSON.stringify(st, null, 2);
	},

	paintLog: function(res) {
		this.el.log.textContent = (res && res.output)
			? res.output : JSON.stringify(res, null, 2);
	},

	refreshLive: function() {
		var self = this;
		return this.rpc('status').then(function(st) {
			self.paintStatus(st);
		}).catch(function() {
			self.el.badge.textContent = _('unreachable');
			self.el.badge.className = 'badge err';
		});
	},

	handleRefreshLog: function() {
		var self = this;
		return this.rpc('logs').then(function(res) {
			self.paintLog(res);
		}).catch(function(e) {
			self.showMsg(_('Log failed: %s').format(e.message || e), true);
		});
	},

	ctl: function(action) {
		var self = this;
		return this.rpc(action).then(function(res) {
			if (res && res.status === 'error')
				self.showMsg(res.message || _('operation failed'), true);
			else
				self.showMsg(action + ': ' + _('done'), false);
			return self.refreshLive();
		}).catch(function(e) {
			self.showMsg(_('Failed: %s').format(e.message || e), true);
		});
	},

	handleStart:   function() { return this.ctl('start'); },
	handleStop:    function() { return this.ctl('stop'); },
	handleRestart: function() { return this.ctl('restart'); },

	/* hide LuCI's own footer bar — this page draws its own buttons */
	handleSaveApply: null,
	handleReset: null
});

JSEOF
log_success "Frontend view created."

# ---- 5. RPCD ACL ---------------------------------------------
#    file.exec keys are the FULL command line, arguments included:
#    fs.exec_direct('/usr/bin/x.sh', ['status']) -> "/usr/bin/x.sh status"
#    cgi-io is checked in addition to file.exec by /cgi-bin/cgi-exec.
mkdir -p /usr/share/rpcd/acl.d
render "/usr/share/rpcd/acl.d/luci-app-${APP_NAME}.json" << 'ACLEOF'
{
	"luci-app-@APP@": {
		"description": "PeDitXOS @TITLE@",
		"read": {
			"cgi-io": [ "exec" ],
			"file": {
				"/usr/bin/@APP@-backend.sh status": [ "exec" ],
				"/usr/bin/@APP@-backend.sh logs": [ "exec" ]
			}
		},
		"write": {
			"file": {
				"/usr/bin/@APP@-backend.sh start": [ "exec" ],
				"/usr/bin/@APP@-backend.sh stop": [ "exec" ],
				"/usr/bin/@APP@-backend.sh restart": [ "exec" ]
			}
		}
	}
}
ACLEOF
log_success "RPCD ACL configured."

# ---- 6. BACKEND (JSON on stdout, nothing else) ---------------
render "/usr/bin/${APP_NAME}-backend.sh" << 'SHBEOF'
#!/bin/sh
# @APP@ backend — exactly one JSON object on stdout, nothing else.
# Diagnostics go to stderr or nowhere: fs.exec_direct(..., 'json') rejects.
UCI="/sbin/uci"
[ -x "$UCI" ] || UCI="uci"

MODE="@MODE@"
TARGET="@TARGET@"
PORT=@PORT@

now() { date -u '+%Y-%m-%dT%H:%M:%SZ'; }

# escape a blob for use inside a JSON string (" -> \", \ -> \\, tab -> \t,
# newline -> \n). busybox awk, no external deps.
json_str() {
	printf '%s' "$1" | awk '
		BEGIN { ORS = "" }
		{
			gsub(/\\/, "\\\\")
			gsub(/"/, "\\\"")
			gsub(/\t/, "\\t")
			if (NR > 1) printf "\\n"
			printf "%s", $0
		}'
}

LAN_IP=$($UCI -q get network.lan.ipaddr 2>/dev/null)
[ -n "$LAN_IP" ] || LAN_IP="192.168.1.1"

case "${1:-}" in
	status)
		STATE="missing"
		RUNNING=false
		if [ "$MODE" = "docker" ]; then
			if command -v docker >/dev/null 2>&1 && docker inspect "$TARGET" >/dev/null 2>&1; then
				STATE=$(docker inspect -f '{{.State.Status}}' "$TARGET" 2>/dev/null)
				RUNNING=$(docker inspect -f '{{.State.Running}}' "$TARGET" 2>/dev/null)
				[ -n "$STATE" ] || STATE="unknown"
				[ -n "$RUNNING" ] || RUNNING=false
			fi
		elif [ -x "/etc/init.d/$TARGET" ]; then
			STATE="stopped"
			if "/etc/init.d/$TARGET" running >/dev/null 2>&1; then
				STATE="running"
				RUNNING=true
			fi
		fi
		if [ "$PORT" = "0" ]; then
			URL=""
		else
			URL="http://${LAN_IP}:${PORT}"
		fi
		printf '{"status":"ok","mode":"%s","target":"%s","state":"%s","running":%s,"port":%s,"ip":"%s","url":"%s","time":"%s"}\n' \
			"$MODE" "$TARGET" "$STATE" "$RUNNING" "$PORT" "$LAN_IP" "$URL" "$(now)"
		;;

	start|stop|restart)
		OK=true
		MSG="ok"
		if [ "$MODE" = "docker" ]; then
			if ! command -v docker >/dev/null 2>&1; then
				OK=false; MSG="docker is not installed"
			elif ! docker inspect "$TARGET" >/dev/null 2>&1; then
				OK=false; MSG="container $TARGET does not exist"
			elif ! docker "$1" "$TARGET" >/dev/null 2>&1; then
				OK=false; MSG="$1 failed"
			fi
		else
			if [ ! -x "/etc/init.d/$TARGET" ]; then
				OK=false; MSG="service $TARGET is not installed"
			elif ! "/etc/init.d/$TARGET" "$1" >/dev/null 2>&1; then
				OK=false; MSG="$1 failed"
			fi
		fi
		if [ "$OK" = "true" ]; then
			printf '{"status":"ok","action":"%s","target":"%s","time":"%s"}\n' \
				"$1" "$TARGET" "$(now)"
		else
			printf '{"status":"error","action":"%s","target":"%s","message":"%s","time":"%s"}\n' \
				"$1" "$TARGET" "$MSG" "$(now)"
		fi
		;;

	logs)
		if [ "$MODE" = "docker" ]; then
			if command -v docker >/dev/null 2>&1; then
				OUT=$(docker logs --tail 100 "$TARGET" 2>&1)
			else
				OUT="docker is not installed"
			fi
		else
			OUT=$(logread -e "$TARGET" 2>/dev/null | tail -n 100)
			[ -n "$OUT" ] || OUT="(no matching log entries)"
		fi
		[ -n "$OUT" ] || OUT="(no log output)"
		printf '{"status":"ok","output":"%s","time":"%s"}\n' "$(json_str "$OUT")" "$(now)"
		;;

	*)
		printf '{"status":"error","message":"unknown action"}\n'
		exit 1
		;;
esac

SHBEOF
chmod +x "/usr/bin/${APP_NAME}-backend.sh"
log_success "Backend script created."

# ---- 7. CLEAN UP THE OLD LUA PAGE ---------------------------
rm -f /usr/lib/lua/luci/controller/peditxos_ha.lua
rm -f /usr/lib/lua/luci/view/peditxos/ha.htm
rmdir /usr/lib/lua/luci/view/peditxos 2>/dev/null

# ---- 8. CACHES ------------------------------------------------
/etc/init.d/rpcd reload >/dev/null 2>&1
rm -f /tmp/luci-indexcache /tmp/luci-sessions/.root 2>/dev/null
rm -rf /tmp/luci-modulecache 2>/dev/null

log_info "First start takes a few minutes — open the page once the badge says running."
log_success "${APP_TITLE} installed."
log_info "LuCI menu: PeDitXOS Tools -> ${APP_TITLE}"
if [ "$APP_PORT" != "0" ]; then
	log_info "Open: http://$(uci -q get network.lan.ipaddr):${APP_PORT}"
fi
log_info "Menu missing or a 403? Log out and back in — LuCI snapshots ACLs at login."
