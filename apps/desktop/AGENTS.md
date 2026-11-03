# apps/desktop: local guide

The Tauri 2 host (ADR-0004). The webview is untrusted: it may call Lumen's own
commands and nothing else (ADR-0023). The UI itself lives in `apps/web`.

## Invariants

- No Tauri plugins, no file-system or shell access from the webview, strict CSP and
  the isolation pattern (`tauri.conf.json`, `isolation/`). Do not loosen any of them.
- Reads return view models. Mutations go through IDs: `plan` proposes, `execute`
  takes a plan ID with the confirmation hash the person saw, `restore` and
  `finalize` take an operation ID. A command never takes a path to change.
- Command handlers stay thin: they call `lumen-app`; logic and safety checks live in
  the core crates.

## Adding or renaming a command

Change all four together, or the call silently never answers:

1. `src-tauri/build.rs` (`let commands = &[…]`),
2. `src-tauri/capabilities/main.json` (`allow-<command>`, dashes for underscores),
3. `isolation/index.js` (the allowed set),
4. `tauri::generate_handler![…]` in `src-tauri/src/lib.rs`.

The test `every_command_is_registered_permitted_and_let_through` checks this. Then add
the call in `apps/web/src/shared/api/`, and update
[`docs/security/threat-model.md`](../../docs/security/threat-model.md) for a new
mutation.

## Checks

`cargo nextest run -p lumen-desktop`, then `just check`. CI builds the app on macOS,
Windows and Linux.
