# Apple Mail to Claude

**Talk to your email in plain English.** One install script turns years of email into something you can actually search — using Claude on your Mac.

> *"Find that email from October where someone sent me the contract"*
>
> *"What did HR say about the policy change last year?"*
>
> *"Show me every email I've had with David about the project"*
>
> *"I know someone emailed me a tracking number last week — find it"*

No more scrolling through thousands of emails. No more guessing which folder something ended up in. No more trying twelve different search terms in Outlook. Just ask Claude what you're looking for and it finds it.

Works with any email account — Gmail, Outlook, Exchange, iCloud, work email, personal email. Everything stays on your Mac. No email content is sent anywhere.

## What you'll need before starting

1. **A Mac** (any recent Mac will work)
2. **Your email added to Apple Mail** — open the Mail app, add your email account (Gmail, Outlook, work email, whatever), and let it finish downloading. For large mailboxes this can take 30-60 minutes. You'll see a progress bar at the bottom of Mail.
3. **A Claude account** — sign up at [claude.ai](https://claude.ai) if you don't have one. You need a Pro subscription ($20/month) to use Claude Code.

## Setup

Open Terminal (press Cmd+Space, type "Terminal", hit Enter) and paste this:

```
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/NathanSkene/apple-mail-to-claude/main/install.sh)"
```

The installer will:

- Install a few tools it needs (you may be asked for your Mac password)
- Ask you to grant permission to read your email files (it walks you through this)
- Ask which email account you want to make searchable
- Convert your emails into text files Claude can read
- Set up automatic syncing so new emails appear every 30 minutes

The install itself takes a few minutes. Converting your emails depends on how many you have — a few thousand takes 5 minutes, 40,000+ can take 30-60 minutes. Building the search index can take another 30-60 minutes on top of that (it runs a small AI model on your Mac to understand your emails — no GPU needed, but it's not instant). You can use your Mac normally while it runs.

## Using it

Once setup is done, open a new Terminal window and type `claude`. Then just ask questions about your emails:

- "Find emails from David about the project"
- "What was the last email I got about the conference?"
- "Show me emails from January about the budget"
- "Search for any emails mentioning the deadline"

Claude searches your local email files — nothing is sent to any server except your question to Claude.

**Important:** Use `claude` in Terminal, not claude.ai in your browser. The browser version runs in a sandbox and can't read your files.

## How it works

Apple Mail downloads your emails to your Mac. This tool converts them into simple text files and builds a search index. When you ask Claude a question, it searches that index locally and reads the matching emails.

New emails are picked up automatically every 30 minutes.

Your emails are stored as plain text files in `~/Mail/` on your hard drive. The search index is also local. Nothing leaves your Mac.

## Troubleshooting

**"Network access is disabled"** — You're using Claude in the browser (claude.ai), not Claude Code in Terminal. Open Terminal and type `claude` instead.

**"No emails found"** — Apple Mail hasn't finished downloading yet. Open Mail, check your account is there, and wait for the progress bar to finish. Large mailboxes (40k+ emails) can take an hour.

**"Operation not permitted"** — Terminal needs permission to read your email files. Go to System Settings > Privacy & Security > Full Disk Access, click +, add Terminal, then restart Terminal and try again.

**Claude keeps asking for permission** — Run `claude --dangerously-skip-permissions` instead of just `claude`.

**Emails aren't updating** — Check the sync is running: `crontab -l` in Terminal. You should see two lines mentioning `sync-email`.

## Advanced

<details>
<summary>Manual commands (for power users)</summary>

```bash
# Force a sync now
~/.claude/scripts/email/sync-email.sh

# Search from terminal (replace 'work' with your collection name)
qmd search "budget" -c work

# Semantic search (finds related concepts, not just keyword matches)
qmd vsearch "project update discussion" -c work

# Re-index after manual changes
qmd update && qmd embed
```

</details>

<details>
<summary>Non-interactive install (for scripting)</summary>

```bash
bash install.sh --non-interactive --account 1 --name work
bash install.sh --non-interactive --account 2 --name personal --skip-cron
```

</details>

<details>
<summary>Architecture</summary>

```
Apple Mail (syncs your email)
    |
mbox_to_markdown.py (converts .emlx to .md files)
    |
~/Mail/<collection>/markdown/  (plain text files by month)
    |
QMD (local BM25 + vector search index)
    |
Claude Code (queries via MCP server)
```

Cron runs every 30 minutes to convert new emails and update the index.

</details>
