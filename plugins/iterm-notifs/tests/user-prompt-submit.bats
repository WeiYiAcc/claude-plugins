#!/usr/bin/env bats
# Tests for hooks/scripts/user-prompt-submit.sh.

load 'test_helper'

setup() {
	export CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT"
}

run_ups() {
	local stdin_payload="$1"
	notify_tty_setup
	run env ITERM_NOTIFS_TTY="$ITERM_NOTIFS_TTY" \
		bash -c "printf '%s' \"\$1\" | bash '${SCRIPTS_DIR}/user-prompt-submit.sh'" _ "$stdin_payload"
	output=$(notify_tty_read)
}

@test "user-prompt-submit: emits both clear-waiting SetUserVars" {
	run_ups '{"any":"json","is":"fine"}'
	[ "$status" -eq 0 ]
	[[ "$output" == *"${ESC}]1337;SetUserVar=claudeWaitingSince=${BEL}"* ]]
	[[ "$output" == *"${ESC}]1337;SetUserVar=claudeWaitingProject=${BEL}"* ]]
}

@test "user-prompt-submit: cleared values are empty (not just 'present')" {
	run_ups '{}'
	[ "$status" -eq 0 ]
	# Use the helper's extractor: empty value should round-trip as empty.
	since_b64=$(extract_setuservar_value "$output" "claudeWaitingSince")
	proj_b64=$(extract_setuservar_value "$output" "claudeWaitingProject")
	[ -z "$since_b64" ]
	[ -z "$proj_b64" ]
}

@test "user-prompt-submit: emits exactly two OSC sequences (no extras)" {
	run_ups '{"hook_event_name":"UserPromptSubmit"}'
	[ "$status" -eq 0 ]
	bel_count=$(printf '%s' "$output" | tr -cd "${BEL}" | wc -c | tr -d ' ')
	[ "$bel_count" -eq 2 ]
}

@test "user-prompt-submit: drains stdin without choking on large payload" {
	# Generate a chunky payload to make sure `cat >/dev/null` actually drains.
	big=$(printf 'x%.0s' {1..10000})
	run_ups "{\"prompt\":\"$big\"}"
	[ "$status" -eq 0 ]
	# Still emits the two clear-waiting sequences regardless of input size.
	[[ "$output" == *"${ESC}]1337;SetUserVar=claudeWaitingSince=${BEL}"* ]]
	[[ "$output" == *"${ESC}]1337;SetUserVar=claudeWaitingProject=${BEL}"* ]]
}

@test "user-prompt-submit: works with empty stdin" {
	run_ups ""
	[ "$status" -eq 0 ]
	[[ "$output" == *"${ESC}]1337;SetUserVar=claudeWaitingSince=${BEL}"* ]]
	[[ "$output" == *"${ESC}]1337;SetUserVar=claudeWaitingProject=${BEL}"* ]]
}

@test "user-prompt-submit: exits 0" {
	run_ups '{"prompt":"hi"}'
	[ "$status" -eq 0 ]
}
