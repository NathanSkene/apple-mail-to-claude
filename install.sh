#!/bin/bash
# One-command installer for Apple Mail to Claude
# Usage: bash install.sh
#        bash install.sh --non-interactive --account 1 --name work
#
# This script:
# 1. Installs Homebrew (if needed)
# 2. Installs Bun (if needed)
# 3. Installs Claude Code (if needed)
# 4. Installs QMD (if needed)
# 5. Checks Full Disk Access
# 6. Finds your Apple Mail account
# 7. Runs initial email conversion
# 8. Creates QMD collection + index
# 9. Adds QMD MCP server to Claude Code settings
# 10. Sets up cron for automatic sync

set -euo pipefail

# Check git works (on fresh Macs, the git shim triggers Xcode Command Line Tools install)
if ! git --version &>/dev/null 2>&1; then
    echo ""
    echo "  Git is not fully installed yet."
    echo "  macOS may have just shown you an install dialog for Command Line Tools."
    echo "  Click 'Install', wait for it to finish, then re-run this installer."
    echo ""
    # Trigger the dialog if it hasn't appeared
    xcode-select --install 2>/dev/null || true
    exit 1
fi

# If running via curl (no repo files alongside us), clone the repo first
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
if [ ! -f "$SCRIPT_DIR/mbox_to_markdown.py" ]; then
    echo "Downloading apple-mail-to-claude..."
    REPO_DIR="$HOME/.apple-mail-to-claude"
    if [ -d "$REPO_DIR" ]; then
        cd "$REPO_DIR" && git pull -q
    else
        git clone -q https://github.com/NathanSkene/apple-mail-to-claude.git "$REPO_DIR"
    fi
    # Re-exec from the cloned repo
    exec bash "$REPO_DIR/install.sh" "$@"
fi

REPO_DIR="$SCRIPT_DIR"
INSTALL_DIR="$HOME/.claude/scripts/email"

# ──────────────────────────────────────────────
# Parse arguments
# ──────────────────────────────────────────────
NON_INTERACTIVE=false
ACCOUNT_CHOICE=""
COLLECTION_NAME_ARG=""
SKIP_CRON=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --non-interactive) NON_INTERACTIVE=true; shift ;;
        --account) ACCOUNT_CHOICE="$2"; shift 2 ;;
        --name) COLLECTION_NAME_ARG="$2"; shift 2 ;;
        --skip-cron) SKIP_CRON=true; shift ;;
        -h|--help)
            echo "Usage: bash install.sh [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --non-interactive    Skip all prompts (use with --account and --name)"
            echo "  --account N          Select account number N (1-indexed)"
            echo "  --name NAME          Collection name (e.g. 'work', 'personal')"
            echo "  --skip-cron          Don't set up automatic sync"
            echo "  -h, --help           Show this help"
            exit 0
            ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done

prompt_user() {
    if [ "$NON_INTERACTIVE" = true ]; then
        echo "$2"  # Return default
    else
        read -rp "$1" response
        echo "${response:-$2}"
    fi
}

echo ""
echo "============================================"
echo "  Apple Mail to Claude — Installer"
echo "============================================"
echo ""

# ──────────────────────────────────────────────
# Step 1: Homebrew
# ──────────────────────────────────────────────
echo "Step 1/10: Checking Homebrew..."

if command -v brew &>/dev/null; then
    echo "  Homebrew already installed."
else
    echo "  Installing Homebrew (macOS package manager)..."
    echo "  You may be asked for your Mac password."
    echo ""
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

    # Add brew to PATH for Apple Silicon Macs
    if [ -f /opt/homebrew/bin/brew ]; then
        eval "$(/opt/homebrew/bin/brew shellenv)"
        # Add to shell profile if not already there
        SHELL_PROFILE="$HOME/.zprofile"
        if ! grep -q 'homebrew' "$SHELL_PROFILE" 2>/dev/null; then
            echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> "$SHELL_PROFILE"
            echo "  Added Homebrew to $SHELL_PROFILE"
        fi
    fi
    echo "  Homebrew installed."
fi
echo ""

# ──────────────────────────────────────────────
# Step 2: Bun
# ──────────────────────────────────────────────
echo "Step 2/10: Checking Bun..."

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
# Step 3: Claude Code
# ──────────────────────────────────────────────
echo "Step 3/10: Checking Claude Code..."

if command -v claude &>/dev/null; then
    echo "  Claude Code already installed."
else
    echo "  Installing Claude Code..."
    echo ""
    echo "  IMPORTANT: Claude Code is a terminal app that runs on your Mac."
    echo "  It is NOT the same as claude.ai in your browser."
    echo "  The browser version runs in a sandbox and cannot access your files."
    echo ""
    brew install claude-code 2>/dev/null || npm install -g @anthropic-ai/claude-code 2>/dev/null || {
        echo ""
        echo "  Could not install Claude Code automatically."
        echo "  Please install it manually: https://claude.ai/claude-code"
        echo "  Then re-run this installer."
        exit 1
    }
    echo "  Claude Code installed."
fi
echo ""

# ──────────────────────────────────────────────
# Step 4: QMD
# ──────────────────────────────────────────────
echo "Step 4/10: Checking QMD..."

if command -v qmd &>/dev/null; then
    echo "  QMD already installed."
else
    echo "  Installing QMD (local search engine)..."
    bun install -g qmd
    echo "  QMD installed."
fi
echo ""

# ──────────────────────────────────────────────
# Step 5: Full Disk Access check
# ──────────────────────────────────────────────
echo "Step 5/10: Checking Full Disk Access..."

# Test if we can read Apple Mail data
MAIL_DIR="$HOME/Library/Mail/V10"
if [ -d "$MAIL_DIR" ]; then
    # Try to actually list contents — will fail without Full Disk Access
    if ls "$MAIL_DIR" &>/dev/null 2>&1; then
        echo "  Full Disk Access OK."
    else
        echo ""
        echo "  WARNING: Cannot read Apple Mail data."
        echo ""
        echo "  You need to grant Full Disk Access to your terminal app:"
        echo ""
        echo "    1. Open System Settings"
        echo "    2. Go to Privacy & Security > Full Disk Access"
        echo "    3. Click the + button"
        echo "    4. Add Terminal (or iTerm, or whichever terminal you use)"
        echo "    5. Quit and reopen your terminal"
        echo "    6. Re-run this installer"
        echo ""
        if [ "$NON_INTERACTIVE" = true ]; then
            echo "  Continuing anyway (non-interactive mode)..."
        else
            echo "  Press Enter to continue anyway, or Ctrl+C to fix this first."
            read -r
        fi
    fi
else
    echo ""
    echo "  Apple Mail directory not found at $MAIL_DIR"
    echo ""
    echo "  Make sure:"
    echo "    1. Apple Mail is open"
    echo "    2. Your email account is added"
    echo "    3. Mail has finished syncing (give it time for large mailboxes)"
    echo ""
    echo "  Then re-run: bash install.sh"
    exit 1
fi
echo ""

# ──────────────────────────────────────────────
# Step 6: Copy scripts
# ──────────────────────────────────────────────
echo "Step 6/10: Installing scripts to $INSTALL_DIR..."

mkdir -p "$INSTALL_DIR"
cp "$REPO_DIR/mbox_to_markdown.py" "$INSTALL_DIR/"
cp "$REPO_DIR/sync-email.sh" "$INSTALL_DIR/"
chmod +x "$INSTALL_DIR/sync-email.sh"
chmod +x "$INSTALL_DIR/mbox_to_markdown.py"
echo "  Scripts installed."
echo ""

# ──────────────────────────────────────────────
# Step 7: Find Apple Mail account
# ──────────────────────────────────────────────
echo "Step 7/10: Finding your Apple Mail accounts..."
echo ""

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
    echo "  Add your email account to Apple Mail and let it sync first."
    exit 1
fi

# Select account
if [ -n "$ACCOUNT_CHOICE" ]; then
    choice="$ACCOUNT_CHOICE"
else
    echo "Which account do you want to make searchable? Enter the number:"
    read -r choice
fi

# Validate choice (1-indexed)
idx=$((choice - 1))
if [ "$idx" -lt 0 ] || [ "$idx" -ge "${#UUIDS[@]}" ]; then
    echo "Invalid choice."
    exit 1
fi

SELECTED_UUID="${UUIDS[$idx]}"
echo ""
echo "  Selected: $SELECTED_UUID"

# Collection name
if [ -n "$COLLECTION_NAME_ARG" ]; then
    COLLECTION_NAME="$COLLECTION_NAME_ARG"
else
    echo ""
    echo "  Give this email collection a short name (e.g. 'work', 'personal', 'gmail'):"
    read -r COLLECTION_NAME
    COLLECTION_NAME=${COLLECTION_NAME:-email}
fi
# Sanitise: lowercase, no spaces
COLLECTION_NAME=$(echo "$COLLECTION_NAME" | tr '[:upper:]' '[:lower:]' | tr ' ' '-')

echo "  Collection name: $COLLECTION_NAME"

# Update the sync script with the UUID and collection name
sed -i '' "s|REPLACE-WITH-YOUR-UUID|$SELECTED_UUID|g" "$INSTALL_DIR/sync-email.sh"
sed -i '' "s|REPLACE-WITH-COLLECTION-NAME|$COLLECTION_NAME|g" "$INSTALL_DIR/sync-email.sh"
echo "  Configured sync script."
echo ""

# ──────────────────────────────────────────────
# Step 8: Initial conversion
# ──────────────────────────────────────────────
echo "Step 8/10: Converting emails to markdown..."
echo "  (This may take 10-30 minutes for a large mailbox)"
echo ""

MAIL_OUTPUT="$HOME/Mail/$COLLECTION_NAME/markdown"
mkdir -p "$MAIL_OUTPUT"

python3 "$INSTALL_DIR/mbox_to_markdown.py" \
    --apple-mail --incremental \
    --mail-root "$HOME/Library/Mail/V10/$SELECTED_UUID" \
    "$MAIL_OUTPUT/"

email_count=$(find "$MAIL_OUTPUT" -name "*.md" 2>/dev/null | wc -l | tr -d ' ')
echo ""
echo "  Converted $email_count emails to ~/Mail/$COLLECTION_NAME/markdown/"
echo ""

# ──────────────────────────────────────────────
# Step 9: Create QMD collection + index
# ──────────────────────────────────────────────
echo "Step 9/10: Creating search index..."

# Check if collection already exists
if qmd collection list 2>/dev/null | grep -q "$COLLECTION_NAME"; then
    echo "  QMD collection '$COLLECTION_NAME' already exists, updating..."
else
    qmd collection add "$MAIL_OUTPUT" --name "$COLLECTION_NAME" --mask "**/*.md"
    echo "  Created QMD collection '$COLLECTION_NAME'"
fi

echo "  Indexing emails (this runs locally, nothing leaves your Mac)..."
qmd update
echo "  Building search embeddings (may take a few minutes)..."
timeout 1200 qmd embed || echo "  Embedding timed out — will complete on next sync cycle"
echo "  Search index ready."
echo ""

# ──────────────────────────────────────────────
# Step 10: Add QMD to Claude Code MCP settings
# ──────────────────────────────────────────────
echo "Step 10/10: Configuring Claude Code..."

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
# Cron setup
# ──────────────────────────────────────────────
if [ "$SKIP_CRON" = true ]; then
    echo "  Skipping cron setup (--skip-cron)."
else
    echo "Setting up automatic sync..."
    echo ""

    SYNC_SCRIPT="$INSTALL_DIR/sync-email.sh"
    QMD_BIN=$(which qmd 2>/dev/null || echo "$HOME/.bun/bin/qmd")

    # Check if cron already has our sync
    if crontab -l 2>/dev/null | grep -q "sync-email"; then
        echo "  Cron job already exists."
    else
        if [ "$NON_INTERACTIVE" = true ]; then
            add_cron="y"
        else
            echo "  To sync emails automatically every 30 minutes, I can add cron jobs."
            echo "  Add cron jobs? (y/n)"
            read -r add_cron
        fi

        if [[ "$add_cron" == "y" || "$add_cron" == "Y" ]]; then
            (crontab -l 2>/dev/null || true; echo "0,30 * * * * $SYNC_SCRIPT >> /tmp/sync-email.log 2>&1"; echo "5,35 * * * * $QMD_BIN update >> /tmp/qmd-update.log 2>&1 && timeout 1200 $QMD_BIN embed >> /tmp/qmd-update.log 2>&1") | crontab -
            echo "  Cron jobs added."
        else
            echo "  Skipped. You can add them later with:"
            echo "    crontab -e"
            echo ""
            echo "  Add these lines:"
            echo "    0,30 * * * * $SYNC_SCRIPT >> /tmp/sync-email.log 2>&1"
            echo "    5,35 * * * * $QMD_BIN update >> /tmp/qmd-update.log 2>&1 && timeout 1200 $QMD_BIN embed >> /tmp/qmd-update.log 2>&1"
        fi
    fi
fi

echo ""
echo "============================================"
echo "  Setup complete!"
echo "============================================"
echo ""
echo "  Emails:     $email_count converted"
echo "  Location:   ~/Mail/$COLLECTION_NAME/markdown/"
echo "  Search:     qmd search 'query' -c $COLLECTION_NAME"
echo ""
echo "  Next steps:"
echo "    1. Open a new terminal window"
echo "    2. Run: claude"
echo "    3. Ask: 'search my emails for ...'"
echo ""
echo "  NOTE: Use 'claude' in the terminal, NOT claude.ai in your browser."
echo "  The browser version cannot access your files."
echo ""
