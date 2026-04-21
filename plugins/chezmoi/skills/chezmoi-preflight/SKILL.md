---
name: chezmoi-preflight
description: Use when about to edit or write any absolute path under `$HOME` whose first component starts with `.` (e.g. `~/.claude/settings.json`, `~/.config/*`, `~/.ssh/*`, `~/.zshrc`, `~/.gitconfig`), before performing the edit. Cheap gate — checks chezmoi management and hands off to chezmoi-expert if tracked, no-ops otherwise. Also use when an agent (including the built-in update-config skill) is about to write to `~/.claude/`.
---

# Chezmoi Preflight

Before editing a `~/.<anything>` file, check if chezmoi manages it. Editing the live file when the source is templated causes silent drift the user has to reconcile by hand.

## The Check

```bash
chezmoi source-path <absolute-path>
```

- **Exit 0 + non-empty output** → managed. The output IS the source path. **STOP. Invoke `chezmoi:chezmoi-expert` and edit the source instead.**
- **Non-zero exit, empty output, or `chezmoi: command not found`** → not managed (or no chezmoi). Proceed normally. Done.

Use `source-path`, not `managed` — it's one targeted lookup vs. listing everything.

## Scope

Applies to absolute paths under `$HOME` whose first component starts with `.`:
`~/.claude/*`, `~/.config/*`, `~/.ssh/*`, `~/.zshrc`, `~/.gitconfig`, `~/.p10k.zsh`, etc.

Does NOT apply to:
- Files inside a project directory
- Files outside `$HOME`
- Files already under `~/.local/share/chezmoi/` (that IS the source tree)

## Common Mistakes

- **Skipping the check** because "I know this isn't managed." Run it. Sub-second.
- **Relative paths.** Resolve to absolute first.
- **Hotfixing the live file "just this once."** It will be overwritten on the next `chezmoi apply`.
- **Relying on the `chezmoi-guard` hook instead.** The hook is a backstop. This skill catches the case before the write tool even fires, and gives a cleaner handoff to chezmoi-expert.
