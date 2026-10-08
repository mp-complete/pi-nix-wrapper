# Repository guidance

This repository provides a Nix flake and reusable nix-wrapper-modules wrapper
for the Pi coding agent. Keep changes focused and preserve the public APIs in
`flake.nix`, `lib/`, and `wrapperModules/pi/`.

## Code review priorities

- Report actionable correctness, security, and compatibility issues introduced
  by the change. Explain the affected behavior and point to the relevant lines;
  avoid speculative findings, style-only feedback, and unrelated refactoring.
- Check Nix module composition: additive resource lists must compose across
  imports, `.apply`, and `.wrap`; preserve option types, defaults, explicit
  overrides, and the exported overlay. Consider all declared Linux and Darwin
  systems, not just the Linux CI runner.
- Check generated shell code for quoting, spaces, literal special characters,
  and argument boundaries. Preserve intentional runtime expansion of trusted
  `configDir` and `sessionDir` values without expanding literal resource paths.
  Pi subcommands must remain the first argument and bypass injected session
  flags; keep the guard against self-updating the Nix-managed Pi executable.
- Preserve caller-provided environment overrides, especially
  `PI_CODING_AGENT_DIR` and `PI_CODING_AGENT_SESSION_DIR`. Renamed wrappers should
  retain isolated state directories, and offline defaults must remain
  overridable.
- Never embed credentials in Nix declarations, generated files, examples, or
  logs: declared contents enter the Nix store. MCP credentials should use Pi's
  runtime interpolation or credential storage. Review writable config changes
  for path traversal, symlink handling, restrictive permissions, atomic
  publication, and the distinct `seed` and `enforce` ownership semantics.
- Preserve hash-pinned npm extension sources and selected entrypoint suffixes.
  `mkPiExtension` extracts the tarball but does not install dependencies; do not
  assume external npm dependencies are available.
- Expect regression coverage for changed behavior in the existing `flake.nix`
  checks and `tests/`, including failure cases where relevant. Prioritize module
  composition, shell arguments, environment precedence, resource discovery,
  subcommand dispatch, and safe config-file installation.

## Validation and review policy

- Use the existing `nix fmt` formatter and `nix flake check -L` checks for code
  changes. Documentation-only changes do not require Nix builds.
- `.github/workflows/ci.yml` runs the **Nix flake checks** job on pull requests.
  Keep this CI check as the merge gate; Copilot feedback is advisory and does
  not replace human approval where required.
- This file supplies guidance, not automatic review activation. A repository
  administrator must activate a ruleset targeting `main`, enable automatic
  Copilot code review including new pushes (and drafts if desired), and require
  **Nix flake checks** to pass. Verify the behavior on a pull request after
  activation, subject to Copilot plan availability and organization policies.
