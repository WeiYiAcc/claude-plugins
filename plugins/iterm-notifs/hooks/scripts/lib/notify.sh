#!/bin/bash
# notify.sh - notification primitives via iTerm2 escape sequences.
#
# Sourced by hook scripts. All functions emit escape sequences only.
# Audio (sound, voice) is dispatched by the iTerm2 AutoLaunch Python
# script on the local Mac, which watches for transitions on
# user.claudeWaitingSince across all sessions. This keeps hooks
# identical on local Mac and on remote SSH+tmux sessions.
#
# IMPORTANT: emits target the user's controlling TTY rather than stdout,
# because Claude Code captures hook stdout for its own use. Without this,
# the OSC escapes get eaten and never affect the iTerm2 session.
#
# /dev/tty doesn't work because hook subprocesses don't inherit a
# controlling terminal from Claude Code. We fall back through env vars
# the user's shell may have exported. See README for setup details.

# Look up this session's TTY in the daemon-maintained session map.
# The map is written by the iTerm2 AutoLaunch script (claude_cycle.py)
# at ~/.claude/run/iterm-notifs/sessions.txt with one line per session
# in the form "<session_id>=<tty>:<pid>". The hook reads its inherited
# $ITERM_SESSION_ID, looks up the entry, and validates two liveness
# invariants before trusting it:
#   1) Daemon liveness: the lock file's PID must still be a live process.
#      If the daemon is dead, the map could be arbitrarily stale.
#   2) Shell PID liveness: the recorded shell PID must still be a live
#      process. If it's dead, macOS may have recycled the PTY device
#      number to an unrelated terminal and writing there would land OSC
#      bytes in the wrong place.
#
# Echoes the TTY path on success; returns non-zero on miss/failure so
# _notify_target falls through to the next mechanism.
_session_map_lookup() {
	local map="${ITERM_NOTIFS_SESSION_MAP:-$HOME/.claude/run/iterm-notifs/sessions.txt}"
	local lock="${ITERM_NOTIFS_LOCK:-$HOME/.claude/run/iterm2-claude-cycle.lock}"
	local sid="${ITERM_SESSION_ID:-}"
	[[ -z "$sid" || ! -r "$map" ]] && return 1

	# Daemon liveness check. The lock file holds the daemon's PID on
	# line 1 (written by acquire_singleton_lock in claude_cycle.py).
	local daemon_pid
	daemon_pid=$(head -1 "$lock" 2>/dev/null)
	[[ -z "$daemon_pid" ]] && return 1
	kill -0 "$daemon_pid" 2>/dev/null || return 1

	# Look up the entry. Try the full ITERM_SESSION_ID first, then
	# fall back to the UUID-only form (post-colon portion). iTerm2's
	# Python API returns session_id as just the UUID, but be robust
	# in case that changes.
	local entry uuid="${sid#*:}"
	entry=$(grep -F "${sid}=" "$map" 2>/dev/null | head -1)
	[[ -z "$entry" ]] && entry=$(grep -F "${uuid}=" "$map" 2>/dev/null | head -1)
	[[ -z "$entry" ]] && return 1

	# Format: <key>=<tty>:<pid>
	entry="${entry#*=}"
	local tty="${entry%:*}"
	local pid="${entry##*:}"
	[[ -z "$tty" || -z "$pid" ]] && return 1

	# PTY-recycling defense. If the recorded shell process is gone,
	# macOS may have reassigned that /dev/ttysXXX to a different
	# terminal and writing there would target the wrong session.
	kill -0 "$pid" 2>/dev/null || return 1

	printf '%s' "$tty"
}

_notify_target() {
	# Test override (set by bats tests).
	if [[ -n "${ITERM_NOTIFS_TTY:-}" ]]; then
		printf '%s' "$ITERM_NOTIFS_TTY"
		return
	fi
	# Zero-config local-Mac path: daemon-maintained session map.
	local mapped
	if mapped=$(_session_map_lookup) && [[ -n "$mapped" ]]; then
		printf '%s' "$mapped"
		return
	fi
	# Manual fallback (required for remote SSH+tmux sessions where the
	# daemon and map file are unreachable).
	if [[ -n "${CLAUDE_TTY:-}" ]]; then
		printf '%s' "$CLAUDE_TTY"
		return
	fi
	# Last resort. Fails when hook has no controlling terminal (the
	# common case in Claude Code) but works in interactive shells.
	printf '/dev/tty'
}

# OSC 9: post a banner notification with custom body text.
# In tmux, allow-passthrough on forwards this to the outer iTerm2.
notify_banner() {
	local message="$1"
	printf '\033]9;%s\007' "$message" >>"$(_notify_target)" 2>/dev/null || true
}

# OSC 1337 RequestAttention: bounce dock icon. DND-immune.
notify_bounce() {
	printf '\033]1337;RequestAttention=1\007' >>"$(_notify_target)" 2>/dev/null || true
}

# Mark this session as waiting on the user. Sets two iTerm2 user
# variables. Project name is set FIRST; claudeWaitingSince LAST -
# the latter is the trigger the Python AutoLaunch watches, so the
# project name must already be present by the time it reacts.
#
# Per the OSC 1337 SetUserVar spec, values are base64-encoded.
notify_set_waiting() {
	local project="$1"
	local project_b64 timestamp_b64 target
	project_b64=$(printf '%s' "$project" | base64)
	timestamp_b64=$(printf '%s' "$(date +%s)" | base64)
	target=$(_notify_target)
	{
		printf '\033]1337;SetUserVar=claudeWaitingProject=%s\007' "$project_b64"
		printf '\033]1337;SetUserVar=claudeWaitingSince=%s\007' "$timestamp_b64"
	} >>"$target" 2>/dev/null || true
}

# Clear the waiting markers when the user resumes (UserPromptSubmit).
notify_clear_waiting() {
	local target
	target=$(_notify_target)
	{
		printf '\033]1337;SetUserVar=claudeWaitingSince=\007'
		printf '\033]1337;SetUserVar=claudeWaitingProject=\007'
	} >>"$target" 2>/dev/null || true
}
