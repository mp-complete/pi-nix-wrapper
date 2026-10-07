# `mkPiExtension` snippets and notes

## Downstream wrapper: load this skill from the flake input

A downstream consumer can make this skill available to Pi directly from the
flake input:

```nix
{
  inputs.pi-wrapper-modules.url = "github:mp-complete/pi-nix-wrapper";

  outputs =
    { nixpkgs, pi-wrapper-modules, ... }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs {
        inherit system;
        overlays = [ pi-wrapper-modules.overlays.default ];
      };
    in
    {
      packages.${system}.default = pi-wrapper-modules.wrappers.pi.wrap {
        inherit pkgs;
        skills = [ "${pi-wrapper-modules}/skills/mk-pi-extension" ];
      };
    };
}
```

Use `skills = [ "${pi-wrapper-modules}/skills" ];` instead if the consumer
wants every bundled skill from this repository.

## Local source example

Use this when the extension already exists in the repository or another local
source tree available to Nix:

```nix
localExtension = pi-wrapper-modules.lib.mkPiExtension {
  inherit pkgs;
  src = ./my-extension;
  entrypoint = "dist/index.js";
};
```

Notes:

- `entrypoint` defaults to `index.js`.
- `src` should point at the directory that contains the chosen entrypoint.
- If the entrypoint is a top-level `index.js`, omit `entrypoint`.

## npm package example

Use this when the extension is already published to npm and its packaged files
are ready to load directly:

```nix
npmExtension = pi-wrapper-modules.lib.mkPiExtension {
  inherit pkgs;
  npmPackage = "pi-btw";
  version = "0.7.1";
  hash = "sha512-XVHTwc6QNYHEXvdobqbUrlkvoEo/pq3pWgq4OPT/BMiyjZpjlhUW/aBO+NjFdyu1app9QL8kyGP+tsB18S1GqA==";
  entrypoint = "extensions/btw.ts";
};
```

The authoritative working example lives in `examples/pi-btw-extension/`.

## Wrapper usage example

Once created, the helper output plugs into the normal wrapper option:

```nix
packages.${system}.default = pi-wrapper-modules.wrappers.pi.wrap {
  inherit pkgs;
  extensions = [ npmExtension ];
};
```

If the consumer wants only declared extensions and no ambient discovery:

```nix
resourceDiscovery.extensions = false;
```

## Limitations

- `mkPiExtension` does **not** run `npm install`.
- It does **not** bundle transitive runtime dependencies.
- It is best for self-contained extensions, extensions that ship built output
  in the tarball, or extensions that depend only on Pi-provided peers.
- A plain local `.js` or `.ts` file does not need `mkPiExtension`; it can be
  passed to `extensions` directly.

## Authoritative files in this repo

- `lib/mkPiExtension.nix`
- `README.md`
- `examples/pi-btw-extension/flake.nix`
- `examples/pi-btw-extension/README.md`
