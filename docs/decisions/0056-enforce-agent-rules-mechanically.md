# ADR-0056: Enforce the agent operating rules mechanically

- Status: Accepted (owner request, 2026-11-03)
- Date: 2026-11-03
- Builds on: [ADR-0025](0025-code-quality-tooling.md),
  [ADR-0027](0027-atomic-commit-pr-workflow.md)

## Context and problem statement

Most of Lumen's code is written by AI coding agents. Their rules live in
[`AGENTS.md`](../../AGENTS.md) as prose. Claude Code loads that prose as context, not
as enforced configuration, and a weaker model forgets or misapplies it: it edits a
generated schema by hand, adds `#[cfg(target_os)]` to a pure crate, pushes to `main`
(which releases, ADR-0054), or skips a step of the PR loop. The commit hook and CI
catch some of this, late; the crate dependency rules in
[system.md §5.1](../architecture/system.md#51-layers-and-crates) are said to be
checked in CI, and are not.

The owner asked for a harness good enough that a weak model can develop Lumen
safely. Findings: [research note 33](../research/33-coding-agent-harness.md).

## Decision drivers

- User-data safety and the release branch must not depend on a model remembering a
  rule.
- Feedback early and specific: the message that stops an agent says which rule and
  how to fix it.
- Agent-neutral where possible: the same checks hold for people, Codex, Claude Code
  and CI.
- Small context: an agent sees the rules for the code it touches, not every rule.
- No new dependencies; nothing that weakens or replaces an existing check.

## Considered options

1. **Prose only (status quo):** improve `AGENTS.md` and rely on CI.
2. **Agent-tool guard rails only:** Claude Code hooks and permissions.
3. **Layered harness:** repository checks first, agent-tool guard rails on top, and
   instructions disclosed where they apply.

## Decision outcome

Chosen option: **3**. Option 1 is what failed. Option 2 protects only Claude Code
sessions and leaves CI as blind as before.

1. **Repository checks** (`cargo xtask lint`, part of `just check` and CI): the crate
   layering of §5.1, no IO or platform code in the pure crates, every ADR in the
   index, and relative links in the documentation resolving. Every failure prints the
   rule, the offending item and the fix.
2. **Claude Code hooks** (`.claude/settings.json`, `.claude/hooks/`): block commands
   that break a hard rule before they run (`--no-verify`, pushing to or force-pushing
   `main`/`develop`, merging into `main`, attribution trailers, changing the Git
   identity); refuse hand edits of generated files and of `#[cfg(target_os)]` in pure
   crates; format a file right after it is edited; brief the session on branch and
   state when it starts; run fast checks before the agent reports it is done.
3. **Local guides:** a short `AGENTS.md` in each safety-critical directory, with a
   `CLAUDE.md` that imports it so Claude Code loads it on demand.
4. **Skills and a reviewer:** the PR loop and ADR creation as step-by-step skills,
   and a read-only subagent that reviews a diff against the hard rules.

Rules for the harness itself:

- CI, branch protection and the commit hooks remain the boundary. Hooks are early
  warnings: they only block or inform, never approve a tool call, and their absence
  never makes an unsafe change mergeable.
- Hooks are fast (a few seconds), read-only apart from formatting the file just
  edited, and fail open on their own errors (a broken hook must not stop work it was
  not written to stop).
- When an agent repeats a mistake, the rule moves from prose into a check or a hook.

### Consequences

- Good: the layering claim in system.md becomes true; a push to `main` from a Claude
  Code session needs the owner to run it; weaker models get the fix in the error.
- Good: the root `AGENTS.md` can stay a map while local guides carry detail.
- Bad: two more places to keep current (hooks, local guides); `cargo xtask lint`
  checks their links, and the reviewer subagent checks the hard rules, but the guides'
  content can still go stale.
- Bad: hooks run `jq`, `bash` and `git` on the developer's machine; without `jq` the
  guards fail open and only CI remains.

## More information

- [Research note 33: coding-agent harness](../research/33-coding-agent-harness.md)
- [Claude Code hooks](https://code.claude.com/docs/en/hooks),
  [memory](https://code.claude.com/docs/en/memory),
  [skills](https://code.claude.com/docs/en/skills),
  [subagents](https://code.claude.com/docs/en/sub-agents)
