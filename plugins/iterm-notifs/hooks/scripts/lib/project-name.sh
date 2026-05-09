#!/bin/bash
# project-name.sh - derive a human-readable project name from a cwd.

# Echoes the project name to stdout. Tries git toplevel basename first,
# falls back to the basename of the given cwd.
project_name() {
	local cwd="$1"
	local toplevel
	if toplevel=$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null); then
		basename "$toplevel"
		return
	fi
	basename "$cwd"
}
