#!/bin/sh
# Screenshot a sample Org report's HTML export for the README.
# Usage: examples/report-screenshot.sh [REPORT] [OUT.png]
# Defaults: lab-draw -> docs/screenshots/org-report.png.  Run
# examples/reports.el first; needs a headless Chromium (CHROMIUM=...).
set -eu
here=$(cd "$(dirname "$0")" && pwd)
report=${1:-lab-draw}
out=${2:-$here/../docs/screenshots/org-report.png}
chromium=${CHROMIUM:-$(command -v chromium || command -v chromium-browser || command -v google-chrome)}
"$chromium" --headless --no-sandbox --disable-gpu --hide-scrollbars \
  --force-device-scale-factor=1 --window-size=1000,1500 \
  --screenshot="$out" "file://$here/reports/$report.html"
echo "wrote $out"
