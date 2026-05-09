#!/bin/bash
# user-prompt-submit.sh - UserPromptSubmit hook entry point.
#
# When the user submits a prompt, the session is no longer waiting:
# clear the iTerm2 user variables that mark it. The Python AutoLaunch
# watcher will see the transition to empty and skip this session in
# the cycling RPC.

set -euo pipefail

# shellcheck source=lib/notify.sh
source "${CLAUDE_PLUGIN_ROOT}/hooks/scripts/lib/notify.sh"

cat >/dev/null

notify_clear_waiting
