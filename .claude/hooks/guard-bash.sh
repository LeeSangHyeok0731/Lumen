#!/usr/bin/env bash
# PreToolUse guard for Bash commands (ADR-0056). Blocks commands that break a hard
# rule of AGENTS.md before they run, and asks the person before a release step.
# Exit 2 blocks the command and shows stderr to the agent. The guard fails open on
# its own errors: CI, branch protection and the Git hooks remain the boundary.
set -uo pipefail

command -v jq >/dev/null || exit 0
input=$(cat)
cmd=$(jq -r '.tool_input.command // empty' <<<"$input" 2>/dev/null) || exit 0
cwd=$(jq -r '.cwd // empty' <<<"$input" 2>/dev/null) || exit 0
[[ -n "$cmd" ]] || exit 0

block() {
  printf 'Blocked by .claude/hooks/guard-bash.sh: %s\nFix: %s\n' "$1" "$2" >&2
  exit 2
}

ask() {
  jq -n --arg r "$1" '{hookSpecificOutput: {hookEventName: "PreToolUse",
    permissionDecision: "ask", permissionDecisionReason: $r}}'
  exit 0
}

inform() {
  jq -n --arg c "$1" '{hookSpecificOutput: {hookEventName: "PreToolUse",
    additionalContext: $c}}'
  exit 0
}

ws='[[:space:]]'

# The repository the command acts on: the target of a leading `cd`, or the
# session's directory. Branch rules apply only inside this project.
dir=$cwd
if [[ "$cmd" =~ ^cd$ws+([^[:space:];\&|]+) ]]; then
  dir=${BASH_REMATCH[1]/#\~/$HOME}
fi
common() { git -C "$1" rev-parse --path-format=absolute --git-common-dir 2>/dev/null; }
branch=""
if [[ -n "${CLAUDE_PROJECT_DIR:-}" && -n "$dir" ]] &&
  [[ "$(common "$dir")" == "$(common "$CLAUDE_PROJECT_DIR")" ]]; then
  branch=$(git -C "$dir" branch --show-current 2>/dev/null)
fi

# --- Checks and hooks are never bypassed (AGENTS.md › Git). ---
if [[ "$cmd" =~ --no-verify|LEFTHOOK=0|LEFTHOOK_EXCLUDE=|core\.hooksPath|lefthook$ws+uninstall ]]; then
  block "Git hooks and checks are never bypassed." \
    "Run the command without the bypass. If a hook fails, fix what it reports (just check shows everything)."
fi

# --- No attribution trailers (AGENTS.md › Git, ADR-0027). ---
if [[ "$cmd" =~ git$ws+commit|gh$ws+pr$ws+(create|edit|merge) ]]; then
  shopt -s nocasematch
  if [[ "$cmd" =~ co-authored-by|generated$ws+with$ws+\[?claude ]]; then
    shopt -u nocasematch
    block "Co-Authored-By and other AI attribution lines are not allowed in commits or PRs." \
      "Remove those lines from the message or body and run the command again."
  fi
  shopt -u nocasematch
fi

# --- The repository's Git identity is never changed (AGENTS.md › Git). ---
if [[ "$cmd" =~ git$ws+(.*$ws)?config$ws+(--[a-z]+$ws+)*user\.(name|email)$ws+[^[:space:]-] ||
  "$cmd" =~ git$ws+-c$ws*user\.(name|email)= ||
  "$cmd" =~ GIT_(AUTHOR|COMMITTER)_(NAME|EMAIL)= ||
  "$cmd" =~ git$ws+commit.*--author ]]; then
  block "The configured Git identity is used as is and never changed." \
    "Drop the identity override; commit with the repository's configured user."
fi

# --- One change per branch; main and develop only move through PRs. ---
if [[ "$cmd" =~ git$ws+commit && "$branch" =~ ^(main|develop)$ ]]; then
  block "Commits are not made on $branch; every change goes through a PR (AGENTS.md › Working loop)." \
    "Create a branch first: git checkout -b <type>/<short-slug>, then commit there."
fi

if [[ "$cmd" =~ git${ws}+push(${ws}[^;\&|]*)? ]]; then
  read -r -a words <<<"${BASH_REMATCH[1]:-}"
  refspecs=()
  for word in "${words[@]}"; do
    case $word in
      --all | --mirror) block "Pushing every branch would include main and develop." \
        "Push only your branch: git push -u origin <type>/<short-slug>." ;;
      -*) ;;
      *) refspecs+=("$word") ;;
    esac
  done
  # The first word is the remote; the rest are refspecs. None means the current branch.
  targets=("${refspecs[@]:1}")
  ((${#targets[@]})) || targets=("$branch")
  for ref in "${targets[@]}"; do
    if [[ "$ref" =~ ^\+?([^:]*:)?(refs/heads/)?(main|develop)$ ]]; then
      block "main and develop are never pushed to directly; a push to main releases to every installed copy (ADR-0054)." \
        "Push your feature branch and open a PR into develop: git push -u origin <type>/<short-slug>; gh pr create --base develop."
    fi
  done
fi

# --- Merges only after green CI; releases only when the owner asks (ADR-0054). ---
if [[ "$cmd" =~ gh$ws+pr$ws+merge && "$cmd" =~ --admin ]]; then
  block "--admin merges past failing or pending checks." \
    "Wait for CI (gh pr checks <number> --watch), fix any failure, then merge with --squash --delete-branch."
fi
if [[ "$cmd" =~ gh$ws+pr$ws+merge && "$cmd" =~ (^|$ws)--merge($ws|$) ]] ||
  [[ "$cmd" =~ gh$ws+pr$ws+create && "$cmd" =~ (--base|-B)[=[:space:]]+main($ws|$) ]]; then
  ask "This is the release path into main (ADR-0054): merging it publishes to every installed copy. Only the owner starts a release. Allow only if you asked for this release."
fi

# --- The JavaScript workspace uses pnpm (packageManager in package.json). ---
if [[ "$cmd" =~ (^|[;\&|]$ws*)(npm$ws+(i|install|add|ci)|yarn)($ws|$) ]]; then
  block "This workspace is managed by pnpm (Corepack); npm or yarn would write a second lockfile." \
    "Use pnpm instead, e.g. pnpm install --frozen-lockfile, or pnpm --filter <package> add <dependency>."
fi

# --- Destructive commands on broad paths. ---
if [[ "$cmd" =~ rm$ws+-[a-zA-Z]*[rR][a-zA-Z]*$ws+(/|~|\$HOME|\.\.?)/?($ws|$) ]]; then
  block "Recursive removal of /, ~, \$HOME, . or .. is never run by an agent." \
    "Remove the specific path you created, inside the repository or a temporary directory."
fi

# --- New dependencies need a justification (AGENTS.md › Code). ---
if [[ "$cmd" =~ cargo$ws+add$ws|pnpm$ws+(.*$ws)?add$ws ]]; then
  inform "New dependency: the PR must justify it (alternatives considered, maintenance, license, security history, size), and cargo-deny / OSV must pass. Prefer the standard library and platform APIs."
fi

exit 0
