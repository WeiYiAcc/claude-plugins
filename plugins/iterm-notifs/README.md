# iterm-notifs

iTerm2-native Claude Code notifications for macOS.

When Claude waits for your input, this plugin posts a custom-text iTerm2
banner with the project name, bounces the dock, and marks the session as
waiting via iTerm2 user variables. A companion AutoLaunch Python script
(deployed separately via your dotfiles, not part of this plugin) watches
those variables to play a custom sound, speak the project name aloud,
and bind a hotkey to "jump to the longest-waiting Claude" across all
your iTerm2 sessions - including remote SSH+tmux sessions, since the
escape sequences pass through tmux.

## Why this plugin exists

Claude Code's built-in iTerm2 notifications (via OSC 9) post a banner
whose body is whatever the terminal happens to set as the title - often
just the tab name. There's no project context, and the sound is locked
to whatever macOS plays for iTerm2 in general.

This plugin replaces that with hook-driven banners that include the
project name and route by event type, plus a side-channel state
mechanism (iTerm2 session user variables) that a small Python AutoLaunch
script can watch to provide cycling and richer audio UX.

## What the hooks do

| Event | What fires |
|---|---|
| `Notification` with `notification_type=idle_prompt` | OSC 9 banner "Claude waiting in $project", dock bounce, set `user.claudeWaitingProject` and `user.claudeWaitingSince` |
| `Notification` with `notification_type=permission_prompt` | OSC 9 banner "Claude needs permission in $project", dock bounce, set the same waiting vars |
| `Notification` with other types | Silent (auth_success, elicitation_*, etc.) |
| `UserPromptSubmit` | Clear `user.claudeWaitingSince` and `user.claudeWaitingProject` |

Hooks deliberately do NOT play sounds or call `say` directly. That work
is handled by the AutoLaunch script on the local Mac, which watches the
iTerm2 user variables uniformly across local and remote-SSH sessions
and dispatches audio centrally.

## iTerm2 session user variable contract

| Variable | Meaning | Set by | Cleared by |
|---|---|---|---|
| `user.claudeWaitingSince` | Unix timestamp when Claude started waiting (empty = not waiting). The trigger watched by external tooling. | `notification.sh` on idle/permission prompt | `user-prompt-submit.sh` |
| `user.claudeWaitingProject` | Project name (basename of git toplevel or cwd). | `notification.sh` (set FIRST, before claudeWaitingSince) | `user-prompt-submit.sh` |

External tooling can `printf '\033]1337;SetUserVar=...'` to read the
plain-text values via the iTerm2 Python API
(`session.async_get_variable("user.claudeWaitingSince")`).

## Companion AutoLaunch script

This plugin emits state but doesn't dispatch audio or provide cycling.
Pair it with an iTerm2 AutoLaunch Python script that:

- Subscribes to `user.claudeWaitingSince` changes via `iterm2.VariableMonitor`
  across all sessions; on transition empty → timestamp, plays a sound and
  speaks the project name.
- Registers `cycle_waiting()` to cycle through waiting sessions
  (oldest-first, wraps from the current foreground session) and
  `clear_waiting()` to manually clear stuck markers on the current
  session. Bind to hotkeys via iTerm2 Settings → Keys → Invoke Script
  Function.

A reference implementation lives in Derek's chezmoi dotfiles at
`~/Library/Application Support/iTerm2/Scripts/AutoLaunch/claude_cycle.py`.

## Manual setup (one-time per Mac)

1. **Re-enable iTerm2 OS-level notifications**: System Settings →
   Notifications → iTerm2 → Allow Notifications: ON.

2. **Allowlist iTerm2 in your Focus modes** so banners break through DND:
   System Settings → Focus → [each mode] → Apps & People → Allow iTerm2.

3. **Bind a hotkey for cycling**: iTerm2 → Settings → Keys → Key Bindings
   → `+` → record shortcut (e.g. `Cmd+Shift+J`) → Action: "Invoke Script
   Function" → `jump_to_oldest_waiting()`.

## Why this is iTerm2-only

The whole design rides on iTerm2-specific escape sequences (OSC 1337
SetUserVar, OSC 1337 RequestAttention, OSC 9 with custom body) and on
the iTerm2 Python API for cycling. Other terminals don't have an
equivalent scoped-variable + scriptable-from-Python combination. If
you're not on iTerm2 + macOS, this plugin won't be useful.

## License

MIT - see `LICENSE`.
