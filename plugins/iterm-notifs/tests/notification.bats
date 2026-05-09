#!/usr/bin/env bats
# Tests for hooks/scripts/notification.sh - the Notification hook entry point.
#
# These are integration tests: we shell out to bash with the real script,
# real libs, real jq, real base64. Stdin is JSON, stdout is captured.

load 'test_helper'

setup() {
	export CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT"
	TEST_TMP="$(mktemp -d "${TMPDIR:-/tmp}/iterm-notifs-tests.XXXXXX")"
	export TEST_TMP
	# Don't let global git config leak in.
	export GIT_CONFIG_GLOBAL=/dev/null
	export GIT_CONFIG_SYSTEM=/dev/null
}

teardown() {
	if [[ -n "${TEST_TMP:-}" && -d "$TEST_TMP" ]]; then
		rm -rf "$TEST_TMP"
	fi
}

# Helper: run the notification script with given JSON stdin.
# Sets $output (from captured TTY file) and $status as bats expects.
run_notification() {
	local json="$1"
	notify_tty_setup
	run env ITERM_NOTIFS_TTY="$ITERM_NOTIFS_TTY" \
		bash -c "printf '%s' \"\$1\" | bash '${SCRIPTS_DIR}/notification.sh'" _ "$json"
	# notify.sh writes escape sequences to ITERM_NOTIFS_TTY, not stdout.
	# Override $output with the captured TTY contents so existing
	# assertions on $output keep working.
	output=$(notify_tty_read)
}

# ---------- idle_prompt ----------

@test "idle_prompt: emits banner + bounce + waiting markers in order" {
	mkdir -p "${TEST_TMP}/myproj"
	json=$(jq -nc --arg cwd "${TEST_TMP}/myproj" \
		'{notification_type: "idle_prompt", cwd: $cwd}')

	run_notification "$json"
	[ "$status" -eq 0 ]

	# Banner present with expected text.
	[[ "$output" == *"${ESC}]9;Claude waiting in myproj${BEL}"* ]]
	# Bounce present.
	[[ "$output" == *"${ESC}]1337;RequestAttention=1${BEL}"* ]]
	# Both waiting markers present.
	has_setuservar "$output" "claudeWaitingProject"
	has_setuservar "$output" "claudeWaitingSince"

	# Order: banner < bounce < project < since.
	banner_pos=$(index_of "$output" "${ESC}]9;")
	bounce_pos=$(index_of "$output" "RequestAttention=1")
	proj_pos=$(index_of "$output" "SetUserVar=claudeWaitingProject=")
	since_pos=$(index_of "$output" "SetUserVar=claudeWaitingSince=")
	[ "$banner_pos" -gt 0 ] && [ "$banner_pos" -lt "$bounce_pos" ]
	[ "$bounce_pos" -lt "$proj_pos" ]
	[ "$proj_pos" -lt "$since_pos" ]
}

@test "idle_prompt: project name is base64-encoded from cwd basename" {
	mkdir -p "${TEST_TMP}/derek-cool-thing"
	json=$(jq -nc --arg cwd "${TEST_TMP}/derek-cool-thing" \
		'{notification_type: "idle_prompt", cwd: $cwd}')

	run_notification "$json"
	[ "$status" -eq 0 ]

	b64=$(extract_setuservar_value "$output" "claudeWaitingProject")
	decoded=$(decode_setuservar "$b64")
	[ "$decoded" = "derek-cool-thing" ]
}

@test "idle_prompt: project name resolves to git toplevel when cwd is inside a repo" {
	repo="${TEST_TMP}/repo-toplevel"
	mkdir -p "${repo}/deep/nested"
	git -C "$repo" init -q

	json=$(jq -nc --arg cwd "${repo}/deep/nested" \
		'{notification_type: "idle_prompt", cwd: $cwd}')

	run_notification "$json"
	[ "$status" -eq 0 ]
	[[ "$output" == *"${ESC}]9;Claude waiting in repo-toplevel${BEL}"* ]]

	b64=$(extract_setuservar_value "$output" "claudeWaitingProject")
	decoded=$(decode_setuservar "$b64")
	[ "$decoded" = "repo-toplevel" ]
}

# ---------- permission_prompt ----------

@test "permission_prompt: emits banner with permission text + bounce + markers" {
	mkdir -p "${TEST_TMP}/permproj"
	json=$(jq -nc --arg cwd "${TEST_TMP}/permproj" \
		'{notification_type: "permission_prompt", cwd: $cwd}')

	run_notification "$json"
	[ "$status" -eq 0 ]
	[[ "$output" == *"${ESC}]9;Claude needs permission in permproj${BEL}"* ]]
	[[ "$output" == *"${ESC}]1337;RequestAttention=1${BEL}"* ]]
	has_setuservar "$output" "claudeWaitingProject"
	has_setuservar "$output" "claudeWaitingSince"
}

@test "permission_prompt: does not use idle_prompt banner text" {
	mkdir -p "${TEST_TMP}/permproj"
	json=$(jq -nc --arg cwd "${TEST_TMP}/permproj" \
		'{notification_type: "permission_prompt", cwd: $cwd}')

	run_notification "$json"
	[ "$status" -eq 0 ]
	# Should NOT contain the idle banner.
	[[ "$output" != *"Claude waiting in"* ]]
}

# ---------- silent notification types ----------

@test "auth_success: silent (no escape sequences emitted)" {
	mkdir -p "${TEST_TMP}/anyproj"
	json=$(jq -nc --arg cwd "${TEST_TMP}/anyproj" \
		'{notification_type: "auth_success", cwd: $cwd}')

	run_notification "$json"
	[ "$status" -eq 0 ]
	[ -z "$output" ]
}

@test "elicitation_dialog: silent" {
	mkdir -p "${TEST_TMP}/anyproj"
	json=$(jq -nc --arg cwd "${TEST_TMP}/anyproj" \
		'{notification_type: "elicitation_dialog", cwd: $cwd}')

	run_notification "$json"
	[ "$status" -eq 0 ]
	[ -z "$output" ]
}

@test "elicitation_complete: silent" {
	mkdir -p "${TEST_TMP}/anyproj"
	json=$(jq -nc --arg cwd "${TEST_TMP}/anyproj" \
		'{notification_type: "elicitation_complete", cwd: $cwd}')

	run_notification "$json"
	[ "$status" -eq 0 ]
	[ -z "$output" ]
}

@test "elicitation_response: silent" {
	mkdir -p "${TEST_TMP}/anyproj"
	json=$(jq -nc --arg cwd "${TEST_TMP}/anyproj" \
		'{notification_type: "elicitation_response", cwd: $cwd}')

	run_notification "$json"
	[ "$status" -eq 0 ]
	[ -z "$output" ]
}

@test "unknown_future_type: silent" {
	mkdir -p "${TEST_TMP}/anyproj"
	json=$(jq -nc --arg cwd "${TEST_TMP}/anyproj" \
		'{notification_type: "some_future_thing", cwd: $cwd}')

	run_notification "$json"
	[ "$status" -eq 0 ]
	[ -z "$output" ]
}

# ---------- missing/empty fields ----------

@test "missing notification_type: silent" {
	mkdir -p "${TEST_TMP}/anyproj"
	json=$(jq -nc --arg cwd "${TEST_TMP}/anyproj" '{cwd: $cwd}')

	run_notification "$json"
	[ "$status" -eq 0 ]
	[ -z "$output" ]
}

@test "empty notification_type: silent" {
	mkdir -p "${TEST_TMP}/anyproj"
	json=$(jq -nc --arg cwd "${TEST_TMP}/anyproj" \
		'{notification_type: "", cwd: $cwd}')

	run_notification "$json"
	[ "$status" -eq 0 ]
	[ -z "$output" ]
}

@test "missing cwd on idle_prompt: falls back to PWD basename" {
	# Run with an explicit PWD by spawning bash in a known dir.
	mkdir -p "${TEST_TMP}/fallback-dir"
	json='{"notification_type":"idle_prompt"}'

	notify_tty_setup
	# Spawn bash with cwd = our fallback-dir, no cwd in JSON.
	(cd "${TEST_TMP}/fallback-dir" && \
		ITERM_NOTIFS_TTY="$ITERM_NOTIFS_TTY" \
		printf '%s' "$json" | \
		ITERM_NOTIFS_TTY="$ITERM_NOTIFS_TTY" bash "${SCRIPTS_DIR}/notification.sh")
	rc=$?
	[ "$rc" -eq 0 ]
	output=$(notify_tty_read)
	[[ "$output" == *"${ESC}]9;Claude waiting in fallback-dir${BEL}"* ]]
}

# ---------- extra fields are ignored ----------

@test "extra fields in JSON are silently ignored" {
	mkdir -p "${TEST_TMP}/myproj"
	json=$(jq -nc --arg cwd "${TEST_TMP}/myproj" \
		'{notification_type: "idle_prompt",
		  cwd: $cwd,
		  message: "extra info",
		  some_future_field: {nested: true}}')

	run_notification "$json"
	[ "$status" -eq 0 ]
	[[ "$output" == *"${ESC}]9;Claude waiting in myproj${BEL}"* ]]
}

# ---------- exit code discipline ----------

@test "always exits 0 on valid input" {
	mkdir -p "${TEST_TMP}/myproj"
	json=$(jq -nc --arg cwd "${TEST_TMP}/myproj" \
		'{notification_type: "idle_prompt", cwd: $cwd}')

	run_notification "$json"
	[ "$status" -eq 0 ]
}

@test "always exits 0 for silent notification types" {
	json='{"notification_type":"auth_success","cwd":"/tmp"}'
	run_notification "$json"
	[ "$status" -eq 0 ]
}

@test "malformed JSON stdin: still exits 0 (hook resilience)" {
	# Contract: failures inside the script must not break the hook chain.
	# This currently fails because of `set -euo pipefail` + jq returning
	# non-zero on bad input. See FINDINGS in the test report.
	run_notification "this is not json {{{"
	[ "$status" -eq 0 ]
}
