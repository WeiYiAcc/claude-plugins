#!/usr/bin/env bats
# Tests for hooks/scripts/lib/notify.sh - pure escape-sequence emitters.

load 'test_helper'

setup() {
	notify_tty_setup
	# shellcheck source=../hooks/scripts/lib/notify.sh
	source "${LIB_DIR}/notify.sh"
}

# ---------- notify_banner ----------

@test "notify_banner: emits exact OSC 9 sequence with simple message" {
	notify_banner "hello"
	output=$(notify_tty_read)
	[ "$output" = "${ESC}]9;hello${BEL}" ]
}

@test "notify_banner: preserves spaces and punctuation in message" {
	notify_banner "Claude waiting in my-project (idle!)"
	output=$(notify_tty_read)
	[ "$output" = "${ESC}]9;Claude waiting in my-project (idle!)${BEL}" ]
}

@test "notify_banner: handles empty message" {
	notify_banner ""
	output=$(notify_tty_read)
	[ "$output" = "${ESC}]9;${BEL}" ]
}

@test "notify_banner: passes through non-ASCII UTF-8" {
	notify_banner "Claude waiting in projet-café"
	output=$(notify_tty_read)
	[ "$output" = "${ESC}]9;Claude waiting in projet-café${BEL}" ]
}

# ---------- notify_bounce ----------

@test "notify_bounce: emits exact OSC 1337 RequestAttention sequence" {
	notify_bounce
	output=$(notify_tty_read)
	[ "$output" = "${ESC}]1337;RequestAttention=1${BEL}" ]
}

@test "notify_bounce: ignores any arguments (no failure, same output)" {
	notify_bounce ignored args here
	output=$(notify_tty_read)
	[ "$output" = "${ESC}]1337;RequestAttention=1${BEL}" ]
}

# ---------- notify_set_waiting ----------

@test "notify_set_waiting: emits exactly two SetUserVar sequences" {
	notify_set_waiting "myproj"
	output=$(notify_tty_read)
	# Count BEL terminators - one per OSC sequence.
	bel_count=$(printf '%s' "$output" | tr -cd "${BEL}" | wc -c | tr -d ' ')
	[ "$bel_count" -eq 2 ]
}

@test "notify_set_waiting: emits claudeWaitingProject before claudeWaitingSince" {
	notify_set_waiting "myproj"
	output=$(notify_tty_read)
	proj_pos=$(index_of "$output" "SetUserVar=claudeWaitingProject=")
	since_pos=$(index_of "$output" "SetUserVar=claudeWaitingSince=")
	[ "$proj_pos" -gt 0 ]
	[ "$since_pos" -gt 0 ]
	[ "$proj_pos" -lt "$since_pos" ]
}

@test "notify_set_waiting: project value decodes to original argument" {
	notify_set_waiting "myproj"
	output=$(notify_tty_read)
	b64=$(extract_setuservar_value "$output" "claudeWaitingProject")
	[ -n "$b64" ]
	decoded=$(decode_setuservar "$b64")
	[ "$decoded" = "myproj" ]
}

@test "notify_set_waiting: project with spaces decodes verbatim" {
	notify_set_waiting "my cool project"
	output=$(notify_tty_read)
	b64=$(extract_setuservar_value "$output" "claudeWaitingProject")
	decoded=$(decode_setuservar "$b64")
	[ "$decoded" = "my cool project" ]
}

@test "notify_set_waiting: project with punctuation/special chars decodes verbatim" {
	notify_set_waiting "weird/proj@v1.2 (test)"
	output=$(notify_tty_read)
	b64=$(extract_setuservar_value "$output" "claudeWaitingProject")
	decoded=$(decode_setuservar "$b64")
	[ "$decoded" = "weird/proj@v1.2 (test)" ]
}

@test "notify_set_waiting: since value decodes to a Unix timestamp near now" {
	before=$(date +%s)
	notify_set_waiting "myproj"
	after=$(date +%s)

	output=$(notify_tty_read)
	b64=$(extract_setuservar_value "$output" "claudeWaitingSince")
	[ -n "$b64" ]
	decoded=$(decode_setuservar "$b64")

	# Must be all digits.
	[[ "$decoded" =~ ^[0-9]+$ ]]
	# And bracketed by the wall-clock readings around the call.
	# Allow 1 second of slack on either side for clock jitter.
	[ "$decoded" -ge "$((before - 1))" ]
	[ "$decoded" -le "$((after + 1))" ]
}

@test "notify_set_waiting: empty project still emits both vars correctly" {
	notify_set_waiting ""
	output=$(notify_tty_read)
	# Project base64 of empty string is empty string.
	proj_b64=$(extract_setuservar_value "$output" "claudeWaitingProject")
	[ -z "$proj_b64" ]
	# Since must still be a valid timestamp.
	since_b64=$(extract_setuservar_value "$output" "claudeWaitingSince")
	[ -n "$since_b64" ]
	decoded=$(decode_setuservar "$since_b64")
	[[ "$decoded" =~ ^[0-9]+$ ]]
}

@test "notify_set_waiting: each emit follows OSC 1337 SetUserVar form" {
	notify_set_waiting "myproj"
	output=$(notify_tty_read)
	# Strict shape: ESC ] 1337 ; SetUserVar=<name>=<b64> BEL ESC ] 1337 ; SetUserVar=<name>=<b64> BEL
	# Verify both sequences begin with ESC]1337;SetUserVar=.
	expected_prefix1="${ESC}]1337;SetUserVar=claudeWaitingProject="
	expected_prefix2="${ESC}]1337;SetUserVar=claudeWaitingSince="
	[[ "$output" == *"$expected_prefix1"* ]]
	[[ "$output" == *"$expected_prefix2"* ]]
	# And exactly two BELs (already checked elsewhere) means no stray output.
}

# ---------- notify_clear_waiting ----------

@test "notify_clear_waiting: emits exactly two SetUserVar sequences" {
	notify_clear_waiting
	output=$(notify_tty_read)
	bel_count=$(printf '%s' "$output" | tr -cd "${BEL}" | wc -c | tr -d ' ')
	[ "$bel_count" -eq 2 ]
}

@test "notify_clear_waiting: both vars are emitted with empty values" {
	notify_clear_waiting
	output=$(notify_tty_read)
	# Use literal-string match: each var with trailing '=' and no value before BEL.
	[[ "$output" == *"${ESC}]1337;SetUserVar=claudeWaitingSince=${BEL}"* ]]
	[[ "$output" == *"${ESC}]1337;SetUserVar=claudeWaitingProject=${BEL}"* ]]
}
