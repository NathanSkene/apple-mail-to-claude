#!/bin/bash
# Incremental sync: Apple Mail → markdown
# Designed to run via cron every 30 minutes
#
# Configured automatically by install.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# >>> These are set by install.sh <<<
ACCOUNT_UUID="REPLACE-WITH-YOUR-UUID"
COLLECTION_NAME="REPLACE-WITH-COLLECTION-NAME"

OUTPUT_DIR="$HOME/Mail/$COLLECTION_NAME/markdown"
LOG="$HOME/Mail/$COLLECTION_NAME/sync.log"
MAIL_ROOT="$HOME/Library/Mail/V10/$ACCOUNT_UUID"

if [[ "$ACCOUNT_UUID" == *"REPLACE-WITH"* ]]; then
    echo "ERROR: Run install.sh first to configure this script." >&2
    exit 1
fi

mkdir -p "$OUTPUT_DIR" "$(dirname "$LOG")"

echo "$(date '+%Y-%m-%d %H:%M:%S') Starting email sync..." >> "$LOG"

python3 "$SCRIPT_DIR/mbox_to_markdown.py" --apple-mail --incremental --mail-root "$MAIL_ROOT" "$OUTPUT_DIR" >> "$LOG" 2>&1

echo "$(date '+%Y-%m-%d %H:%M:%S') Sync complete." >> "$LOG"
