---
name: mk-pi-extension
description: Explain how to package and load a Pi extension with pi-nix-wrapper's lib.mkPiExtension, including local source and hash-pinned npm tarball flows. Use when the user asks about mkPiExtension, Nix-packaged Pi extensions, or loading an extension through this wrapper.
metadata:
  author: pi-nix-wrapper
  version: "1.0"
---

# Use `lib.mkPiExtension`

Use this skill when the task is about packaging a Pi extension for this wrapper.
Choose the smallest viable path, explain the helper's constraints up front, and
prefer copyable Nix snippets.

## Procedure

1. Identify which source mode the user needs.
   - **Local source tree:** use `src = ./path-to-extension;` and optionally set
     `entrypoint` when the file is not `index.js`.
   - **Published npm package:** use `npmPackage`, `version`, `hash`, and
     `entrypoint`.
   - **Single local `.js` or `.ts` file:** do **not** require
     `mkPiExtension`; passing the file directly to `extensions` is simpler.

2. Explain the helper contract clearly.
   - Exactly one of `src` or `npmPackage` is allowed.
   - `entrypoint` must be a relative path inside the source tree; it cannot
     contain empty segments, `.` segments, or `..`.
   - In npm mode, `version` and the npm tarball's SRI `hash` are required.
   - The result is a Nix-store path pointing at the chosen extension entry
     file, suitable for the wrapper's existing `extensions` option.

3. Call out the main limitation before recommending the helper.
   - `mkPiExtension` extracts the selected npm tarball but does **not** install
     npm dependencies.
   - Prefer it only for extensions that are already bundled, dependency-free,
     or rely on Pi-provided peer dependencies.
   - If the extension needs an npm install step or dependency closure work,
     say that `mkPiExtension` alone is insufficient.

4. Give a minimal wrapper example.
   - Show the `mkPiExtension` call.
   - Show it being passed into `extensions = [ myExtension ];`.
   - If the user wants a hermetic wrapper, mention
     `resourceDiscovery.extensions = false;`.

5. Point to the canonical in-repo examples when helpful.
   - `README.md` contains the basic `mkPiExtension` snippet.
   - `examples/pi-btw-extension/` shows a real npm-backed extension.
   - `lib/mkPiExtension.nix` is the authoritative behavior for validation and
     limitations.

## Recommended response patterns

### Local source tree

```nix
myExtension = pi-wrapper-modules.lib.mkPiExtension {
  inherit pkgs;
  src = ./my-extension;
  entrypoint = "dist/index.js";
};

extensions = [ myExtension ];
```

### Published npm package

```nix
myExtension = pi-wrapper-modules.lib.mkPiExtension {
  inherit pkgs;
  npmPackage = "my-pi-extension";
  version = "1.0.0";
  hash = "sha512-...";
  entrypoint = "dist/index.js";
};

extensions = [ myExtension ];
```

### Plain local file

```nix
extensions = [ ./extensions/review.ts ];
```

## What to emphasize

- `mkPiExtension` is a packaging helper, not a build system.
- The wrapper treats its output like any other extension path.
- The npm `hash` should come from the package's published integrity value.
- When debugging, verify that the selected `entrypoint` actually exists inside
  the local source tree or extracted tarball.

## References

- [`references/snippets.md`](references/snippets.md) — copyable examples,
  limitations, and downstream-consumer guidance.
