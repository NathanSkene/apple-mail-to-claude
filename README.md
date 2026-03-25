# Imperial Email Extraction for Claude Code

Gives Claude Code the ability to search and read your Imperial College emails. Emails are converted to markdown files and indexed locally on your Mac — nothing leaves your machine.

## Requirements

- macOS
- [Claude Code](https://claude.ai/claude-code) installed
- Apple Mail with your Imperial email account added and synced

## Quick start

```bash
git clone https://github.com/NathanSkene/imperial-email-extraction.git
cd imperial-email-extraction
bash install.sh
```

The installer walks you through everything:

1. Installs [Bun](https://bun.sh) (JavaScript runtime)
2. Installs [QMD](https://github.com/tobi/qmd) (local markdown search engine)
3. Finds your Imperial account in Apple Mail
4. Converts all emails to searchable markdown files
5. Builds a local search index
6. Configures Claude Code to use the search index
7. Sets up automatic sync every 30 minutes

## After setup

Ask Claude Code things like:

- "Search my emails for messages about the budget review"
- "Find emails from Allan Young about recruitment"
- "What did the last email from HR say?"

## How it works

```
Apple Mail (syncs Imperial email via Exchange)
    ↓
mbox_to_markdown.py (converts to text files)
    ↓
~/Mail/Imperial/markdown/
  2026-01/email1.md
  2026-02/email2.md
  ...
    ↓
QMD (indexes files for fast search)
    ↓
Claude Code (searches via MCP server)
```

Emails are stored as simple markdown files in `~/Mail/Imperial/markdown/`, organised by month. Each file has the email headers (from, to, date, subject) and the body text.

A cron job runs every 30 minutes to pick up new emails automatically.

## Manual commands

```bash
# Force a sync now
~/.claude/scripts/email/sync-imperial-email.sh

# Search emails from terminal
qmd search "budget" -c imperial-email

# Semantic search (finds related concepts)
qmd vsearch "grant funding discussion" -c imperial-email

# Check sync status
tail -20 ~/Mail/Imperial/sync.log

# Re-index after manual changes
qmd update && qmd embed
```

## Privacy

- All processing is local — no email content is sent anywhere
- QMD's AI embeddings are computed on your Mac using small local models
- The markdown files are plain text on your hard drive
- Claude Code reads them the same way it reads any local file

## Troubleshooting

**"No .emlx files found"** — Apple Mail hasn't finished syncing. Open Mail, check your Imperial account is there, wait for it to download.

**QMD search returns nothing** — Re-index: `qmd update && qmd embed`

**"command not found: qmd"** — Add to `~/.zshrc`: `export PATH="$HOME/.bun/bin:$PATH"`, then restart terminal.

**"command not found: bun"** — Re-run: `curl -fsSL https://bun.sh/install | bash && source ~/.zshrc`

**Emails aren't updating** — Check cron: `crontab -l`. Check logs: `tail -20 /tmp/sync-imperial.log`
