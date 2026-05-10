#!/usr/bin/env bats
# Tests for _session_map_lookup in hooks/scripts/lib/notify.sh.
#
# The lookup function reads $ITERM_SESSION_ID, validates daemon liveness
# (via lock-file PID), looks up the entry in the session map, validates
# the recorded shell PID, and echoes the TTY path on success.

load 'test_helper'

setup() {
	notify_session_map_setup
	# Make sure no stray fallback fires accidentally.
	unset ITERM_NOTIFS_TTY CLAUDE_TTY
	# shellcheck source=../hooks/scripts/lib/notify.sh
	source "${LIB_DIR}/notify.sh"
}

# ---------- happy path ----------

@test "session-map: hits when daemon alive, shell alive, uuid present" {
	export ITERM_SESSION_ID="w7t1p0:UUID-HAPPY"
	notify_session_map_add "UUID-HAPPY" "/dev/ttys011" "$$"
	run _session_map_lookup
	[ "$status" -eq 0 ]
	[ "$output" = "/dev/ttys011" ]
}

@test "session-map: matches full ITERM_SESSION_ID form too" {
	# In case iTerm2's API ever returns the full prefixed form, verify
	# the lookup tries that key in addition to the UUID-only form.
	export ITERM_SESSION_ID="w0t0p0:UUID-FULLFORM"
	notify_session_map_add "w0t0p0:UUID-FULLFORM" "/dev/ttys020" "$$"
	run _session_map_lookup
	[ "$status" -eq 0 ]
	[ "$output" = "/dev/ttys020" ]
}

# ---------- miss conditions ----------

@test "session-map: misses when ITERM_SESSION_ID is unset (remote shells)" {
	unset ITERM_SESSION_ID
	notify_session_map_add "UUID-X" "/dev/ttys011" "$$"
	run _session_map_lookup
	[ "$status" -ne 0 ]
}

@test "session-map: misses when map file does not exist" {
	export ITERM_SESSION_ID="w7t1p0:UUID-X"
	rm -f "$ITERM_NOTIFS_SESSION_MAP"
	run _session_map_lookup
	[ "$status" -ne 0 ]
}

@test "session-map: misses when uuid is not in the map" {
	export ITERM_SESSION_ID="w7t1p0:UUID-PRESENT"
	notify_session_map_add "UUID-DIFFERENT" "/dev/ttys011" "$$"
	run _session_map_lookup
	[ "$status" -ne 0 ]
}

# ---------- liveness checks ----------

@test "session-map: misses when daemon PID is dead" {
	# Lock points to a dead PID; map otherwise fine.
	local dead_pid
	dead_pid=$(notify_dead_pid)
	printf '%d\n' "$dead_pid" >"$ITERM_NOTIFS_LOCK"
	export ITERM_SESSION_ID="w7t1p0:UUID-X"
	notify_session_map_add "UUID-X" "/dev/ttys011" "$$"
	run _session_map_lookup
	[ "$status" -ne 0 ]
}

@test "session-map: misses when shell PID in map is dead (PTY recycling defense)" {
	# Daemon alive (default), but the recorded shell PID is dead.
	local dead_pid
	dead_pid=$(notify_dead_pid)
	export ITERM_SESSION_ID="w7t1p0:UUID-X"
	notify_session_map_add "UUID-X" "/dev/ttys011" "$dead_pid"
	run _session_map_lookup
	[ "$status" -ne 0 ]
}

@test "session-map: misses when lock file is empty" {
	: >"$ITERM_NOTIFS_LOCK"
	export ITERM_SESSION_ID="w7t1p0:UUID-X"
	notify_session_map_add "UUID-X" "/dev/ttys011" "$$"
	run _session_map_lookup
	[ "$status" -ne 0 ]
}

# ---------- env overrides + isolation ----------

@test "session-map: env overrides do not touch real ~/.claude paths" {
	# This test confirms the helper actually points at temp paths.
	[[ "$ITERM_NOTIFS_SESSION_MAP" != "$HOME"/.claude/* ]]
	[[ "$ITERM_NOTIFS_LOCK" != "$HOME"/.claude/* ]]
}

# ---------- UUID extraction ----------

@test "session-map: UUID extraction handles realistic ITERM_SESSION_ID format" {
	# Real format: <wXtYpZ>:<UUID>. Strip via ${var#*:} should yield
	# exactly the UUID portion.
	local realistic="w7t1p0:AFB95FE7-56C3-435A-A5E5-F55ED889854A"
	export ITERM_SESSION_ID="$realistic"
	notify_session_map_add "AFB95FE7-56C3-435A-A5E5-F55ED889854A" \
		"/dev/ttys042" "$$"
	run _session_map_lookup
	[ "$status" -eq 0 ]
	[ "$output" = "/dev/ttys042" ]
}

# ---------- _notify_target priority chain ----------

@test "priority: ITERM_NOTIFS_TTY beats session map" {
	export ITERM_NOTIFS_TTY="/tmp/test-override"
	export ITERM_SESSION_ID="w7t1p0:UUID-X"
	notify_session_map_add "UUID-X" "/dev/ttys011" "$$"
	run _notify_target
	[ "$status" -eq 0 ]
	[ "$output" = "/tmp/test-override" ]
}

@test "priority: session map beats CLAUDE_TTY" {
	export CLAUDE_TTY="/dev/ttys999"
	export ITERM_SESSION_ID="w7t1p0:UUID-X"
	notify_session_map_add "UUID-X" "/dev/ttys011" "$$"
	run _notify_target
	[ "$status" -eq 0 ]
	[ "$output" = "/dev/ttys011" ]
}

@test "priority: falls through to CLAUDE_TTY when map misses" {
	# No ITERM_SESSION_ID, no map entry — should land on CLAUDE_TTY.
	unset ITERM_SESSION_ID
	export CLAUDE_TTY="/dev/ttys999"
	run _notify_target
	[ "$status" -eq 0 ]
	[ "$output" = "/dev/ttys999" ]
}

@test "priority: falls through to /dev/tty when nothing matches" {
	unset ITERM_SESSION_ID
	# CLAUDE_TTY already unset by setup().
	run _notify_target
	[ "$status" -eq 0 ]
	[ "$output" = "/dev/tty" ]
}

@test "priority: dead daemon falls through to CLAUDE_TTY" {
	# Confirms that a stale map (daemon dead) doesn't trap the chain.
	local dead_pid
	dead_pid=$(notify_dead_pid)
	printf '%d\n' "$dead_pid" >"$ITERM_NOTIFS_LOCK"
	export ITERM_SESSION_ID="w7t1p0:UUID-X"
	notify_session_map_add "UUID-X" "/dev/ttys011" "$$"
	export CLAUDE_TTY="/dev/ttys999"
	run _notify_target
	[ "$status" -eq 0 ]
	[ "$output" = "/dev/ttys999" ]
}
