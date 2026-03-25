#!/bin/bash
# Incremental sync: Apple Mail (Imperial) → markdown
# Designed to run via cron every 30 minutes (at :00 and :30)
#
# SETUP: Edit IMPERIAL_ACCOUNT below with your Apple Mail account UUID.
#        Run setup.sh to find it automatically.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
OUTPUT_DIR="$HOME/Mail/Imperial/markdown"
LOG="$HOME/Mail/Imperial/sync.log"

# >>> EDIT THIS: Your Apple Mail account UUID <<<
IMPERIAL_ACCOUNT="$HOME/Library/Mail/V10/REPLACE-WITH-YOUR-UUID"

if [[ "$IMPERIAL_ACCOUNT" == *"REPLACE-WITH"* ]]; then
    echo "ERROR: Edit sync-imperial-email.sh and set your Apple Mail account UUID" >&2
    echo "Run: bash setup.sh  — to find your UUID" >&2
    exit 1
fi

mkdir -p "$OUTPUT_DIR" "$(dirname "$LOG")"

echo "$(date '+%Y-%m-%d %H:%M:%S') Starting email sync..." >> "$LOG"

# Convert new emails to markdown (scoped to Imperial account only)
python3 "$SCRIPT_DIR/mbox_to_markdown.py" --apple-mail --incremental --mail-root "$IMPERIAL_ACCOUNT" "$OUTPUT_DIR" >> "$LOG" 2>&1

echo "$(date '+%Y-%m-%d %H:%M:%S') Sync complete." >> "$LOG"
