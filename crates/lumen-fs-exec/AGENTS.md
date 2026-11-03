# lumen-fs-exec: local guide

The only crate that may move or delete user files (ADR-0015, ADR-0016). A bug here
loses someone's data. Read this before changing anything in this directory.

## Invariants

- Act by handle from a verified scan root, one name at a time; never on a path string
  resolved after verification. No link is followed, no volume crossed, no mount point
  entered.
- Compare every item with its record (identity, kind, size, time, link count) before
  acting. Any mismatch fails closed and the item goes to `REVIEW`.
- Renames never replace (`RENAME_NOREPLACE` / `RENAME_EXCL` /
  `ReplaceIfExists = FALSE`). Nothing is copied and then deleted.
- Permanent removal happens only inside a quarantine store, through `finalize`, after
  the whole tree is checked.
- Restore is never stricter than finalize: both use the same `check_held`.
- Every error says where it left the item (`Left`, `Removed`).
- `unsafe` only in `win_sys.rs`, each block with a `// SAFETY:` comment.

## Before you open a PR

1. Go through [`docs/security/executor-review.md`](../../docs/security/executor-review.md)
   item by item and say in the PR's Security section that you did.
2. Add a test for every new error path, in a temporary directory only
   (`tempfile`); races go in `tests/races.rs`, test-only fault points in
   `src/fault.rs` (ADR-0032).
3. `cargo nextest run -p lumen-fs-exec` here; the Windows paths (`win_*.rs`) run only
   in CI on `windows-2025`, so say so in the PR rather than claiming you tested them.
4. If the attack surface changed, update
   [`docs/security/threat-model.md`](../../docs/security/threat-model.md).

If you are unsure whether a change keeps an invariant, stop and ask the owner. Do not
weaken a check to make a test pass.
