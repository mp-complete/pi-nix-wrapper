# pi-wrapper-modules

A [`nix-wrapper-modules`](https://github.com/BirdeeHub/nix-wrapper-modules)
module for [Pi](https://pi.dev), a terminal coding agent.

The flake exports:

- `wrapperModules.pi`: the unevaluated, reusable wrapper module;
- `wrappers.pi`: the partially evaluated wrapper with `.wrap`, `.apply`, and
  `.eval`;
- `packages.<system>.pi`: a minimal wrapped Pi package;
- `overlays.default`: the `pi-nix` overlay that supplies
  `pkgs.pi-coding-agent`.

## Run the minimal package

```console
nix run .
```

The default package deliberately adds no resources or opinionated command-line
tools. Pi continues to use its normal user and project configuration. Package,
check, and formatter outputs are published for `aarch64-darwin`,
`aarch64-linux`, and `x86_64-linux`.

## Configure the wrapper

Apply the exported overlay to the package set passed to `.wrap`:

```nix
{
  inputs.pi-wrapper-modules.url = "github:YOUR-ORG/pi-wrapper-modules";

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

        extensions = [ pkgs.my-pi-extension ];
        skills = [ ./skills/review ];
        promptTemplates = [ ./prompts/review.md ];
        themes = [ ./themes/catppuccin.json ];
        appendSystemPrompts = [ ./AGENTS.md ];

        configDir = "$HOME/.config/pi-work";
        sessionDir = "$HOME/.local/state/pi-work/sessions";
      };
    };
}
```

All resource options are lists and emit one command-line flag per item, so list
values compose naturally across repeated `.wrap` / `.apply` calls.

`configDir` and `sessionDir` are quoted, runtime-expanded strings. This permits
values such as `$HOME` and paths containing spaces, while an explicitly
exported environment variable still wins. Shell expansion is intentional, so
only use trusted Nix configuration values. These semantics require the default
`nix` wrapper implementation; the module fixes that backend accordingly.

Pi's package-management subcommands (`install`, `remove`, `uninstall`, `update`,
`list`, `config`, and `auth`) must be the first argument. The generated wrapper
therefore runs them without injected resource flags, while retaining configured
environment variables.

## Import the module

The unevaluated form can be imported into another wrapper definition:

```nix
flake.wrappers.pi-work = {
  imports = [ inputs.pi-wrapper-modules.wrapperModules.pi ];
  appendSystemPrompts = [ ./AGENTS.md ];
};
```

The consuming package set must contain `pkgs.pi-coding-agent`, normally by
applying `overlays.default`. Alternatively, override the inherited `package`
option when wrapping.

## Options

| Option | Type | Purpose |
| --- | --- | --- |
| `extensions` | list of stringable values | Repeat `--extension` |
| `skills` | list of stringable values | Repeat `--skill` |
| `promptTemplates` | list of stringable values | Repeat `--prompt-template` |
| `themes` | list of stringable values | Repeat `--theme` |
| `appendSystemPrompts` | list of stringable values | Repeat `--append-system-prompt` |
| `configDir` | null or string | Set `PI_CODING_AGENT_DIR` if unset |
| `sessionDir` | null or string | Set `PI_CODING_AGENT_SESSION_DIR` if unset |

This module intentionally models resource paths, appended system prompts, and
state directories rather than Pi's entire CLI. Generic options from
`wlib.modules.default` remain available as escape hatches, including `package`,
`binName`, `runtimePkgs`, `env`, `envDefault`, and `flags`.

## Validate

```console
nix fmt
nix flake check -L
```
