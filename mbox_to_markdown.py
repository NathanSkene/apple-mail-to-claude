#!/usr/bin/env python3
"""
Convert Apple Mail .mbox exports (or ~/Library/Mail) to markdown files
for indexing by QMD.

Usage:
    # Convert Apple Mail's local storage directly (no export needed)
    python3 mbox_to_markdown.py --apple-mail ~/Mail/Imperial/markdown/

    # Incremental update (skip already-converted emails)
    python3 mbox_to_markdown.py --apple-mail --incremental ~/Mail/Imperial/markdown/

    # Scope to specific Apple Mail account
    python3 mbox_to_markdown.py --apple-mail --incremental --mail-root ~/Library/Mail/V10/YOUR-UUID ~/Mail/Imperial/markdown/
"""

import mailbox
import email
import email.policy
import os
import sys
import re
import json
import hashlib
import html
from datetime import datetime
from pathlib import Path
from email.utils import parsedate_to_datetime
import argparse


def clean_filename(s, max_len=80):
    """Create safe filename from email subject."""
    if not s:
        return "no-subject"
    s = re.sub(r'[<>:"/\\|?*\x00-\x1f]', '', s)
    s = re.sub(r'\s+', ' ', s).strip()
    s = s[:max_len]
    return s or "no-subject"


def extract_text_from_html(html_content):
    """Simple HTML to text conversion."""
    if not html_content:
        return ""
    # Remove style and script blocks
    text = re.sub(r'<style[^>]*>.*?</style>', '', html_content, flags=re.DOTALL | re.IGNORECASE)
    text = re.sub(r'<script[^>]*>.*?</script>', '', text, flags=re.DOTALL | re.IGNORECASE)
    # Convert common tags
    text = re.sub(r'<br\s*/?>', '\n', text, flags=re.IGNORECASE)
    text = re.sub(r'<p[^>]*>', '\n\n', text, flags=re.IGNORECASE)
    text = re.sub(r'</p>', '', text, flags=re.IGNORECASE)
    text = re.sub(r'<div[^>]*>', '\n', text, flags=re.IGNORECASE)
    text = re.sub(r'<li[^>]*>', '\n- ', text, flags=re.IGNORECASE)
    # Remove remaining tags
    text = re.sub(r'<[^>]+>', '', text)
    # Decode HTML entities
    text = html.unescape(text)
    # Clean up whitespace
    text = re.sub(r'\n{3,}', '\n\n', text)
    text = re.sub(r' {2,}', ' ', text)
    return text.strip()


def get_body(msg):
    """Extract body text from email message."""
    text_body = None
    html_body = None

    if msg.is_multipart():
        for part in msg.walk():
            content_type = part.get_content_type()
            disposition = str(part.get("Content-Disposition", ""))
            if "attachment" in disposition:
                continue
            try:
                payload = part.get_payload(decode=True)
                if payload is None:
                    continue
                charset = part.get_content_charset() or 'utf-8'
                try:
                    decoded = payload.decode(charset, errors='replace')
                except (LookupError, UnicodeDecodeError):
                    decoded = payload.decode('utf-8', errors='replace')

                if content_type == 'text/plain' and text_body is None:
                    text_body = decoded
                elif content_type == 'text/html' and html_body is None:
                    html_body = decoded
            except Exception:
                continue
    else:
        try:
            payload = msg.get_payload(decode=True)
            if payload:
                charset = msg.get_content_charset() or 'utf-8'
                try:
                    decoded = payload.decode(charset, errors='replace')
                except (LookupError, UnicodeDecodeError):
                    decoded = payload.decode('utf-8', errors='replace')

                if msg.get_content_type() == 'text/html':
                    html_body = decoded
                else:
                    text_body = decoded
        except Exception:
            pass

    # Prefer text, fall back to converted HTML
    if text_body:
        return text_body.strip()
    elif html_body:
        return extract_text_from_html(html_body)
    return ""


def get_attachments(msg):
    """List attachment filenames."""
    attachments = []
    if msg.is_multipart():
        for part in msg.walk():
            disposition = str(part.get("Content-Disposition", ""))
            if "attachment" in disposition:
                filename = part.get_filename()
                if filename:
                    attachments.append(filename)
    return attachments


def msg_to_markdown(msg):
    """Convert email message to markdown string."""
    # Parse headers
    subject = str(msg.get('Subject', 'No Subject'))
    from_addr = str(msg.get('From', 'Unknown'))
    to_addr = str(msg.get('To', ''))
    cc_addr = str(msg.get('Cc', ''))
    message_id = str(msg.get('Message-ID', ''))
    in_reply_to = str(msg.get('In-Reply-To', ''))
    references = str(msg.get('References', ''))

    # Parse date
    date_str = msg.get('Date', '')
    try:
        date_obj = parsedate_to_datetime(date_str)
        date_iso = date_obj.strftime('%Y-%m-%d %H:%M')
        date_folder = date_obj.strftime('%Y-%m')
    except Exception:
        date_iso = date_str
        date_folder = 'unknown-date'

    # Get body and attachments
    body = get_body(msg)
    attachments = get_attachments(msg)

    # Build markdown
    lines = [
        '---',
        f'subject: "{subject.replace(chr(34), chr(39))}"',
        f'from: "{from_addr.replace(chr(34), chr(39))}"',
        f'to: "{to_addr.replace(chr(34), chr(39))}"',
    ]
    if cc_addr:
        lines.append(f'cc: "{cc_addr.replace(chr(34), chr(39))}"')
    lines.extend([
        f'date: "{date_iso}"',
        f'message_id: "{message_id}"',
    ])
    if in_reply_to:
        lines.append(f'in_reply_to: "{in_reply_to}"')
    if attachments:
        lines.append(f'attachments: {json.dumps(attachments)}')
    lines.extend([
        'type: email',
        '---',
        '',
        f'# {subject}',
        '',
        f'**From:** {from_addr}',
        f'**To:** {to_addr}',
    ])
    if cc_addr:
        lines.append(f'**Cc:** {cc_addr}')
    lines.extend([
        f'**Date:** {date_iso}',
    ])
    if attachments:
        lines.append(f'**Attachments:** {", ".join(attachments)}')
    lines.extend([
        '',
        '---',
        '',
        body,
    ])

    return '\n'.join(lines), date_folder, date_iso


def message_hash(msg):
    """Generate unique hash for deduplication."""
    mid = msg.get('Message-ID', '')
    if mid:
        return hashlib.md5(mid.encode()).hexdigest()[:12]
    # Fallback: hash from date + subject + from
    key = f"{msg.get('Date', '')}{msg.get('Subject', '')}{msg.get('From', '')}"
    return hashlib.md5(key.encode()).hexdigest()[:12]


def find_apple_mail_folders(base_path=None):
    """Find Apple Mail's local storage folders containing .emlx files."""
    if base_path is None:
        base_path = Path.home() / 'Library' / 'Mail'

    emlx_dirs = set()
    base = Path(base_path)

    if not base.exists():
        print(f"Apple Mail directory not found: {base}", file=sys.stderr)
        return []

    # Find all .emlx files and collect their parent directories
    for emlx in base.rglob('*.emlx'):
        emlx_dirs.add(emlx.parent)

    return sorted(emlx_dirs)


def parse_emlx(filepath):
    """Parse an Apple Mail .emlx file."""
    try:
        with open(filepath, 'rb') as f:
            # First line is byte count
            first_line = f.readline()
            try:
                byte_count = int(first_line.strip())
            except ValueError:
                # Not a valid emlx
                return None

            # Read the email content
            raw = f.read(byte_count)

        msg = email.message_from_bytes(raw, policy=email.policy.default)
        return msg
    except Exception as e:
        print(f"  Error parsing {filepath}: {e}", file=sys.stderr)
        return None


def convert_mbox(mbox_path, output_dir, incremental=False):
    """Convert .mbox file to markdown files."""
    output = Path(output_dir)
    converted_file = output / '.converted_ids.json'

    # Load already-converted IDs for incremental mode
    converted_ids = set()
    if incremental and converted_file.exists():
        converted_ids = set(json.loads(converted_file.read_text()))

    mbox = mailbox.mbox(mbox_path)
    total = len(mbox)
    converted = 0
    skipped = 0

    print(f"Processing {total} messages from {mbox_path}...")

    for i, msg in enumerate(mbox):
        mid = message_hash(msg)

        if incremental and mid in converted_ids:
            skipped += 1
            continue

        try:
            md_content, date_folder, date_iso = msg_to_markdown(msg)
            subject = clean_filename(str(msg.get('Subject', 'no-subject')))

            # Organize by year-month
            folder = output / date_folder
            folder.mkdir(parents=True, exist_ok=True)

            filename = f"{date_iso[:10]}_{mid}_{subject}.md"
            filepath = folder / filename

            filepath.write_text(md_content, encoding='utf-8')
            converted_ids.add(mid)
            converted += 1

            if converted % 500 == 0:
                print(f"  Converted {converted}/{total} ({skipped} skipped)...")
                # Save progress
                converted_file.write_text(json.dumps(list(converted_ids)))

        except Exception as e:
            print(f"  Error on message {i}: {e}", file=sys.stderr)

    # Save final state
    converted_file.write_text(json.dumps(list(converted_ids)))
    print(f"Done: {converted} converted, {skipped} skipped, {total - converted - skipped} errors")


def convert_apple_mail(output_dir, incremental=False, mail_root=None, folders=None):
    """Convert Apple Mail's local storage to markdown files.

    Args:
        folders: Optional list of folder names to include (e.g. ['INBOX.mbox', 'Sent.mbox']).
                 If None, all folders under mail_root are processed.
    """
    output = Path(output_dir)
    converted_file = output / '.converted_ids.json'

    converted_ids = set()
    if incremental and converted_file.exists():
        converted_ids = set(json.loads(converted_file.read_text()))

    # Find all emlx files (optionally scoped to a specific account folder)
    if mail_root:
        mail_base = Path(mail_root)
    else:
        mail_base = Path.home() / 'Library' / 'Mail'

    if folders:
        # Only scan specified folders
        emlx_files = []
        for folder_name in folders:
            folder_path = mail_base / folder_name
            if folder_path.exists():
                emlx_files.extend(folder_path.rglob('*.emlx'))
    else:
        emlx_files = list(mail_base.rglob('*.emlx'))

    print(f"Found {len(emlx_files)} .emlx files in Apple Mail storage...")

    converted = 0
    skipped = 0
    errors = 0

    for i, emlx_path in enumerate(emlx_files):
        # Skip non-Imperial accounts if possible (check path)
        path_str = str(emlx_path)

        try:
            msg = parse_emlx(emlx_path)
            if msg is None:
                errors += 1
                continue

            mid = message_hash(msg)

            if incremental and mid in converted_ids:
                skipped += 1
                continue

            md_content, date_folder, date_iso = msg_to_markdown(msg)
            subject = clean_filename(str(msg.get('Subject', 'no-subject')))

            folder = output / date_folder
            folder.mkdir(parents=True, exist_ok=True)

            filename = f"{date_iso[:10]}_{mid}_{subject}.md"
            filepath = folder / filename

            filepath.write_text(md_content, encoding='utf-8')
            converted_ids.add(mid)
            converted += 1

            if converted % 500 == 0:
                print(f"  Converted {converted}/{len(emlx_files)} ({skipped} skipped)...")
                converted_file.write_text(json.dumps(list(converted_ids)))

        except Exception as e:
            errors += 1
            if errors < 10:
                print(f"  Error on {emlx_path.name}: {e}", file=sys.stderr)

    converted_file.write_text(json.dumps(list(converted_ids)))
    print(f"Done: {converted} converted, {skipped} skipped, {errors} errors")


def main():
    parser = argparse.ArgumentParser(description='Convert emails to markdown for QMD indexing')
    parser.add_argument('source', nargs='?', help='Path to .mbox file (omit for --apple-mail)')
    parser.add_argument('output', help='Output directory for markdown files')
    parser.add_argument('--apple-mail', action='store_true', help='Read directly from Apple Mail local storage')
    parser.add_argument('--incremental', action='store_true', help='Skip already-converted emails')
    parser.add_argument('--mail-root', help='Scope Apple Mail scan to specific account folder')
    parser.add_argument('--folders', nargs='+', help='Only process these folder names (e.g. INBOX.mbox Sent.mbox)')
    args = parser.parse_args()

    output = Path(args.output)
    output.mkdir(parents=True, exist_ok=True)

    if args.apple_mail:
        convert_apple_mail(args.output, args.incremental, mail_root=args.mail_root, folders=args.folders)
    elif args.source:
        convert_mbox(args.source, args.output, args.incremental)
    else:
        parser.error('Provide a .mbox path or use --apple-mail')


if __name__ == '__main__':
    main()
