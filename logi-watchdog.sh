#!/bin/bash
#
# logi-watchdog.sh
# Keeps the Logi Options+ agent (which handles MX Master 4 custom buttons)
# alive. Detects both a MISSING agent and a HUNG agent (state Z/T/U that
# Logitech's own KeepAlive=SuccessfulExit does NOT catch, since a hung
# process has not "exited").
#
# Installed as a user LaunchAgent; requires no admin rights.

set -u

AGENT_NAME="logioptionsplus_agent"
AGENT_BIN="/Library/Application Support/Logitech.localized/LogiOptionsPlus/logioptionsplus_agent.app/Contents/MacOS/logioptionsplus_agent"
LOG_DIR="$HOME/Library/Logs/LogiWatchdog"
LOG_FILE="$LOG_DIR/logi-watchdog.log"
MAX_LOG_BYTES=1048576   # 1 MiB, then rotate

mkdir -p "$LOG_DIR"

log() {
    printf '%s  %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$1" >> "$LOG_FILE"
}

# Post a native macOS notification. Runs in the user's GUI session (this is a
# LaunchAgent, so it has access to the Aqua session). Best-effort: never fails
# the script if osascript is unavailable.
notify() {
    local title="$1"
    local message="$2"
    /usr/bin/osascript -e "display notification \"${message//\"/\\\"}\" with title \"${title//\"/\\\"}\" sound name \"Submarine\"" >/dev/null 2>&1 || true
}

rotate_log() {
    if [ -f "$LOG_FILE" ]; then
        local size
        size=$(stat -f%z "$LOG_FILE" 2>/dev/null || echo 0)
        if [ "$size" -gt "$MAX_LOG_BYTES" ]; then
            mv -f "$LOG_FILE" "$LOG_FILE.1"
        fi
    fi
}

restart_agent() {
    local reason="$1"
    log "RESTART triggered ($reason). Killing any existing agent and relaunching."

    # Terminate any lingering/hung instances (TERM, then KILL if needed).
    pkill -x "$AGENT_NAME" 2>/dev/null
    sleep 2
    if pgrep -x "$AGENT_NAME" >/dev/null 2>&1; then
        pkill -9 -x "$AGENT_NAME" 2>/dev/null
        sleep 1
    fi

    if [ ! -x "$AGENT_BIN" ]; then
        log "ERROR: agent binary not found/executable at: $AGENT_BIN"
        return 1
    fi

    # Relaunch detached so it survives this script exiting.
    nohup "$AGENT_BIN" --launchd >/dev/null 2>&1 &
    disown 2>/dev/null
    sleep 2

    if pgrep -x "$AGENT_NAME" >/dev/null 2>&1; then
        log "OK: agent is running again (pid $(pgrep -x "$AGENT_NAME" | tr '\n' ' '))."
        notify "Logi Options+ recovered" "The mouse agent had stopped ($reason) and was restarted. Your MX Master 4 buttons should work again."
    else
        log "WARN: agent did not come back after restart attempt."
        notify "Logi Options+ restart failed" "The mouse agent stopped ($reason) but could not be restarted. You may need to reopen Logi Options+ manually."
    fi
}

rotate_log

# Grab pid(s) and their process state.
pids=$(pgrep -x "$AGENT_NAME")

if [ -z "$pids" ]; then
    restart_agent "agent not running"
    exit 0
fi

# Check the state of each matching pid. A healthy agent is S (sleeping) or R (running).
# Z=zombie, T=stopped/traced, U (in STAT) = uninterruptible wait / stuck.
hung=0
for pid in $pids; do
    stat=$(ps -o stat= -p "$pid" 2>/dev/null | tr -d ' ')
    case "$stat" in
        Z*|T*) hung=1 ;;
        U*)    hung=1 ;;   # uninterruptible sleep as primary state = likely wedged
        *)     : ;;        # S, R, I, etc. = healthy
    esac
done

if [ "$hung" -eq 1 ]; then
    restart_agent "agent hung (state=$stat)"
    exit 0
fi

# Detect a dead/killed device manager (cp-dev-mgr) even when the parent agent
# is alive. This is the "buttons stop working but the mouse still moves"
# failure mode that the parent-pid checks above do NOT catch: the top-level
# logioptionsplus_agent stays healthy while the component that maps custom
# buttons has been killed (e.g. SIGKILL / exit status -9).
#
# In `launchctl list`, column 1 is the PID (or "-" when not running) and
# column 3 is the service label.
dev_mgr_pid=$(launchctl list 2>/dev/null | awk '$3=="com.logi.cp-dev-mgr"{print $1; exit}')
if [ -n "$dev_mgr_pid" ] && [ "$dev_mgr_pid" = "-" ]; then
    restart_agent "device manager (cp-dev-mgr) not running"
    exit 0
fi

# Healthy: no action, no log spam.
exit 0
