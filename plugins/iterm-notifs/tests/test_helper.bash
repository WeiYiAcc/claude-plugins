# test_helper.bash - shared setup for iterm-notifs bats tests.
#
# Resolves paths relative to the plugin root so tests can be invoked
# from anywhere (e.g. `bats tests/` from plugin root, or by absolute
# path from elsewhere).

# Plugin root = parent of this tests/ directory.
PLUGIN_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export PLUGIN_ROOT

SCRIPTS_DIR="${PLUGIN_ROOT}/hooks/scripts"
LIB_DIR="${SCRIPTS_DIR}/lib"
export SCRIPTS_DIR LIB_DIR

# Escape sequence byte constants.
# ESC = 0x1b, BEL = 0x07. Bash $'...' handles the C escapes.
ESC=$'\033'
BEL=$'\007'
export ESC BEL

# Set up a fake TTY target file so tests can capture notify output.
# notify.sh's primitives write to $ITERM_NOTIFS_TTY (defaults to /dev/tty
# in production); here we point at a fresh temp file per test.
notify_tty_setup() {
	export ITERM_NOTIFS_TTY="${BATS_TEST_TMPDIR:-/tmp}/iterm-notifs-out-$$"
	: >"$ITERM_NOTIFS_TTY"
}

# Read everything captured at the fake TTY since the last setup.
notify_tty_read() {
	cat "$ITERM_NOTIFS_TTY" 2>/dev/null
}

# Decode an iTerm2 SetUserVar value (base64) back to plaintext.
# Usage: decode_setuservar "<base64-string>"
decode_setuservar() {
	printf '%s' "$1" | base64 -d 2>/dev/null
}

# Extract the base64 value of a SetUserVar emission for a given var name.
# Pulls from a captured stdout blob. Returns empty string if not found.
# Usage: extract_setuservar_value "<output>" "<varname>"
extract_setuservar_value() {
	local output="$1"
	local var="$2"
	# OSC sequence: ESC]1337;SetUserVar=<var>=<b64>BEL
	# Use awk with explicit byte separators. ESC=\033, BEL=\007.
	printf '%s' "$output" | awk -v var="$var" '
		BEGIN { RS="\007"; FS=";" }
		{
			for (i = 1; i <= NF; i++) {
				if (match($i, /^SetUserVar=/)) {
					payload = substr($i, RSTART + RLENGTH)
					eq = index(payload, "=")
					if (eq > 0) {
						name = substr(payload, 1, eq - 1)
						val  = substr(payload, eq + 1)
						if (name == var) { print val; exit }
					}
				}
			}
		}
	'
}

# Returns 0 if the given output blob contains a SetUserVar emission
# for the given var name (regardless of value).
# Usage: has_setuservar "<output>" "<varname>"
has_setuservar() {
	local output="$1"
	local var="$2"
	printf '%s' "$output" | awk -v var="$var" '
		BEGIN { RS="\007"; FS=";"; found=0 }
		{
			for (i = 1; i <= NF; i++) {
				if (match($i, /^SetUserVar=/)) {
					payload = substr($i, RSTART + RLENGTH)
					eq = index(payload, "=")
					if (eq > 0) {
						name = substr(payload, 1, eq - 1)
						if (name == var) { found=1 }
					} else if (payload == var) {
						# Defensive: malformed SetUserVar with no value.
						found=1
					}
				}
			}
		}
		END { exit (found ? 0 : 1) }
	'
}

# Returns the byte offset (1-based) of the first occurrence of needle
# in haystack, or 0 if not found. Used to assert ordering of emits.
# Usage: index_of "<haystack>" "<needle>"
index_of() {
	local haystack="$1"
	local needle="$2"
	awk -v h="$haystack" -v n="$needle" 'BEGIN { print index(h, n) }'
}
