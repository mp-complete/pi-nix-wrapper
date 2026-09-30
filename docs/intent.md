# Project intent and architecture

## Purpose

`pi-nix-wrapper` provides a reusable
[`nix-wrapper-modules`](https://nix-community.github.io/nix-wrapper-modules/md/intro.html)
module for [Pi](https://pi.dev). It should make Pi configurations portable as
ordinary Nix derivations without requiring NixOS or Home Manager activation and
without replacing a user's project configuration.

The intended result is a small set of primitives from which consumers can build
multiple opinionated Pi executables—for example `pi`, `pi-work`, and a headless
`pi-agent`—while sharing a common base.

This repository is private while its API and package-building strategy are
being established.

## Goals

1. Model Pi's configuration primitives declaratively, including extensions,
   Pi package roots, skills, prompt templates, themes, system-prompt additions,
   and eventually the files in Pi's agent directory.
2. Build wrappers that carry immutable extensions and other resources in their
   Nix closure.
3. Allow one Pi wrapper configuration to extend another without creating nested
   shell wrappers.
4. Preserve Pi's normal user and project configuration unless a consumer
   explicitly chooses stricter behavior.
5. Provide helpers for assembling local resources into valid Pi packages.
6. Eventually expose reproducibly built packages from the
   [Pi package catalog](https://pi.dev/packages), with unsupported packages
   reported honestly rather than silently producing incomplete derivations.

## Non-goals

- Do not put credentials or unencrypted secrets in the Nix store.
- Do not make NixOS or Home Manager activation a prerequisite for using a
  configured Pi.
- Do not point Pi's complete agent directory at the immutable Nix store: that
  directory also contains mutable authentication, settings, package state, and
  other runtime data.
- Do not model wrapper inheritance by setting `package` to an already wrapped
  Pi derivation. Composition should remain in the module graph.
- Do not claim that unpacking an npm tarball is sufficient to package every Pi
  extension. Runtime dependencies, patches, native components, and platform
  restrictions must be handled explicitly.

## Pi configuration facts that shape the design

Pi has two importantly different classes of configuration.

### Immutable invocation resources

Pi accepts repeatable command-line paths for:

- extensions and complete Pi package roots via `--extension`;
- skills via `--skill`;
- prompt templates via `--prompt-template`;
- themes via `--theme`;
- appended system-prompt content via `--append-system-prompt`.

It also accepts one replacement system prompt via `--system-prompt`. These
options are a good fit for Nix because store paths are immutable and list-valued
module options compose naturally.

Package-management commands must remain the first argument. The generated
wrapper therefore needs to bypass injected resource flags for commands such as
`install`, `remove`, `uninstall`, `update`, `list`, `config`, and `auth`, while
retaining applicable environment setup.

### Writable agent-directory state

Pi's agent directory contains `settings.json`, `models.json`,
`keybindings.json`, `auth.json`, package state, conventional resource
directories, and global context files such as `AGENTS.md`. It is selected with
`PI_CODING_AGENT_DIR` and must remain writable for normal interactive use.

A file passed to `--append-system-prompt` is not semantically identical to an
`AGENTS.md` context file. Real context files participate in directory discovery,
precedence, and `AGENTS.override.md` behavior. The public API should not call an
appended prompt an `AGENTS.md` installation.

A future managed-state layer must state ownership per file rather than hide
several behaviors behind one vague option:

- **seed**: create a file only when it does not exist;
- **merge**: preserve mutable content while reasserting declarative keys;
- **enforce**: replace the complete file with the declarative version.

Any runtime reconciler must use atomic writes and define malformed-JSON,
permissions, concurrency, and precedence behavior. Authentication remains
outside declarative Nix data.

## Proposed public API

The stable first layer should look like this:

```nix
{
  imports = [ inputs.pi-nix-wrapper.wrapperModules.pi ];

  piPackages = [ pkgs.pi-subagents-package ];
  extensions = [ ./extensions/review.ts ];
  skills = [ ./skills/nix-review ];
  promptTemplates = [ ./prompts/review.md ];
  themes = [ ./themes/catppuccin.json ];

  systemPrompt = null;
  appendSystemPrompts = [
    ./wrapper-instructions.md
    "Prefer focused changes."
  ];

  # Additive by default. Disable selected ambient discovery for a hermetic
  # wrapper while retaining the explicitly configured paths above.
  resourceDiscovery = {
    extensions = true;
    skills = true;
    promptTemplates = true;
    themes = true;
    contextFiles = true;
  };

  configDir = "$HOME/.config/pi-work";
  sessionDir = "$HOME/.local/state/pi-work/sessions";
}
```

`piPackages` and `extensions` both eventually emit `--extension`, but separate
names communicate whether a value is a complete Pi package root or an
individual extension. List options are additive. `systemPrompt` is singular
because replacement is non-additive. Ambient discovery remains enabled by
default; `resourceDiscovery` maps explicit `false` values to Pi's `--no-*`
flags for consumers that need a closed resource set. Context-file discovery is
controlled separately because disabling it changes real `AGENTS.md` semantics.

Raw `nix-wrapper-modules` options such as `package`, `binName`, `runtimePkgs`,
`env`, `envDefault`, and `flags` remain available as escape hatches.

## Wrapper composition

Wrappers should depend on one another through module imports:

```nix
wrapperModules.pi-base = { pkgs, ... }: {
  imports = [ inputs.pi-nix-wrapper.wrapperModules.pi ];
  piPackages = [ pkgs.pi-subagents-package ];
  appendSystemPrompts = [ ./shared-instructions.md ];
};

wrapperModules.pi-work = {
  imports = [ self.wrapperModules.pi-base ];
  binName = "pi-work";
  appendSystemPrompts = [ ./work-instructions.md ];
};
```

An evaluated wrapper can also be extended with the standard
`nix-wrapper-modules` interface:

```nix
workPi = self.wrappers.pi-base.wrap {
  binName = "pi-work";
  appendSystemPrompts = [ ./work-instructions.md ];
};
```

Both forms should re-evaluate one flattened module configuration rather than
execute one generated wrapper from another.

## Pi package helpers

The first helper should have deliberately narrow scope:

```nix
myPiPackage = inputs.pi-nix-wrapper.lib.mkPiPackage {
  inherit pkgs;
  name = "my-pi-resources";
  extensions = [ ./extensions ];
  skills = [ ./skills ];
  prompts = [ ./prompts ];
  themes = [ ./themes ];
};
```

It should create a stable Pi package root, generate `package.json`, and link
resources already available to Nix. A separate future `buildNpmPiPackage`
interface can address npm sources and their dependency closures. Keeping these
builders separate avoids overstating what a simple resource assembler can do.

Pi identifies CLI-loaded packages partly through paths visible at runtime.
Store-hashed derivation names can produce poor display names, so wrappers may
need a stable `linkFarm` entry per package, following the technique proven in
the predecessor configuration.

## Package catalog direction

The Pi package gallery is an npm-keyword-driven, changing catalog rather than a
Nix package set. At the time of initial research it exposed about 58 package
pages. Complete coverage is a separate milestone:

1. establish `mkPiPackage` for local resources;
2. define `buildNpmPiPackage` with an explicit source and dependency strategy;
3. generate and commit pinned catalog metadata and hashes;
4. expose supported entries under `packages.<system>.piPackages` or an
   equivalent discoverable namespace;
5. record unsupported packages and reasons such as missing lockfiles, native
   dependencies, required patches, or unsupported platforms;
6. add an update/check workflow so catalog drift is visible.

A curated registry can use simple, vendored, and bespoke build shapes similar
to the existing predecessor registry. Fully automatic packaging should only be
claimed after dependency closure and runtime loading are validated.

## Milestones

### Milestone 1: immutable wrapper primitives

- retain the working wrapper-module foundation;
- add `piPackages` and singular `systemPrompt` options;
- verify complete Pi package roots on the pinned Pi version;
- add opt-in controls for ambient resource and context-file discovery;
- prove additive composition through imports and repeated `.wrap`/`.apply`;
- add the local-resource `mkPiPackage` helper;
- document flattened inheritance and mutable-state boundaries;
- test renamed executables and package-command dispatch.

### Milestone 2: managed writable configuration

- decide whether each supported agent-directory file is seeded, merged, or
  enforced;
- add settings, models, keybindings, and real global context-file support;
- preserve mutable auth, sessions, and user package state;
- add atomicity, concurrency, malformed-file, and permission tests.

The recommended boundary is to complete Milestone 1 before adding a runtime
state reconciler. This remains a product decision until explicitly approved.

### Milestone 3: package registry

- implement npm package builders;
- migrate reusable extension definitions from the predecessor configuration;
- generate pinned gallery metadata;
- expand coverage with runtime smoke tests and platform metadata.

## Validation contract

At minimum, checks should prove:

- the default wrapper runs without taking over user configuration;
- every configured resource produces the correct repeated flag;
- a Pi package manifest can load more than one resource kind;
- package-management subcommands remain first and usable;
- list options accumulate through module imports and `.wrap`;
- a renamed wrapper exposes only its requested executable;
- runtime-expanded state paths handle spaces and allow caller overrides;
- generated package roots have stable names and valid manifests;
- all behavior is exercised against the Pi package pinned by this flake.

Use `nix fmt` and `nix flake check -L` as the repository-level gate, plus
focused runtime smoke tests where network access or credentials are not needed.

## Current state and version context

The repository already contains a provisional wrapper module and smoke checks.
They currently pass `nix flake check -L` on `x86_64-linux`. This is a starting
point, not a commitment to the final API.

The current `pi.nix` input builds Pi 0.84.4, while the ambient Pi documentation
used during initial research was from 0.87.1. New behavior must be checked
against the pinned executable. The pinned `pi.nix` project is also useful prior
art: it merges declarative settings into a writable `settings.json` on launch
but only seeds `models.json` when absent, demonstrating why per-file policy must
be explicit.

Primary references:

- [Pi configuration](https://pi.dev/docs/configuration)
- [Pi settings](https://pi.dev/docs/settings)
- [Pi packages](https://pi.dev/docs/packages)
- [Pi command line](https://pi.dev/docs/cli)
- [nix-wrapper-modules introduction](https://nix-community.github.io/nix-wrapper-modules/md/intro.html)
- [pi.nix](https://github.com/lukasl-dev/pi.nix)
