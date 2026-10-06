# pi-nix-wrapper

A [`nix-wrapper-modules`](https://github.com/BirdeeHub/nix-wrapper-modules)
module for [Pi](https://pi.dev), a terminal coding agent.

> [!NOTE]
> This project is in its private bootstrap phase. The current implementation is
> a working foundation, but its public API is still provisional. See
> [the project intent and architecture](docs/intent.md) for goals, design
> constraints, proposed milestones, and open decisions.

The flake currently exports:

- `lib.mkPiPackage`: a local-resource Pi package assembler;
- `wrapperModules.pi`: the unevaluated, reusable wrapper module;
- `wrappers.pi`: the partially evaluated wrapper with `.wrap`, `.apply`, and
  `.eval`;
- `packages.<system>.pi`: a minimal wrapped Pi package;
- `packages.<system>.example`: a runnable, self-contained demonstration wrapper;
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

## Run the configured example

```console
nix run .#example
```

This starts `pi-example`, a self-contained demonstration built through the
public wrapper and `mkPiPackage` APIs. It includes an extension, skill, prompt
template, theme, and appended wrapper instructions. Run `/demo` inside Pi to
verify the extension and skill, or `/demo-review` to expand the bundled prompt.
See [`examples/pi-demo`](examples/pi-demo/) for the resources and details.

## Configure the wrapper

Apply the exported overlay to the package set passed to `.wrap`:

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

        piPackages = [ pkgs.my-pi-package ];
        extensions = [ pkgs.my-pi-extension ];
        skills = [ ./skills/review ];
        promptTemplates = [ ./prompts/review.md ];
        themes = [ ./themes/catppuccin.json ];
        useTheme = "catppuccin-mocha";
        systemPrompt = ./prompts/system.md;
        appendSystemPrompts = [ ./wrapper-instructions.md ];

        tools = {
          allow = [ "read" "bash" "edit" "write" "grep" "codemode" ];
          packages = [ pkgs.ripgrep pkgs.fd pkgs.jq ];
        };

        resourceDiscovery.contextFiles = false;

        configDir = "$HOME/.config/pi-work";
        sessionDir = "$HOME/.local/state/pi-work/sessions";
      };
    };
}
```

Additive resource options are lists and emit one command-line flag per item, so
list values compose naturally across module imports and repeated `.wrap` /
`.apply` calls. `systemPrompt` is singular because it replaces Pi's prompt.
Ambient discovery remains enabled by default; set individual
`resourceDiscovery` options to `false` for a more hermetic wrapper without
removing explicitly configured resources.

Pi's `--no-extensions` also disables its built-in extensions (`mcp`,
`codemode`, `tool-search`, and `llama.cpp`). When
`resourceDiscovery.extensions = false`, the wrapper therefore reloads each
enabled `builtinExtensions` entry with `--extension builtin:<name>`, so a
hermetic wrapper keeps MCP and codemode unless they are explicitly disabled.
Pi cannot disable one built-in from the command line while ambient discovery
is enabled, so that combination is an evaluation error.

`tools.allow`, `tools.exclude`, `tools.builtin`, and `tools.enable` map to
`--tools`, `--exclude-tools`, `--no-builtin-tools`, and `--no-tools`.
`tools.allow` replaces Pi's selection, so name every tool to enable; an empty
list disables all tools. `tools.packages` appends Nix packages to Pi's `PATH`
for the `bash` tool, `!` commands, extensions, and stdio MCP servers.

Pi is versioned by Nix, so the wrapper sets `PI_SKIP_VERSION_CHECK=1` and, by
default, `PI_OFFLINE=1` when the caller has not set them. Offline mode also
skips model-catalog refreshes, package update checks, automatic installation
of missing configured packages, and bug-report uploads. To avoid silent no-op
`pi update --extensions`, `pi update <source>`, and `pi update --models`
commands, the wrapper refuses those explicit updates while `PI_OFFLINE` is
set; use `offline = false` to restore them. Pi treats any non-empty
`PI_OFFLINE` as offline in some code paths, so exporting `PI_OFFLINE=0` is
not a reliable override.

Each wrapper owns its own agent directory, so wrappers never share settings,
credentials, trust decisions, MCP configuration, installed packages, or
sessions. A wrapper named `pi` keeps Pi's default `~/.pi/agent`; a renamed
wrapper defaults `configDir` to
`${XDG_STATE_HOME:-$HOME/.local/state}/pi/<binName>`. Set `configDir = null`
to use Pi's default directory regardless of the name. Logging in once per
wrapper is the intended cost of this isolation.

`configDir` and `sessionDir` are quoted, runtime-expanded strings. This permits
values such as `$HOME` and paths containing spaces, while an explicitly
exported environment variable still wins. Shell expansion is intentional, so
only use trusted Nix configuration values. These semantics require the default
`nix` wrapper implementation; the module fixes that backend accordingly.

Pi's subcommands (`install`, `remove`, `uninstall`, `update`, `list`,
`config`, `auth`, and `mcp`) must be the first argument and reject injected
session flags. The generated wrapper therefore runs them without injected
resource flags, while retaining configured environment variables.

The wrapper refuses `update` invocations that would self-update Pi: no target,
`self`, `pi`, `--self`, or `--all`. Update the Nix input that provides Pi
instead. Package and model-catalog updates (`update --extensions`,
`update <source>`, `update --models`) pass through only when `PI_OFFLINE` is
unset; `--help` always passes through.

## MCP servers

`mcpServers` declares MCP servers for every session. Each value has the shape
of an `mcpServers` entry in Pi's `mcp.json`:

```nix
mcpServers = {
  enghub = {
    url = "https://example.com/mcp";
    description = "Engineering documentation search";
  };
  github = {
    url = "https://api.githubcopilot.com/mcp/";
    headers.Authorization = "!echo Bearer $(gh auth token)";
  };
};
```

The wrapper loads a generated extension that registers these servers with
`pi.registerMcpServer()` on every load. It never writes `mcp.json`, so
servers added ad hoc with `pi mcp add` stay in the user's writable file and
connect next to the declared ones. A server of the same name in `mcp.json`
takes precedence, which also allows a per-machine override such as
`"enabled": false`.

- Secrets: values are stored in the Nix store. Use Pi's runtime interpolation
  (`${NAME}` or a leading `!command`) in `env`, `headers`, and
  `oauth.clientSecret`, never literal secrets.
- Authentication: declared HTTP servers use the same connection and sign-in
  code as `mcp.json` servers: OAuth, pre-registered OAuth clients, headers,
  and `auth.provider`. Sign in with `/mcp` inside a session. Tokens are
  stored in the wrapper's agent directory.
- Shell `pi mcp list` and `pi mcp login` do not load extensions and therefore
  do not show declared servers. `/mcp` enable and exposure changes to declared
  servers last for the current session.
- The built-in `mcp` extension must remain enabled.

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
| `piPackages` | list of stringable values | Load complete package roots with repeated `--extension` |
| `extensions` | list of stringable values | Repeat `--extension` |
| `skills` | list of stringable values | Repeat `--skill` |
| `promptTemplates` | list of stringable values | Repeat `--prompt-template` |
| `themes` | list of stringable values | Repeat `--theme` |
| `useTheme` | null or string | Select the initial theme with `--use-theme` |
| `systemPrompt` | null or stringable value | Set the singular `--system-prompt` replacement |
| `appendSystemPrompts` | list of stringable values | Repeat `--append-system-prompt` |
| `resourceDiscovery.extensions` | boolean | Toggle ambient extension discovery |
| `resourceDiscovery.skills` | boolean | Toggle ambient skill discovery |
| `resourceDiscovery.promptTemplates` | boolean | Toggle ambient prompt-template discovery |
| `resourceDiscovery.themes` | boolean | Toggle ambient theme discovery |
| `resourceDiscovery.contextFiles` | boolean | Toggle `AGENTS.md` and `CLAUDE.md` discovery |
| `builtinExtensions.{mcp,codemode,toolSearch,llamaCpp}` | boolean | Keep built-ins when extension discovery is disabled |
| `tools.enable` | boolean | `false` emits `--no-tools` |
| `tools.builtin` | boolean | `false` emits `--no-builtin-tools` |
| `tools.allow` | null or list of strings | Set the `--tools` allowlist |
| `tools.exclude` | list of strings | Set `--exclude-tools` |
| `tools.packages` | list of packages | Append executables to `PATH` |
| `offline` | boolean (default `true`) | Set `PI_OFFLINE=1` if unset |
| `mcpServers` | attribute set of JSON values | Register MCP servers through a generated extension |
| `configDir` | null or string | Set `PI_CODING_AGENT_DIR` if unset; defaults per wrapper name |
| `sessionDir` | null or string | Set `PI_CODING_AGENT_SESSION_DIR` if unset |

This module intentionally models resource paths, appended system prompts, and
state directories rather than Pi's entire CLI. Generic options from
`wlib.modules.default` remain available as escape hatches, including `package`,
`binName`, `runtimePkgs`, `env`, `envDefault`, and `flags`.

## Assemble a local Pi package

`lib.mkPiPackage` creates a package root with a generated `package.json` and
symlinks to resources already available to Nix:

```nix
myPiPackage = pi-wrapper-modules.lib.mkPiPackage {
  inherit pkgs;
  name = "my-pi-resources";
  version = "1.0.0"; # Optional; defaults to 0.0.0.
  extensions = [ ./extensions/review.ts ];
  skills = [ ./skills/review ];
  prompts = [ ./prompts/review.md ];
  themes = [ ./themes/catppuccin.json ];
};
```

Each source is linked under its conventional resource directory and listed
explicitly in the generated manifest. Sources may be individual resources or
directories accepted by Pi. This helper only assembles local resources; it does
not install npm dependencies or replace a dedicated npm package builder.

Pass the result through `piPackages` to load the complete manifest:

```nix
packages.${system}.default = pi-wrapper-modules.wrappers.pi.wrap {
  inherit pkgs;
  piPackages = [ myPiPackage ];
};
```

## Use agent-skills-nix bundles

[`agent-skills-nix`](https://github.com/Kyure-A/agent-skills-nix)
`mkBundle` outputs already have a layout Pi accepts recursively. No conversion or
copying is required: pass the Pi-filtered bundle through the existing `skills`
option.

```nix
skillBundle = inputs.agent-skills.lib.agent-skills.mkBundle {
  inherit pkgs selection;
};

packages.${system}.default = pi-wrapper-modules.wrappers.pi.wrap {
  inherit pkgs;
  skills = [ (skillBundle.forTarget "pi") ];

  # Optional: use only the pinned bundle, not ~/.pi or project skills.
  resourceDiscovery.skills = false;
};
```

Build `selection` from your configured sources with `discoverCatalog`,
`allowlistFor`, and `selectSkills`; the default package exported by
`agent-skills-nix` has an intentionally empty selection. Calling `forTarget
"pi"` preserves per-skill `agents` restrictions while retaining unrestricted
skills. A Home Manager configuration that enables the `pi` target can instead
pass `config.programs.agent-skills.targetBundlePaths.pi`.

See [the interoperability notes](docs/agent-skills-nix-interop.md) for a full
selection example and collision considerations.

## Validate

```console
nix fmt
nix flake check -L
```
