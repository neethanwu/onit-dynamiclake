#!/bin/sh
# Installs a throwaway LaunchAgent that drives onit through running, finished and failed,
# so the plugin can be checked in DynamicLake. Remove it with: Tools/test-agent.sh remove
#
# Every 2 minutes it runs for 15 seconds, then alternates between succeeding and failing
# with a "No such file or directory" error.
set -e
LABEL=com.neethanwu.onit-test
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
# Not under Application Support: onit treats programs there as app helpers and hides them.
DIR="$HOME/.onit-dynamiclake-test"

if [ "$1" = "remove" ]; then
  launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
  rm -f "$PLIST"
  rm -rf "$DIR"
  echo "Removed $LABEL"
  exit 0
fi

mkdir -p "$DIR"
cat > "$DIR/run.sh" <<'SCRIPT'
#!/bin/sh
COUNT_FILE="$(dirname "$0")/count"
N=$(( $(cat "$COUNT_FILE" 2>/dev/null || echo 0) + 1 ))
echo $N > "$COUNT_FILE"
echo "run $N started $(date)"
sleep 15
if [ $((N % 2)) -eq 0 ]; then
  echo "cat: /Users/me/Reports/nightly.csv: No such file or directory" >&2
  exit 1
fi
echo "run $N done"
SCRIPT
chmod +x "$DIR/run.sh"

cat > "$PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>$LABEL</string>
  <key>ProgramArguments</key><array><string>$DIR/run.sh</string></array>
  <key>StartInterval</key><integer>120</integer>
  <key>StandardOutPath</key><string>$DIR/test.log</string>
  <key>StandardErrorPath</key><string>$DIR/test.log</string>
</dict>
</plist>
PLIST
launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$PLIST"
launchctl kickstart "gui/$(id -u)/$LABEL"
echo "Installed $LABEL; it runs now and every 2 minutes. Remove it with: $0 remove"
