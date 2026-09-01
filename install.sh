#!/bin/bash
#
# install.sh — sets up the Logi Options+ watchdog on this Mac.
# Portable across users: detects $HOME and the current user automatically.
# Requires no admin rights (everything lives in the user's Library).
#
# Usage:  bash install.sh

set -eu

LABEL="com.logi-watchdog.user"
SCRIPT_DIR="$HOME/Library/Application Support/LogiWatchdog"
LOG_DIR="$HOME/Library/Logs/LogiWatchdog"
LA_DIR="$HOME/Library/LaunchAgents"
PLIST="$LA_DIR/$LABEL.plist"
UID_NUM=$(id -u)
HERE="$(cd "$(dirname "$0")" && pwd)"

echo "Installing Logi Options+ watchdog for user '$(whoami)'..."

# 1. Create dirs.
mkdir -p "$SCRIPT_DIR" "$LOG_DIR" "$LA_DIR"

# 2. Copy the scripts into place.
cp "$HERE/logi-watchdog.sh"           "$SCRIPT_DIR/logi-watchdog.sh"
cp "$HERE/uninstall-logi-watchdog.sh" "$SCRIPT_DIR/uninstall-logi-watchdog.sh"
chmod +x "$SCRIPT_DIR/logi-watchdog.sh" "$SCRIPT_DIR/uninstall-logi-watchdog.sh"
echo "  - installed scripts to $SCRIPT_DIR"

# 3. Generate the LaunchAgent plist with the correct absolute path.
#    (launchd does NOT expand $HOME in plist paths, so we bake it in here.)
cat > "$PLIST" <<PLIST_EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>$LABEL</string>
    <key>ProgramArguments</key>
    <array>
        <string>/bin/bash</string>
        <string>$SCRIPT_DIR/logi-watchdog.sh</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>StartInterval</key>
    <integer>30</integer>
    <key>LimitLoadToSessionType</key>
    <string>Aqua</string>
    <key>StandardOutPath</key>
    <string>$LOG_DIR/launchd.out.log</string>
    <key>StandardErrorPath</key>
    <string>$LOG_DIR/launchd.err.log</string>
</dict>
</plist>
PLIST_EOF
echo "  - wrote LaunchAgent to $PLIST"

# 4. Validate the plist.
plutil -lint "$PLIST" >/dev/null && echo "  - plist validated"

# 5. (Re)load into launchd.
launchctl bootout "gui/$UID_NUM/$LABEL" 2>/dev/null || true
launchctl bootstrap "gui/$UID_NUM" "$PLIST"
launchctl enable "gui/$UID_NUM/$LABEL" 2>/dev/null || true
launchctl kickstart "gui/$UID_NUM/$LABEL" 2>/dev/null || true

# 6. Verify.
if launchctl list | grep -q "$LABEL"; then
    echo "Done. Watchdog is loaded and runs every 30s + at login."
    echo "Log: $LOG_DIR/logi-watchdog.log"
    echo "Uninstall: bash \"$SCRIPT_DIR/uninstall-logi-watchdog.sh\""
else
    echo "WARNING: watchdog not found in launchctl list. Try logging out/in."
fi
