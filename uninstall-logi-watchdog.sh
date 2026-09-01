#!/bin/bash
#
# uninstall-logi-watchdog.sh
# Cleanly removes the Logi Options+ watchdog: unloads the LaunchAgent and
# deletes all files it installed. Does NOT touch Logitech's own software.
# Portable across users; requires no admin rights.
#
# Usage:  bash uninstall-logi-watchdog.sh [--keep-logs]

set -u

LABEL="com.logi-watchdog.user"
UID_NUM=$(id -u)
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
SCRIPT_DIR="$HOME/Library/Application Support/LogiWatchdog"
LOG_DIR="$HOME/Library/Logs/LogiWatchdog"

echo "Uninstalling Logi Options+ watchdog ($LABEL)..."

if launchctl print "gui/$UID_NUM/$LABEL" >/dev/null 2>&1; then
    launchctl bootout "gui/$UID_NUM/$LABEL" 2>/dev/null \
        || launchctl unload "$PLIST" 2>/dev/null
    echo "  - unloaded from launchd"
else
    echo "  - not currently loaded in launchd (ok)"
fi

if [ -f "$PLIST" ]; then
    rm -f "$PLIST" && echo "  - removed $PLIST"
else
    echo "  - plist already gone"
fi

if [ -d "$SCRIPT_DIR" ]; then
    rm -rf "$SCRIPT_DIR" && echo "  - removed $SCRIPT_DIR"
else
    echo "  - script dir already gone"
fi

if [ "${1:-}" = "--keep-logs" ]; then
    echo "  - kept logs at $LOG_DIR (--keep-logs)"
else
    if [ -d "$LOG_DIR" ]; then
        rm -rf "$LOG_DIR" && echo "  - removed $LOG_DIR"
    else
        echo "  - log dir already gone"
    fi
fi

if launchctl list | grep -q "$LABEL"; then
    echo "WARNING: $LABEL still appears in 'launchctl list'. Try logging out/in."
else
    echo "Done. Watchdog fully removed. Logitech's own software is untouched."
fi
