# Reconcile Chezmoi Status

Detect and resolve ALL chezmoi drift, including silent template drift that `chezmoi status` misses.

Usage:
- `/chezmoi:reconcile` - detect and interactively resolve all drift

---

First, activate the chezmoi skill for full context:

/chezmoi

Then follow this workflow precisely:

## Step 1: Run the reconciliation detection script

Run the reconcile-status.sh script to detect both visible and silent drift:

```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/reconcile-status.sh --verbose
```

If the exit code is 0 (no drift), tell the user everything is clean and stop.

## Step 2: For each drifted file, resolve interactively

For EACH file with drift (visible or silent), do the following in order.

**Handle script entries (R) separately from file entries (M/A/D):**

### Scripts (R entries) -- WILL EXECUTE

Scripts (`run_once_*`, `run_onchange_*`) will **execute code**, not just modify files. They may:
- Take a long time (e.g., `brew bundle`)
- Require interactive input (`read -p`) which cannot work in Claude Code's non-interactive shell
- Have side effects (killing Dock/Finder, installing packages)

For R entries:
1. Show the script source so the user can evaluate what it does: `chezmoi cat <script-path>` or read the source file directly
2. Ask the user if they want to:
   - **run manually**: User runs the script in their own terminal (recommended for interactive scripts)
   - **apply**: Let chezmoi execute it (only if the script is non-interactive and safe)
   - **skip**: Leave it for now
   - **clear state**: Delete the entry state so it re-runs next time (`chezmoi state delete`)

### Files (M/A/D entries)

The reconcile-status.sh script tags each drifted file as `[TEMPLATE]` or plain. Use this tag to determine the correct resolution options.

### 2a. Show the diff BEFORE asking the user

Always show the diff first so the user can make an informed decision.

**Reading the diff correctly:** See the chezmoi skill's "WARNING: Reading
`chezmoi diff` output correctly" section for the full reference. The short
version: **minus = on disk, plus = from template.**

- `-` lines = what's currently **on disk** (the live/target file)
- `+` lines = what chezmoi would **write** (rendered from source/template)

**Mandatory self-check BEFORE presenting findings to the user:**
After reading the diff, verify your interpretation by re-reading each `-` and
`+` line against the rule: minus=disk, plus=template. State your interpretation
with explicit citations like "line X shows `-foo`, meaning foo is ON DISK" or
"line Y shows `+bar`, meaning bar is FROM THE TEMPLATE." If you catch yourself
saying "the live file has X" where X appears on a `+` line, you have it
backwards -- correct it before continuing.

**When describing drift to the user:** Always cite the specific diff line and
its sign (`-` or `+`) to anchor each claim. For example: "The diff shows
`-  old_setting = true` (on disk) and `+  new_setting = true` (from template),
meaning the live file has `old_setting` but the template wants `new_setting`."

For **plist files** (`.plist`), use the plist diff helper for human-readable output:
```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/diff-plist.sh <relative-path>
```

For other files with **visible drift**:
```bash
chezmoi diff <target-path>
```

For **silent template drift** (where chezmoi diff shows nothing):
```bash
# Show what the template renders vs what's on disk
chezmoi cat <target-path> > $TMPDIR/chezmoi-rendered.txt
diff <target-path> $TMPDIR/chezmoi-rendered.txt || true
```

### 2b. Ask the user what to do

After showing the diff, use AskUserQuestion to present the appropriate options for EACH file.

**For PLAIN (non-template) files:**

- **re-add**: Accept the target file's current state as the new source of truth (`chezmoi re-add <path>`)
- **apply**: Overwrite the target with the source (`chezmoi apply --force <path>`)
- **skip**: Leave this file alone for now
- **show more**: Show additional context (source path, entry state hashes, etc.)

**For TEMPLATE files** (tagged `[TEMPLATE]` in script output):

Do NOT offer `re-add` as an option. Depending on the chezmoi version, `chezmoi re-add` on a template either replaces the `.tmpl` source with the literal target content (stripping all Go template directives like `{{ if }}` / `{{ .data }}`) or silently refuses with no stdout, no stderr, and exit 0. Either way it is the wrong tool for templates.

Instead, offer:
- **edit template**: Open the `.tmpl` source file so the user (or you) can manually integrate the live changes into the template while preserving template logic. Show both the template source and the diff to make this easy.
- **apply**: Overwrite the target with the rendered source template, discarding the live changes (`chezmoi apply --force <path>`)
- **skip**: Leave this file alone for now
- **show template source**: Read and display the `.tmpl` source file so the user can see the template directives

When the user chooses "edit template", read the `.tmpl` source file and the diff, then propose specific edits that incorporate the live changes while preserving template directives. Ask the user to confirm before writing.

### 2c. Execute the chosen action

Run the appropriate chezmoi command. After each action, briefly confirm it succeeded.

## Step 3: Verify clean state

After resolving all files, run the detection script again:

```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/reconcile-status.sh
```

If drift remains, loop back to Step 2 for any remaining files.
If clean, proceed to Step 4.

## Step 4: Commit source repo changes

After reconciliation, the chezmoi source repo often has uncommitted changes from `re-add` operations or source edits.

1. Run `git status` in the source repo to check for uncommitted changes
2. If there are changes, group them into logical commits (e.g., separate "re-add plist changes" from "update zshrc")
3. Commit with descriptive messages following conventional commit style (e.g., `fix(macos): re-add updated dock plist`)
4. Do NOT push unless the user explicitly asks

If there are no uncommitted changes, confirm reconciliation is fully complete.

## Important notes

- **Sandbox**: ALL chezmoi commands in this workflow should use `dangerouslyDisableSandbox: true` to avoid environment variable contamination. The sandbox overrides `TMPDIR` (and potentially other env vars), which causes templates using `{{ env "TMPDIR" }}` to render with sandbox paths instead of real system paths. This creates false positive drift that does not exist outside the sandbox. Both read commands (`chezmoi diff`, `chezmoi cat`, `chezmoi status`) and write commands (`chezmoi apply`, `chezmoi re-add`) are affected.
- **Plist files**: Always run the plist diff helper (`diff-plist.sh`) and show the output BEFORE asking the user what to do. The user needs to see what changed to make an informed decision.
- For `.tmpl` source files, NEVER offer `chezmoi re-add` as an option. Depending on chezmoi version, it either strips template directives or silently no-ops with no error signal. The script tags these files as `[TEMPLATE]` -- use the template-specific resolution options in Step 2b instead.
- **Silent no-op detection (defense in depth):** if you ever do run `chezmoi re-add <file>` and it exits 0 with no stdout, no stderr, an unchanged `chezmoi diff`, AND a clean `git status` in the source repo, the file is almost certainly template-managed and chezmoi silently refused the operation. Confirm with `chezmoi source-path <target>` -- if it ends in `.tmpl`, switch to the template-edit workflow. Do not retry `re-add` and do not report success.
- Never run `chezmoi apply` without `--force` in this workflow -- the non-interactive shell will hang on the TTY prompt.
- If the user says "re-add all" or "apply all", batch the operations but still show a summary of what will change.
