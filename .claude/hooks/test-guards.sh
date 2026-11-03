#!/usr/bin/env bash
# Tests for the PreToolUse guards (ADR-0056). Run: just agent-hooks-test.
# Each case feeds a hook the JSON Claude Code would send and checks the outcome:
# allow (exit 0, no decision), block (exit 2), ask or inform (JSON on stdout).
set -uo pipefail

hooks=$(cd "$(dirname "$0")" && pwd)
root=$(git -C "$hooks" rev-parse --show-toplevel)
export CLAUDE_PROJECT_DIR=$root
failures=0

run() { # hook expected json
  local out code got
  out=$("$hooks/$1" <<<"$3" 2>/dev/null)
  code=$?
  case $code in
    2) got=block ;;
    0) case $out in
         *'"ask"'*) got=ask ;;
         *additionalContext*) got=inform ;;
         *) got=allow ;;
       esac ;;
    *) got="exit $code" ;;
  esac
  if [[ "$got" != "$2" ]]; then
    printf 'FAIL %s: expected %s, got %s for %s\n' "$1" "$2" "$got" "$3"
    failures=$((failures + 1))
  fi
}

bash_case() { # expected command
  run guard-bash.sh "$1" "$(jq -n --arg c "$2" --arg d "$root" \
    '{tool_name: "Bash", cwd: $d, tool_input: {command: $c}}')"
}

edit_case() { # expected relative-path new-text
  run guard-edit.sh "$1" "$(jq -n --arg f "$root/$2" --arg s "$3" \
    '{tool_name: "Edit", tool_input: {file_path: $f, old_string: "x", new_string: $s}}')"
}

bash_case allow 'just check'
bash_case allow 'git status --short'
bash_case allow 'git push -u origin feat/some-change'
bash_case allow 'git push --force-with-lease origin fix/typo'
bash_case allow 'gh pr merge 12 --squash --delete-branch'
bash_case allow 'git config user.name'
bash_case allow 'grep -ri co-authored-by scripts'
bash_case allow 'rm -rf ./target/tmp'
bash_case allow 'pnpm install --frozen-lockfile'
bash_case block 'git commit --no-verify -m "fix(scan): x"'
bash_case block 'LEFTHOOK=0 git commit -m "fix(scan): x"'
bash_case block $'git commit -m "fix(scan): x\n\nCo-Authored-By: Bot <b@x>"'
bash_case block 'gh pr create --title t --body "🤖 Generated with [Claude Code](https://x)"'
bash_case block 'git config --global user.email a@b.c'
bash_case block 'git -c user.name=bot commit -m "fix(scan): x"'
bash_case block 'git push origin main'
bash_case block 'git push origin HEAD:develop'
bash_case block 'git push --force origin +develop'
bash_case block 'git push --all'
bash_case block 'gh pr merge 12 --admin --squash'
bash_case ask 'gh pr merge 12 --merge'
bash_case ask 'gh pr create --base main --head develop --title t --body b'
bash_case block 'npm install left-pad'
bash_case block 'rm -rf ~'
bash_case inform 'cargo add serde_yaml'
bash_case inform 'pnpm --filter @lumen/web add zod'

edit_case allow crates/lumen-scan/src/lib.rs '#[cfg(target_os = "macos")] mod mac;'
edit_case allow crates/lumen-policy/src/lib.rs 'pub fn decide() {}'
edit_case allow crates/lumen-fs-exec/src/lib.rs 'std::fs::rename(a, b)?;'
edit_case allow apps/web/src/a.ts 'const company: Company = load();'
edit_case allow apps/web/src/a.ts 'const x: unknown = JSON.parse(s);'
edit_case allow crates/lumen-app/src/x.rs $'#[allow(clippy::disallowed_methods)] // temp fixture\nstd::fs::remove_dir_all(dir)?;'
edit_case block schemas/evidence.schema.json '{}'
edit_case block Cargo.lock 'x'
edit_case block .env 'KEY=1'
edit_case block crates/lumen-policy/src/lib.rs '#[cfg(target_os = "macos")] fn f() {}'
edit_case block crates/lumen-application/src/lib.rs '#[cfg(windows)] fn f() {}'
edit_case block crates/lumen-domain/src/lib.rs 'let t = std::fs::read(p);'
edit_case block crates/lumen-scan/src/walk.rs 'std::fs::remove_file(p)?;'
edit_case block apps/web/src/a.ts 'function f(x: any) {}'
edit_case block apps/web/src/a.ts 'const y = x as any;'
edit_case block apps/web/src/a.ts "import axios from 'axios';"

# Files of other repositories are not this project's business.
run guard-edit.sh allow "$(jq -n '{tool_name: "Write", tool_input: {file_path: "/tmp/elsewhere/Cargo.lock", content: "x"}}')"

if ((failures)); then
  echo "$failures guard test(s) failed"
  exit 1
fi
echo "guard tests passed"
