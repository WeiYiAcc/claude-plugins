# Chezmoi Plugin for Claude Code

Prevents the classic AI assistant mistake of editing dotfiles directly instead of through chezmoi. Also provides comprehensive chezmoi expertise.

## Features

### Chezmoi Guard (PreToolUse Hook)

Automatically intercepts `Edit` and `Write` tool calls targeting files under `$HOME`:

- **Managed files**: Warns Claude that the file is managed by chezmoi, shows the source file path, and asks Claude to confirm with the user before proceeding
- **Unmanaged dotfiles/configs**: Suggests `chezmoi add` if the file looks like a dotfile or config
- **Other files**: Passes through silently

The guard does NOT block edits (exit 0). It warns strongly and instructs Claude to ask the user for confirmation.

### Chezmoi Preflight (Skill)

Lightweight gate skill that activates whenever Claude is about to edit a file under `~/.<something>` (e.g. `~/.claude/settings.json`, `~/.zshrc`, `~/.gitconfig`). Runs a single `chezmoi source-path` check — if the file is managed, hands off to `chezmoi-expert`; otherwise exits silently. Catches the case earlier than the PreToolUse hook, before the write tool is even invoked.

### Chezmoi Expert (Skill)

Comprehensive chezmoi knowledge that activates when discussing dotfile management:

- Correct diff direction interpretation (the #1 source of mistakes)
- File naming conventions and cross-platform scripting
- Template syntax and machine-specific configurations
- Sandbox considerations for Claude Code
- Helper scripts for plist diffing and drift detection
- Troubleshooting, common scenarios, and encryption guidance

## Installation

This plugin is designed to be installed as a user-global plugin:

```bash
# Test locally
cc --plugin-dir ~/.claude/plugins/chezmoi

# Or register in Claude Code settings
```

## Prerequisites

- chezmoi installed and initialized
- `jq` available (for hook JSON parsing)
- macOS or Linux

## Helper Scripts

### diff-plist.sh

Compare binary plist files between chezmoi source and target:

```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/diff-plist.sh Library/Preferences/com.example.App.plist
```

### reconcile-status.sh

Detect all chezmoi drift, including silent template drift:

```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/reconcile-status.sh [--verbose]
```

## Plugin Structure

```
chezmoi/
├── .claude-plugin/
│   └── plugin.json
├── hooks/
│   ├── hooks.json
│   └── scripts/
│       └── chezmoi-guard.sh
├── scripts/
│   ├── diff-plist.sh
│   └── reconcile-status.sh
├── skills/
│   ├── chezmoi-preflight/
│   │   └── SKILL.md
│   └── chezmoi-expert/
│       ├── SKILL.md
│       └── references/
│           ├── commands.md
│           ├── common-scenarios.md
│           ├── encryption.md
│           ├── templates-and-workflows.md
│           └── troubleshooting.md
└── README.md
```

## Replaces

This plugin subsumes and replaces the project-scoped skill at `~/.local/share/chezmoi/.claude/skills/chezmoi/`. The old skill can be removed after this plugin is installed.
