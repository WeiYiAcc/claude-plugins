#!/bin/bash
# reconcile-status.sh - Detect ALL chezmoi drift, including silent template drift
#
# Usage:
#   bash ${CLAUDE_PLUGIN_ROOT}/scripts/reconcile-status.sh [--verbose]
#
# This script detects two types of drift:
#   1. VISIBLE drift: files where `chezmoi status` reports differences
#   2. SILENT drift: template-managed files where the target was edited
#      outside chezmoi but happens to match the rendered template output,
#      so `chezmoi status` stays quiet
#
# Exit codes:
#   0 - No drift detected (everything clean)
#   1 - Drift detected (see output for details)
#   2 - Error (missing tools, etc.)

set -euo pipefail

VERBOSE=false
if [[ "${1:-}" == "--verbose" ]]; then
	VERBOSE=true
fi

DRIFT_FOUND=false
VISIBLE_DRIFT=()
SILENT_DRIFT=()

# Color codes (if terminal supports it)
if [[ -t 1 ]]; then
	RED='\033[0;31m'
	YELLOW='\033[0;33m'
	GREEN='\033[0;32m'
	CYAN='\033[0;36m'
	BOLD='\033[1m'
	RESET='\033[0m'
else
	RED='' YELLOW='' GREEN='' CYAN='' BOLD='' RESET=''
fi

printf '%s\n' "${BOLD}Chezmoi Reconciliation Status${RESET}"
printf '%s\n' "=============================="
printf "\n"

# --- Sandbox environment check ---
if [[ "${TMPDIR:-}" == */tmp/claude* || "${TMPDIR:-}" == */private/tmp/claude* ]]; then
	printf '%sWARNING: Sandbox-overridden TMPDIR detected (%s)%s\n' "$RED" "$TMPDIR" "$RESET"
	printf '%sTemplates using {{ env "TMPDIR" }} will render with the sandbox path,%s\n' "$RED" "$RESET"
	printf '%scausing false positive drift. Run this script outside the sandbox%s\n' "$RED" "$RESET"
	printf '%s(dangerouslyDisableSandbox: true) for accurate results.%s\n' "$RED" "$RESET"
	printf "\n"
fi

# --- Pre-scan: Index template-managed files ---
# Built once with absolute paths so both the visible-drift loop and the
# silent-drift loop can do reliable lookups without re-querying chezmoi.
TMPL_TARGETS=()

while IFS= read -r target; do
	[[ -z "$target" ]] && continue
	src=$(chezmoi source-path "$target" 2>/dev/null || true)
	if [[ "$src" == *.tmpl ]]; then
		TMPL_TARGETS+=("$target")
	fi
done < <(chezmoi managed --include=files --path-style=absolute 2>/dev/null)

TMPL_COUNT=${#TMPL_TARGETS[@]}

if $VERBOSE; then
	printf '%s[0/2] Template index: %s template-managed file(s)%s\n' "$BOLD" "$TMPL_COUNT" "$RESET"
	printf "\n"
fi

# --- Part 1: Visible drift (chezmoi status) ---
printf '%s\n' "${BOLD}[1/2] Checking chezmoi status (visible drift)...${RESET}"
STATUS_OUTPUT=$(chezmoi status 2>/dev/null || true)

VISIBLE_RUN=()
VISIBLE_TMPL=()
INFRA_ADD_COUNT=0

if [[ -n "$STATUS_OUTPUT" ]]; then
	DRIFT_FOUND=true
	while IFS= read -r line; do
		col1="${line:0:1}"
		col2="${line:1:1}"
		path="${line:3}"

		is_tmpl=false
		tmpl_src=""
		# chezmoi status emits paths relative to the destination dir, but
		# `chezmoi source-path` resolves bare relative paths against CWD,
		# which is almost never $HOME when this script runs. So normalize
		# to an absolute path and look up in the pre-built template index
		# instead of re-querying source-path here.
		abs_path="$path"
		[[ "$abs_path" != /* ]] && abs_path="$HOME/$path"
		for t in "${TMPL_TARGETS[@]+"${TMPL_TARGETS[@]}"}"; do
			if [[ "$t" == "$abs_path" ]]; then
				is_tmpl=true
				tmpl_src=$(chezmoi source-path "$t" 2>/dev/null || echo "")
				VISIBLE_TMPL+=("$path")
				break
			fi
		done

		direction=""
		if [[ "$col1" == "R" || "$col2" == "R" ]]; then
			direction="[WILL EXECUTE] script will run (may have side effects)"
			VISIBLE_RUN+=("$path")
		elif [[ "$col1" != " " && "$col2" != " " ]]; then
			direction="both directions"
		elif [[ "$col2" == "M" ]]; then
			direction="source template differs from target (chezmoi apply would change target)"
		elif [[ "$col2" == "A" ]]; then
			direction="new file in source (chezmoi apply would create target)"
			if [[ "$path" != *dot_* && "$path" != *private_* && "$path" != *executable_* ]]; then
				((INFRA_ADD_COUNT++)) || true
			fi
		elif [[ "$col2" == "D" ]]; then
			direction="removed from source (chezmoi apply would delete target)"
		elif [[ "$col1" == "M" ]]; then
			direction="target edited outside chezmoi"
		else
			direction="status: ${col1}${col2}"
		fi

		VISIBLE_DRIFT+=("$path")

		tmpl_tag=""
		if $is_tmpl; then
			tmpl_tag=" ${CYAN}[TEMPLATE]${RESET}"
		fi

		if [[ "$col1" == "R" || "$col2" == "R" ]]; then
			printf '  %sRUN%s      %s%s  %s%s\n' "$RED" "$RESET" "$col1" "$col2" "$path" "$tmpl_tag"
		else
			printf '  %sVISIBLE%s  %s%s  %s%s\n' "$YELLOW" "$RESET" "$col1" "$col2" "$path" "$tmpl_tag"
		fi
		if $VERBOSE; then
			printf "           %s\n" "$direction"
			if $is_tmpl; then
				printf '           %ssource: %s%s\n' "$CYAN" "$tmpl_src" "$RESET"
				printf '%s\n' "           ${CYAN}re-add on a template is unsafe (strips directives or silently no-ops) -- edit template manually instead${RESET}"
			fi
		fi
	done <<<"$STATUS_OUTPUT"
else
	printf '%s\n' "  ${GREEN}Clean${RESET} - no visible differences"
fi

# Warn about script entries
if [[ ${#VISIBLE_RUN[@]} -gt 0 ]]; then
	printf "\n"
	printf '  %s%sNote:%s %s entry(s) marked RUN will %sexecute scripts%s, not just modify files.\n' "$RED" "$BOLD" "$RESET" "${#VISIBLE_RUN[@]}" "$RED" "$RESET"
	printf "  Scripts may take a long time, require interactive input, or have side effects.\n"
fi

# Warn about template-managed drift
if [[ ${#VISIBLE_TMPL[@]} -gt 0 ]]; then
	printf "\n"
	printf '  %s%sNote:%s %s drifted file(s) are %stemplate-managed%s.\n' "$CYAN" "$BOLD" "$RESET" "${#VISIBLE_TMPL[@]}" "$CYAN" "$RESET"
	printf '%s\n' "  ${CYAN}Do NOT use 'chezmoi re-add' on these -- it strips directives or silently no-ops.${RESET}"
	printf '%s\n' "  ${CYAN}Instead, edit the .tmpl source file to incorporate the live changes.${RESET}"
fi

# Warn about possible infrastructure false positives
if [[ $INFRA_ADD_COUNT -gt 5 ]]; then
	printf "\n"
	printf '  %s%sHint:%s %s '"'"'add'"'"' entries don'"'"'t follow chezmoi naming conventions.\n' "$YELLOW" "$BOLD" "$RESET" "$INFRA_ADD_COUNT"
	printf '%s\n' "  These may be repo infrastructure files that need to be added to ${BOLD}.chezmoiignore${RESET}."
fi

printf "\n"

# --- Part 2: Silent template drift ---
printf '%s\n' "${BOLD}[2/2] Checking template entry states (silent drift)...${RESET}"

STATE_JSON=$(chezmoi state dump 2>/dev/null)

if [[ ${#TMPL_TARGETS[@]} -eq 0 ]]; then
	printf "  No template-managed files found\n"
else
	for target in "${TMPL_TARGETS[@]}"; do
		skip=false
		for visible in "${VISIBLE_DRIFT[@]+"${VISIBLE_DRIFT[@]}"}"; do
			if [[ "$target" == *"$visible"* || "$visible" == *"$target"* ]]; then
				skip=true
				break
			fi
		done
		if $skip; then
			if $VERBOSE; then
				printf '  %sSKIP%s    %s (already in visible drift)\n' "$CYAN" "$RESET" "$target"
			fi
			continue
		fi

		entry_hash=$(printf '%s' "$STATE_JSON" | jq -r --arg key "$target" '.entryState[$key].contentsSHA256 // empty' 2>/dev/null || true)

		if [[ -z "$entry_hash" ]]; then
			if $VERBOSE; then
				printf '  %sSKIP%s    %s (no entry state -- never applied?)\n' "$CYAN" "$RESET" "$target"
			fi
			continue
		fi

		if [[ ! -f "$target" ]]; then
			if $VERBOSE; then
				printf '  %sSKIP%s    %s (target file does not exist)\n' "$CYAN" "$RESET" "$target"
			fi
			continue
		fi

		actual_hash=$(shasum -a 256 "$target" 2>/dev/null | awk '{print $1}')

		if [[ "$entry_hash" != "$actual_hash" ]]; then
			DRIFT_FOUND=true
			SILENT_DRIFT+=("$target")
			src=$(chezmoi source-path "$target" 2>/dev/null || echo "unknown")
			printf '  %sSILENT%s   %s\n' "$RED" "$RESET" "$target"
			if $VERBOSE; then
				printf "           source:      %s\n" "$src"
				printf '           entry state:  %s...\n' "${entry_hash:0:16}"
				printf '           actual file:  %s...\n' "${actual_hash:0:16}"
				printf "           Target was edited outside chezmoi but matches rendered template.\n"
				printf "           Edit the .tmpl source to incorporate the live changes.\n"
				printf "           Or:  chezmoi apply --force %s  (overwrite target, discarding live changes)\n" "$target"
			fi
		else
			if $VERBOSE; then
				printf '  %sCLEAN%s   %s\n' "$GREEN" "$RESET" "$target"
			fi
		fi
	done

	if [[ ${#SILENT_DRIFT[@]} -eq 0 ]]; then
		printf '%s\n' "  ${GREEN}Clean${RESET} - no silent template drift detected"
	fi
fi

printf "\n"

# --- Summary ---
printf '%s\n' "${BOLD}Summary${RESET}"
printf '%s\n' "-------"
printf "Visible drift:  %d file(s)\n" "${#VISIBLE_DRIFT[@]}"
printf "  Scripts (R):  %d\n" "${#VISIBLE_RUN[@]}"
printf "  Templates:    %d\n" "${#VISIBLE_TMPL[@]}"
printf "Silent drift:   %d file(s)\n" "${#SILENT_DRIFT[@]}"
printf "Template index: %d total template-managed file(s)\n" "$TMPL_COUNT"
printf "\n"

if $DRIFT_FOUND; then
	printf '%sDrift detected.%s Reconciliation needed.\n' "$YELLOW" "$RESET"
	printf "\n"
	printf "To resolve plain (non-template) drift:\n"
	printf "  chezmoi diff                    # review differences\n"
	printf "  chezmoi re-add <file>           # accept target changes into source\n"
	printf "  chezmoi apply --force <file>    # overwrite target with source\n"
	printf "\n"
	if [[ ${#VISIBLE_TMPL[@]} -gt 0 || ${#SILENT_DRIFT[@]} -gt 0 ]]; then
		printf 'To resolve %stemplate%s drift:\n' "$CYAN" "$RESET"
		printf "  Edit the .tmpl source file directly to incorporate live changes.\n"
		printf "  Do NOT use 'chezmoi re-add' -- it strips directives or silently no-ops on templates.\n"
		printf "  chezmoi apply --force <file>    # overwrite target with source (discards live changes)\n"
		printf "\n"
	fi
	exit 1
else
	printf '%sAll clean!%s No drift detected.\n' "$GREEN" "$RESET"
	exit 0
fi
