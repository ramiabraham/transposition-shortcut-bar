#!/bin/sh
# Packages the tool sources in src/ into an installable .xrnx in dist/.
set -e

cd "$(dirname "$0")"
TOOL_ID="com.ramiforms.TranspositionShortcutBar"
OUT="dist/$TOOL_ID.xrnx"

mkdir -p dist
rm -f "$OUT"
(cd "src/$TOOL_ID.xrnx" && zip -q -X -r "../../$OUT" . -x ".DS_Store" -x "preferences.xml")
echo "Built $OUT"
