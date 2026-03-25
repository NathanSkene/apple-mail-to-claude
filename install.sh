#!/bin/bash
# One-command installer for Imperial Email Extraction
# Usage: bash install.sh
#
# This script:
# 1. Installs Bun (if needed)
# 2. Installs QMD (if needed)
# 3. Copies scripts to ~/.claude/scripts/email/
# 4. Finds your Apple Mail Imperial account
# 5. Runs initial email conversion
# 6. Creates QMD collection + index
# 7. Adds QMD MCP server to Claude Code settings
# 8. Sets up cron for automatic sync

set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
INSTALL_DIR="$HOME/.claude/scripts/email"

echo ""
echo "============================================"
echo "  Imperial Email Extraction — Installer"
echo "============================================"
echo ""

# ──────────────────────────────────────────────
# Step 1: Bun
# ──────────────────────────────────────────────
echo "Step 1/8: Checking Bun..."

if command -v bun &>/dev/null; then
    echo "  Bun already installed: $(bun --version)"
else
    echo "  Installing Bun (JavaScript runtime for QMD)..."
    curl -fsSL https://bun.sh/install | bash
    export PATH="$HOME/.bun/bin:$PATH"
    echo "  Bun installed: $(bun --version)"
fi
echo ""

# ──────────────────────────────────────────────
# Step 2: QMD
# ──────────────────────────────────────────────
echo "Step 2/8: Checking QMD..."

if command -v qmd &>/dev/null; then
    echo "  QMD already installed."
else
    echo "  Installing QMD (local search engine)..."
    bun install -g qmd
    echo "  QMD installed."
fi
echo ""

# ──────────────────────────────────────────────
# Step 3: Copy scripts
# ──────────────────────────────────────────────
echo "Step 3/8: Installing scripts to $INSTALL_DIR..."

mkdir -p "$INSTALL_DIR"
cp "$REPO_DIR/mbox_to_markdown.py" "$INSTALL_DIR/"
cp "$REPO_DIR/sync-imperial-email.sh" "$INSTALL_DIR/"
chmod +x "$INSTALL_DIR/sync-imperial-email.sh"
chmod +x "$INSTALL_DIR/mbox_to_markdown.py"
echo "  Scripts installed."
echo ""

# ──────────────────────────────────────────────
# Step 4: Find Apple Mail account
# ──────────────────────────────────────────────
echo "Step 4/8: Finding your Apple Mail accounts..."
echo ""

MAIL_DIR="$HOME/Library/Mail/V10"
if [ ! -d "$MAIL_DIR" ]; then
    echo "  ERROR: Apple Mail directory not found at $MAIL_DIR"
    echo ""
    echo "  Make sure:"
    echo "    1. Apple Mail is open"
    echo "    2. Your Imperial email account is added"
    echo "    3. Mail has finished syncing (give it time for large mailboxes)"
    echo ""
    echo "  Then re-run: bash install.sh"
    exit 1
fi

# List accounts
declare -a UUIDS=()
i=1
for dir in "$MAIL_DIR"/*/; do
    uuid=$(basename "$dir")
    # Skip non-UUID directories
    if [[ ! "$uuid" =~ ^[A-F0-9-]{36}$ ]]; then
        continue
    fi

    # Count emails
    email_count=$(find "$dir" -name "*.emlx" 2>/dev/null | wc -l | tr -d ' ')

    # Try to get account info
    account_info=""
    plist="$dir/.AccountInfo.plist"
    if [ -f "$plist" ]; then
        account_info=$(plutil -p "$plist" 2>/dev/null | grep -iE "AccountIdentifier|EmailAddresses|username" | head -3 | sed 's/^/     /' || true)
    fi

    echo "  $i) $uuid  ($email_count emails)"
    if [ -n "$account_info" ]; then
        echo "$account_info"
    fi
    echo ""

    UUIDS+=("$uuid")
    i=$((i + 1))
done

if [ ${#UUIDS[@]} -eq 0 ]; then
    echo "  ERROR: No Apple Mail accounts found."
    echo "  Add your Imperial email to Apple Mail and let it sync first."
    exit 1
fi

echo "Which account is your Imperial email? Enter the number:"
read -r choice

# Validate choice (1-indexed)
idx=$((choice - 1))
if [ "$idx" -lt 0 ] || [ "$idx" -ge "${#UUIDS[@]}" ]; then
    echo "Invalid choice."
    exit 1
fi

SELECTED_UUID="${UUIDS[$idx]}"
echo ""
echo "  Selected: $SELECTED_UUID"

# Update the sync script with the UUID
sed -i '' "s|REPLACE-WITH-YOUR-UUID|$SELECTED_UUID|g" "$INSTALL_DIR/sync-imperial-email.sh"
echo "  Configured sync script with your account UUID."
echo ""

# ──────────────────────────────────────────────
# Step 5: Initial conversion
# ──────────────────────────────────────────────
echo "Step 5/8: Converting emails to markdown..."
echo "  (This may take 10-30 minutes for a large mailbox)"
echo ""

mkdir -p "$HOME/Mail/Imperial/markdown"

python3 "$INSTALL_DIR/mbox_to_markdown.py" \
    --apple-mail --incremental \
    --mail-root "$HOME/Library/Mail/V10/$SELECTED_UUID" \
    "$HOME/Mail/Imperial/markdown/"

email_count=$(find "$HOME/Mail/Imperial/markdown" -name "*.md" 2>/dev/null | wc -l | tr -d ' ')
echo ""
echo "  Converted $email_count emails to ~/Mail/Imperial/markdown/"
echo ""

# ──────────────────────────────────────────────
# Step 6: Create QMD collection + index
# ──────────────────────────────────────────────
echo "Step 6/8: Creating search index..."

# Check if collection already exists
if qmd collection list 2>/dev/null | grep -q "imperial-email"; then
    echo "  QMD collection 'imperial-email' already exists, updating..."
else
    qmd collection add "$HOME/Mail/Imperial/markdown" --name imperial-email --mask "**/*.md"
    echo "  Created QMD collection 'imperial-email'"
fi

echo "  Indexing emails (this runs locally, nothing leaves your Mac)..."
qmd update
echo "  Building search embeddings (may take a few minutes)..."
timeout 1200 qmd embed || echo "  Embedding timed out — will complete on next sync cycle"
echo "  Search index ready."
echo ""

# ──────────────────────────────────────────────
# Step 7: Add QMD to Claude Code MCP settings
# ──────────────────────────────────────────────
echo "Step 7/8: Configuring Claude Code..."

SETTINGS_FILE="$HOME/.claude/settings.json"
QMD_PATH=$(which qmd 2>/dev/null || echo "$HOME/.bun/bin/qmd")

if [ -f "$SETTINGS_FILE" ]; then
    # Check if qmd MCP server already configured
    if grep -q '"qmd"' "$SETTINGS_FILE" 2>/dev/null; then
        echo "  QMD MCP server already in Claude Code settings."
    else
        echo ""
        echo "  Claude Code settings file exists but doesn't have QMD configured."
        echo ""
        echo "  Please add this to the 'mcpServers' section in $SETTINGS_FILE:"
        echo ""
        echo '    "qmd": {'
        echo "      \"command\": \"$QMD_PATH\","
        echo '      "args": ["mcp"]'
        echo '    }'
        echo ""
        echo "  Or ask Claude Code to do it: 'Add QMD as an MCP server'"
    fi
else
    # Create settings file with QMD
    mkdir -p "$HOME/.claude"
    cat > "$SETTINGS_FILE" << SETTINGS_EOF
{
  "mcpServers": {
    "qmd": {
      "command": "$QMD_PATH",
      "args": ["mcp"]
    }
  }
}
SETTINGS_EOF
    echo "  Created $SETTINGS_FILE with QMD MCP server."
fi
echo ""

# ──────────────────────────────────────────────
# Step 8: Cron setup
# ──────────────────────────────────────────────
echo "Step 8/8: Automatic sync setup"
echo ""

SYNC_SCRIPT="$INSTALL_DIR/sync-imperial-email.sh"
QMD_BIN=$(which qmd 2>/dev/null || echo "$HOME/.bun/bin/qmd")

# Check if cron already has our sync
if crontab -l 2>/dev/null | grep -q "sync-imperial-email"; then
    echo "  Cron job already exists."
else
    echo "  To sync emails automatically every 30 minutes, run:"
    echo ""
    echo "    crontab -e"
    echo ""
    echo "  And add these two lines:"
    echo ""
    echo "    0,30 * * * * $SYNC_SCRIPT >> /tmp/sync-imperial.log 2>&1"
    echo "    5,35 * * * * $QMD_BIN update >> /tmp/qmd-update.log 2>&1 && timeout 1200 $QMD_BIN embed >> /tmp/qmd-update.log 2>&1"
    echo ""
    echo "  Or I can add them for you now. Add cron jobs? (y/n)"
    read -r add_cron

    if [[ "$add_cron" == "y" || "$add_cron" == "Y" ]]; then
        (crontab -l 2>/dev/null || true; echo "0,30 * * * * $SYNC_SCRIPT >> /tmp/sync-imperial.log 2>&1"; echo "5,35 * * * * $QMD_BIN update >> /tmp/qmd-update.log 2>&1 && timeout 1200 $QMD_BIN embed >> /tmp/qmd-update.log 2>&1") | crontab -
        echo "  Cron jobs added."
    else
        echo "  Skipped. You can add them later."
    fi
fi

echo ""
echo "============================================"
echo "  Setup complete!"
echo "============================================"
echo ""
echo "  Emails:     $email_count converted"
echo "  Location:   ~/Mail/Imperial/markdown/"
echo "  Search:     qmd search 'query' -c imperial-email"
echo ""
echo "  Next: restart Claude Code, then ask it to"
echo "  'search my Imperial emails for ...'"
echo ""
