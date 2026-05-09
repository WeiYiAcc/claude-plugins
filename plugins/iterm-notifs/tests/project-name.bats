#!/usr/bin/env bats
# Tests for hooks/scripts/lib/project-name.sh.
#
# Uses real git repos in mktemp dirs as fixtures. Cheap, deterministic,
# and exercises the actual git plumbing the function depends on.

load 'test_helper'

setup() {
	# shellcheck source=../hooks/scripts/lib/project-name.sh
	source "${LIB_DIR}/project-name.sh"

	# Per-test scratch dir. Sandbox-friendly: under $TMPDIR.
	TEST_TMP="$(mktemp -d "${TMPDIR:-/tmp}/iterm-notifs-tests.XXXXXX")"
	export TEST_TMP

	# Make sure git operations in fixtures don't pick up the developer's
	# global hooks/templates/identity.
	export GIT_CONFIG_GLOBAL=/dev/null
	export GIT_CONFIG_SYSTEM=/dev/null
}

teardown() {
	if [[ -n "${TEST_TMP:-}" && -d "$TEST_TMP" ]]; then
		rm -rf "$TEST_TMP"
	fi
}

# ---------- non-git paths ----------

@test "project_name: returns basename of cwd when not in a git repo" {
	mkdir -p "${TEST_TMP}/standalone-dir"
	run project_name "${TEST_TMP}/standalone-dir"
	[ "$status" -eq 0 ]
	[ "$output" = "standalone-dir" ]
}

@test "project_name: works on a non-git path with no stderr noise" {
	mkdir -p "${TEST_TMP}/quiet-dir"
	# Capture stdout and stderr separately by running through a wrapper.
	output_file="${TEST_TMP}/stdout"
	stderr_file="${TEST_TMP}/stderr"
	project_name "${TEST_TMP}/quiet-dir" >"$output_file" 2>"$stderr_file"
	rc=$?
	[ "$rc" -eq 0 ]
	[ "$(cat "$output_file")" = "quiet-dir" ]
	# Stderr must be empty - the function suppresses git's "not a repo" errors.
	[ ! -s "$stderr_file" ]
}

@test "project_name: returns basename even when path has trailing structure" {
	mkdir -p "${TEST_TMP}/parent/nested-leaf"
	run project_name "${TEST_TMP}/parent/nested-leaf"
	[ "$status" -eq 0 ]
	[ "$output" = "nested-leaf" ]
}

# ---------- git-tracked paths ----------

@test "project_name: returns repo toplevel basename when cwd is repo root" {
	repo="${TEST_TMP}/myrepo"
	mkdir -p "$repo"
	git -C "$repo" init -q
	run project_name "$repo"
	[ "$status" -eq 0 ]
	[ "$output" = "myrepo" ]
}

@test "project_name: returns repo toplevel basename when cwd is deep inside repo" {
	repo="${TEST_TMP}/cool-project"
	mkdir -p "${repo}/a/b/c/d"
	git -C "$repo" init -q
	run project_name "${repo}/a/b/c/d"
	[ "$status" -eq 0 ]
	[ "$output" = "cool-project" ]
}

@test "project_name: returns repo basename even when repo dir has spaces" {
	repo="${TEST_TMP}/my cool repo"
	mkdir -p "$repo/sub"
	git -C "$repo" init -q
	run project_name "${repo}/sub"
	[ "$status" -eq 0 ]
	[ "$output" = "my cool repo" ]
}

@test "project_name: handles non-existent path gracefully (falls back to basename)" {
	# git -C on a missing dir errors out, so we should hit the fallback.
	# basename of a bogus path is just the trailing component.
	run project_name "${TEST_TMP}/does-not-exist/leaf"
	[ "$status" -eq 0 ]
	[ "$output" = "leaf" ]
}
