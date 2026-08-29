# Gmail unread badge

Berg polls Gmail label metadata once per minute and displays the sum of the
configured unread counts. It never requests message lists, headers, bodies, or
attachments. The badge supports multiple Google accounts and multiple labels
per account.

## Dependencies

Google's official `oauth2l` 1.3.5 Linux binary is installed by the workstation
Ansible configuration at `/usr/local/bin/oauth2l`. Its versioned archive and
SHA-256 checksum are pinned in the managed package role; no AUR recipe is used.

## Configuration

Create `~/.config/gmail-unread/config.json` from
`gmail-unread-config.example.json`. Keep the real config, OAuth client JSON, and
token caches out of the dotfiles repository.

```bash
mkdir -p ~/.config/gmail-unread ~/.local/state/gmail-unread
chmod 700 ~/.config/gmail-unread ~/.local/state/gmail-unread
cp ~/.config/quickshell/berg/gmail-unread-config.example.json \
  ~/.config/gmail-unread/config.json
chmod 600 ~/.config/gmail-unread/config.json \
  ~/.config/gmail-unread/client_secret.json
```

The top-level `credentials` value is shared only as an OAuth client definition;
each account must use a distinct `cache` file because that file contains the
account's refresh token. An account may override `credentials` if it uses a
different Google Cloud OAuth client.

`browserIndex` maps an account to Gmail's `/mail/u/N/` browser route. Use the
same number shown in that account's Gmail URL, such as `0` for `/u/0` and `1`
for `/u/1`. Indices must be unique. If omitted, they default to the account's
position in the configuration array.

Label strings use their Gmail API IDs. Built-in labels such as `INBOX` can be
written directly. Custom labels normally have IDs such as `Label_42`; the
optional `name` is only the friendly text shown in the tooltip.

`countField` may be `threadsUnread` (the Gmail-style default) or
`messagesUnread`. Counts for configured labels are summed. If labels overlap,
the same thread or message can therefore contribute to more than one label's
count; the tooltip calls this out.

The bar renders one colored badge per account with unread items. Zero-count
accounts are hidden, and the whole Gmail cell is hidden when the aggregate is
zero unless the integration is unhealthy. Left-clicking a badge opens that
account's Gmail inbox; right-clicking refreshes all configured counts
immediately.

## Authorization

Complete the Google Cloud desktop OAuth setup, enable the Gmail API, and grant
only `https://www.googleapis.com/auth/gmail.labels`. Then authorize each account
explicitly from a terminal:

```bash
~/.config/quickshell/berg/scripts/gmail-unread.py authorize Personal
~/.config/quickshell/berg/scripts/gmail-unread.py authorize Work
```

The background `status` command refuses to run when a cache is absent or has
unsafe permissions, so periodic polling never opens a surprise OAuth browser.
To discover custom label IDs after authorization:

```bash
~/.config/quickshell/berg/scripts/gmail-unread.py labels Personal
```

Validate and fetch once before reloading Berg:

```bash
~/.config/quickshell/berg/scripts/gmail-unread.py validate
~/.config/quickshell/berg/scripts/gmail-unread.py status | jq
qs -c berg ipc call shell reload
qs -c berg ipc call shell gmailUnreadStatus
```

To disable the integration, move or remove
`~/.config/gmail-unread/config.json` and reload Berg. Token caches and the OAuth
client JSON remain in place for a reversible rollback; remove them separately
only if you also intend to revoke the local integration.
