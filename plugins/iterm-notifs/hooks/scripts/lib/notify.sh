#!/bin/bash
# notify.sh - notification primitives via iTerm2 escape sequences.
#
# Sourced by hook scripts. All functions emit escape sequences only.
# Audio (sound, voice) is dispatched by the iTerm2 AutoLaunch Python
# script on the local Mac, which watches for transitions on
# user.claudeWaitingSince across all sessions. This keeps hooks
# identical on local Mac and on remote SSH+tmux sessions.
#
# IMPORTANT: all emits target /dev/tty rather than stdout, because
# Claude Code captures hook stdout for its own use. Writing to /dev/tty
# bypasses that capture and reaches the actual terminal that iTerm2
# controls. Without this, the OSC escapes get eaten and never affect
# the iTerm2 session.
#
# Tests can override the target by setting ITERM_NOTIFS_TTY to a file
# path; primitives will write there instead.

_notify_target() {
	printf '%s' "${ITERM_NOTIFS_TTY:-/dev/tty}"
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
