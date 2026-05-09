#!/bin/bash
# notification.sh - Claude Code Notification hook entry point.
#
# Routes by notification_type: idle_prompt and permission_prompt are
# the user-attention cases that trigger banner + bounce + waiting marker.
# Other types are silent.
#
# Stdin: JSON with at least { notification_type, cwd, ... }.

set -euo pipefail

# shellcheck source=lib/notify.sh
source "${CLAUDE_PLUGIN_ROOT}/hooks/scripts/lib/notify.sh"
# shellcheck source=lib/project-name.sh
source "${CLAUDE_PLUGIN_ROOT}/hooks/scripts/lib/project-name.sh"

input=$(cat)
# `|| true` keeps the hook resilient to malformed JSON: if jq fails, the
# variable comes through empty and the case below silently no-ops, instead
# of pipefail/errexit propagating a non-zero exit that would break the
# hook chain. jq's stderr is preserved so debugging is still possible.
notification_type=$(printf '%s' "$input" | jq -r '.notification_type // empty' || true)
cwd=$(printf '%s' "$input" | jq -r '.cwd // empty' || true)
project=$(project_name "${cwd:-$PWD}")

case "$notification_type" in
idle_prompt)
	notify_banner "Claude waiting in $project"
	notify_bounce
	notify_set_waiting "$project"
	;;
permission_prompt)
	notify_banner "Claude needs permission in $project"
	notify_bounce
	notify_set_waiting "$project"
	;;
*)
	# Other notification types (auth_success, elicitation_*, etc.) are silent.
	;;
esac
