---
name: oncall-rota
description: >-
  Use when asked who is on call today, to write the daily on-call rota
  message, or to look up the current on-call people from Rootly (the `rootly`
  CLI, `rootly oncall who`). Fills a message template kept outside the repo
  with the current on-call names. Not for raising or triaging an incident.
disable-model-invocation: true
argument-hint: "[send|copy|show]"
---

# On-call rota message

Look up who is on call now with the Rootly CLI, fill the user's message
template, then deliver it as the user chooses (see Delivery). Look-up is
read-only; nothing is posted unless the user picks `send`.

## Keep the wording out of the repo

This repo is public. The message text (company name, channel names, links,
team names) lives only in a sops secret, which home-manager decrypts to a local
template file; never copy any of it into this skill, a commit, a PR, or another
tracked file.

Template path: `${XDG_CONFIG_HOME:-$HOME/.config}/oncall-rota/template.md`

If the file is missing, stop and tell the user the host has no
`oncall_rota_template` secret (it comes from the work identity sops file).
Do not invent message text and do not write one into the repo.

## Template format

The file is the message verbatim, with one placeholder per rota line:

    {{oncall:<schedule>}}

`<schedule>` is a case-insensitive substring of a Rootly schedule name. It is
replaced with `@<Primary> (Primary) & @<Secondary> (Secondary)`. Everything
else is copied unchanged. Neutral example:

```
Today's on-call rota:

Platform: {{oncall:platform}}

Raise incidents in the usual channel.
```

Rules:

- Names are the display name from Rootly, prefixed `@`. For `send`, each name
  becomes a real mention, `<@U...>`, using the Slack user ID found by the
  procedure in Slack IDs below; `show` and `copy` keep plain `@Name`.
- If a level is empty, write `nobody scheduled` for that slot and say so in the
  reply. Never invent a name.
- A placeholder matching zero or several schedules: list the schedule names
  found and ask which is meant. Do not guess.

## Look-up procedure

1. Read the template. Probe the tool: `command -v rootly`. If absent, tell the
   user it comes from `modules.rootly.enable = true` in the host's home-manager
   config, and stop.
2. Auth: `ROOTLY_API_TOKEN` in the environment, or `~/.rootly-cli/config.yaml`
   (`api_token:`). If a call returns 401/unauthorized, ask the user to set one;
   never print or write the token.
3. Discover schedule names; do not assume them:
   `rootly oncall schedules --format=json`
4. Who is on call right now, per placeholder:
   `rootly oncall who --schedule="<name>" --format=json`
5. If `who` does not separate primary from secondary, fall back to shifts,
   picking the shift whose window contains the current UTC time:
   `rootly oncall shifts --schedule="<name>" --days=1 --format=json`

The CLI is early preview and its JSON field names are not documented here:
read the real output of step 3/4 before parsing, and use `jq` over the JSON
rather than scraping the table. Re-check with `rootly oncall who --help` if a
flag errors.

## Slack IDs

Resolve IDs only for `send`, after the names are known. Load
`slack_search_users` (and `slack_read_user_profile` to confirm) via ToolSearch
in one call.

1. Search by the email in the Rootly output when it has one; otherwise by the
   full display name.
2. Accept a match only if exactly one user comes back and the profile email or
   full name equals Rootly's. Zero or several matches: keep plain `@Name` for
   that person, and name them in the closing line. Never pick the closest
   match: a wrong ID pings a stranger.
3. Deduplicate: one lookup per person even if they hold two slots.

Report the resolved IDs only as "resolved N of M mentions"; do not print IDs or
emails into the reply or any file.

## Delivery

Argument: `send`, `copy` or `show`. With no argument, or anything else, ask
which one (AskUserQuestion, three options) before delivering. Never pick a
default.

- `show`: print the rendered message in a code block in the reply.
- `copy`: pipe the rendered message to the clipboard, first of `pbcopy`,
  `wl-copy`, `xclip -selection clipboard` that `command -v` finds; if none,
  say so and fall back to `show`. Confirm in one line; do not echo it back.
- `send`: read the channel from
  `${XDG_CONFIG_HOME:-$HOME/.config}/oncall-rota/channel` (trim whitespace;
  if missing, stop and say the host has no `oncall_rota_channel` secret). Load
  the Slack connector's `slack_send_message` via ToolSearch, post the message
  (with resolved `<@U...>` mentions) to that channel, and report the permalink or message timestamp. Posting is
  public and cannot be undone: only the explicit `send` choice authorises it,
  and a failed post is reported, never retried blind.

Whatever the mode, finish with one line stating the source
(`rootly oncall who`, time queried in ISO8601 UTC, e.g. 2026-10-28T09:05:00Z)
and any slot that was empty or inferred. Never write the channel name or the
message into the repo.
