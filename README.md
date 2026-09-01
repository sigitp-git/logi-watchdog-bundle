# Logi Options+ Watchdog (macOS)

A small, self-contained macOS watchdog that keeps the **Logi Options+** mouse
agent alive so your Logitech MX Master custom buttons don't silently stop
working.

Tested on macOS 26.x with an MX Master 4. Requires **no admin rights** —
everything installs into the user's `~/Library`.

---

## The problem

The Logi Options+ **agent** (`logioptionsplus_agent`) is the background process
that applies your custom button remaps. When it dies or wedges, the mouse still
moves and left/right click still work, but **custom buttons stop working**.

Logitech ships its own watchdog at
`/Library/LaunchAgents/com.logi.optionsplus.plist` with `KeepAlive` +
`SuccessfulExit=false`. But that only restarts the agent when it **cleanly
exits**. If the agent **hangs** (stuck in a stopped or uninterruptible state) it
never "exits", so Logitech's KeepAlive does **not** recover it — and your custom
buttons stay dead until you manually restart the app.

This watchdog closes that gap: it detects both a **missing** and a **hung**
agent, and restarts it automatically within ~30 seconds.

---

## Install

```bash
bash install.sh
```

This will:
- Copy `logi-watchdog.sh` and `uninstall-logi-watchdog.sh` into
  `~/Library/Application Support/LogiWatchdog/`
- Generate a LaunchAgent plist (`com.logi-watchdog.user`) with the correct
  absolute path for the current user, and validate it
- Load it into `launchd` so it runs **at login** and **every 30 seconds**

> **Prerequisite:** Logi Options+ must be installed. The watchdog manages
> Logitech's agent at the standard path
> `/Library/Application Support/Logitech.localized/LogiOptionsPlus/logioptionsplus_agent.app/…`.
> If it's missing, the watchdog logs an error and posts a notification instead
> of failing silently.

### First-run notification permission

The first time the watchdog posts a notification, macOS may ask whether to allow
notifications from **Script Editor** / `osascript`. Allow it, and future banners
appear silently. Adjust later in **System Settings → Notifications**.

---

## How it works

- Runs at login and every 30 seconds (`StartInterval = 30`).
- Each run inspects the `logioptionsplus_agent` process:
  - **Missing** → restart it.
  - **Hung** (process state `Z` zombie / `T` stopped / `U` uninterruptible) →
    kill it and relaunch a fresh one. *(The case Logitech's KeepAlive misses.)*
  - **Healthy** (state `S`/`R`) → do nothing. No log spam, no notification.
- On a restart it sends `TERM`, then `KILL` if needed, relaunches detached via
  `nohup "<agent>" --launchd &`, writes a log line, and posts a native macOS
  notification:
  - Success: *"Logi Options+ recovered — your custom buttons should work again."*
  - Failure: *"Logi Options+ restart failed — you may need to reopen Logi Options+ manually."*
- The log auto-rotates at 1 MiB.

**Worst-case downtime** if the agent wedges: ~30 seconds, then auto-recovery.

---

## Files

| File | Purpose |
|------|---------|
| `install.sh` | One-command installer (generates the plist for the current user) |
| `logi-watchdog.sh` | The watchdog logic (health check + restart + notify) |
| `uninstall-logi-watchdog.sh` | Clean removal |
| `README.md` | This document |
| `LICENSE` | MIT |

### Installed locations (per user)

| Purpose | Path |
|---------|------|
| Scripts | `~/Library/Application Support/LogiWatchdog/` |
| LaunchAgent | `~/Library/LaunchAgents/com.logi-watchdog.user.plist` |
| Logs | `~/Library/Logs/LogiWatchdog/logi-watchdog.log` |

---

## Everyday commands

**Did the watchdog ever act?**
```bash
cat ~/Library/Logs/LogiWatchdog/logi-watchdog.log
```

**Is the watchdog loaded?**
```bash
launchctl list | grep logi-watchdog
```

**Is the Logi agent healthy right now?**
```bash
PID=$(pgrep -x logioptionsplus_agent)
echo "pid=$PID state=$(ps -o stat= -p "$PID" | tr -d ' ')"   # S or R = healthy
```

**Force a run now:**
```bash
launchctl kickstart "gui/$(id -u)/com.logi-watchdog.user"
```

---

## Test it (simulate a hung agent)

```bash
PID=$(pgrep -x logioptionsplus_agent)
kill -STOP "$PID"                 # freeze the agent (state -> T)
ps -o stat= -p "$PID"             # confirms: T
launchctl kickstart "gui/$(id -u)/com.logi-watchdog.user"   # or wait <=30s
sleep 3
pgrep -x logioptionsplus_agent    # a NEW pid = watchdog recovered it
```
You should get a "Logi Options+ recovered" notification.

---

## Uninstall

```bash
bash uninstall-logi-watchdog.sh            # remove everything
bash uninstall-logi-watchdog.sh --keep-logs # keep the log history
```

Unloads the LaunchAgent and removes the plist, scripts, and logs. Does **not**
touch Logitech's own software. Idempotent (safe to re-run).

---

## Note

The MX Master 4 is new, so the underlying hang may be a Logi Options+
software/firmware bug. **Keep Logi Options+ updated** — if the root cause is
fixed upstream, this watchdog simply becomes a harmless safety net.

---

## License

MIT — see [LICENSE](LICENSE).
