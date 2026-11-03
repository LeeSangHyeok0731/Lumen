#!/usr/bin/env bash
# PreToolUse guard for file edits (ADR-0056). Refuses edits that break a hard rule
# of AGENTS.md, with the fix in the message. Exit 2 blocks the edit and shows stderr
# to the agent. Fails open on its own errors: clippy, Biome and CI remain the
# boundary; this only says it sooner.
set -uo pipefail

command -v jq >/dev/null || exit 0
input=$(cat)
file=$(jq -r '.tool_input.file_path // .tool_input.notebook_path // empty' <<<"$input" 2>/dev/null) || exit 0
# The text the edit would add (Write, Edit and MultiEdit).
new=$(jq -r '[.tool_input.content, .tool_input.new_string,
  (.tool_input.edits // [] | .[].new_string)] | map(select(. != null)) | join("\n")' \
  <<<"$input" 2>/dev/null) || exit 0
[[ -n "$file" && -n "${CLAUDE_PROJECT_DIR:-}" ]] || exit 0

# Only files of this project (any worktree of it) are checked.
dir=$(dirname "$file")
while [[ ! -d "$dir" ]]; do dir=$(dirname "$dir"); done
common() { git -C "$1" rev-parse --path-format=absolute --git-common-dir 2>/dev/null; }
[[ "$(common "$dir")" == "$(common "$CLAUDE_PROJECT_DIR")" ]] || exit 0
top=$(git -C "$dir" rev-parse --show-toplevel 2>/dev/null) || exit 0
rel=${file#"$top"/}
name=$(basename "$file")

block() {
  printf 'Blocked by .claude/hooks/guard-edit.sh (%s): %s\nFix: %s\n' "$rel" "$1" "$2" >&2
  exit 2
}

# --- Secrets never pass through an agent. ---
if [[ "$name" =~ ^\.env($|\.) && "$name" != ".env.example" ]] ||
  [[ "$name" =~ \.(pem|p8|p12|key|keystore|jks)$ ]]; then
  block "secrets and signing keys are never written by an agent." \
    "Ask the owner to change this file; reference secrets by name only (see docs/operations/release.md)."
fi

# --- Generated files are regenerated, not edited. ---
case $rel in
  schemas/*)
    block "schemas/ is generated from the Rust types (ADR-0011)." \
      "Change the type in crates/, then run: just gen (cargo xtask schema) and commit the result." ;;
  Cargo.lock | */Cargo.lock | pnpm-lock.yaml | */pnpm-lock.yaml)
    block "lockfiles are written by cargo and pnpm." \
      "Edit Cargo.toml or package.json, then run cargo update -p <crate> --precise <version> or pnpm install." ;;
esac

# --- Pure crates: no platform code, no IO (system.md §5.1). ---
if [[ "$rel" =~ ^crates/lumen-(domain|policy|graph|application)/ ]] &&
  [[ "$new" =~ target_os|target_family|cfg\(unix|cfg\(windows ]]; then
  block "the domain, policy, graph and application crates have no platform code." \
    "Put platform-specific code in an adapter (crates/lumen-platform-*, lumen-scan) behind a port in lumen-application."
fi
if [[ "$rel" =~ ^crates/lumen-(domain|policy|graph)/ ]] &&
  [[ "$new" =~ std::(fs|net|process|thread|env)|tokio ]]; then
  block "lumen-domain, lumen-policy and lumen-graph are IO-free." \
    "Take the data as an argument; let lumen-application or an adapter fetch it through a port."
fi

# --- Only lumen-fs-exec changes user files (ADR-0016). ---
if [[ "$rel" == *.rs && ! "$rel" =~ ^crates/lumen-fs-exec/ ]] &&
  [[ "$new" =~ fs::(remove_file|remove_dir|remove_dir_all|rename|copy|set_permissions)\( ]] &&
  [[ ! "$new" =~ allow\(clippy::disallowed_methods ]]; then
  block "destructive filesystem calls belong only in crates/lumen-fs-exec, which acts by verified handle (ADR-0016)." \
    "Go through the Executor / QuarantineStore ports. Test-only cleanup of a temporary fixture may use the call with #[allow(clippy::disallowed_methods)] and a comment saying why it is safe."
fi

# --- TypeScript rules (AGENTS.md › Code). ---
if [[ "$rel" =~ \.(ts|tsx|mts|cts)$ ]]; then
  if [[ "$new" =~ (:|<|as|\|)[[:space:]]*any([^A-Za-z0-9_\$]|$) ]]; then
    block "TypeScript here is strict: no any." \
      "Use unknown and narrow it, a precise type, or a Zod schema at an untrusted edge."
  fi
  if [[ "$new" =~ from[[:space:]]*[\'\"]axios[\'\"] ]]; then
    block "HTTP uses native fetch, never axios." "Use fetch and validate the response with Zod."
  fi
fi

exit 0
