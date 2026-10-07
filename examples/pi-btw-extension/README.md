# Package a real Pi extension

This standalone flake demonstrates `lib.mkPiExtension` with the published
`pi-btw@0.7.1` npm package. It fetches the npm tarball with the package's
published SRI integrity hash, selects `extensions/btw.ts`, and loads it in the
Pi version pinned by `pi-nix-wrapper`. `pi-btw` has no runtime dependencies and
declares Pi APIs as peers.

Run the wrapper:

```console
nix run ./examples/pi-btw-extension
```

Run the smoke check that confirms `/btw` was registered:

```console
nix flake check ./examples/pi-btw-extension
```

The test probe is available as `/real-extension-probe` in print mode through
the flake check. `mkPiExtension` extracts the hashed package tarball but does
not install npm dependencies.
