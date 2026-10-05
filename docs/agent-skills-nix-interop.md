# Research: `agent-skills-nix` interoperability with `pi-nix-wrapper`

## Summary

The authoritative project is [`Kyure-A/agent-skills-nix`](https://github.com/Kyure-A/agent-skills-nix), examined at revision [`dc122af897ab9a685c20ae54c639021619dbbb52`](https://github.com/Kyure-A/agent-skills-nix/tree/dc122af897ab9a685c20ae54c639021619dbbb52). Its `mkBundle` result is already a directory tree that Pi 0.84.4 accepts directly through one `--skill <directory>` argument. The narrowest interoperability API is therefore **no new wrapper option or adapter**: pass `bundle.forTarget "pi"` (or an unrestricted bundle) as one element of the existing `skills` list.

> [!NOTE]
> This research was performed against Pi 0.84.4. The flake now pins Pi 1.0.0, and the `configured` check still loads an `agent-skills-nix`-shaped bundle through `--skill` on that version. Pi 1.0.0 also discovers `~/.agents/skills` and project `.agents/skills` directly.

## Findings

### 1. Authoritative project and flake surface

The root flake exports:

- `packages.<system>.agent-skills-bundle` and `packages.<system>.default`;
- apps `skills-install`, `skills-install-local`, `skills-list`, and `skills-sources-lock`;
- `checks.<system>.skills`, `formatter.<system>`, `catalog`;
- `homeManagerModules.default`;
- `lib.agent-skills`.

The root package is intentionally built from an empty `defaultConfig`, so it is an empty bundle until a consumer constructs a catalog and selection. **Do not integrate `inputs.agent-skills.packages.${system}.default` expecting repository skills.** [Root flake](https://github.com/Kyure-A/agent-skills-nix/blob/dc122af897ab9a685c20ae54c639021619dbbb52/flake.nix) · [Default configuration](https://github.com/Kyure-A/agent-skills-nix/blob/dc122af897ab9a685c20ae54c639021619dbbb52/nix/default-config.nix) · [Documented outputs](https://github.com/Kyure-A/agent-skills-nix/blob/dc122af897ab9a685c20ae54c639021619dbbb52/README.md#flake-outputs)

`lib.agent-skills` publishes these relevant functions:

- discovery/selection: `discoverCatalog`, `allowlistFor`, `selectSkills`, `catalogJson`;
- building: `mkBundle`, `mkAgentPlugin`;
- targets/install: `bundlesForTargets`, `targetsFor`, `mkSyncProgram`, `mkLocalInstallProgram`, `mkShellHook` (plus compatibility script wrappers);
- source registry: `loadSourceManifests`, `sourcesFromLock`, `mkSourceLockProgram`.

The normal library pipeline is `sources -> discoverCatalog -> allowlistFor/selectSkills -> mkBundle`. [Library exports](https://github.com/Kyure-A/agent-skills-nix/blob/dc122af897ab9a685c20ae54c639021619dbbb52/lib/default.nix) · [Example](https://github.com/Kyure-A/agent-skills-nix/blob/dc122af897ab9a685c20ae54c639021619dbbb52/examples/library-functions/snippet.nix)

### 2. Source, builder, and module APIs

A source is a named attribute with either `path` or an input name in `input` (`path` wins), plus optional `subdir`, `idPrefix`, and `filter.{maxDepth,nameRegex}`. Discovery recursively finds directories containing `SKILL.md`; catalog IDs are relative paths with `/`, optionally prefixed. It rejects unsafe paths, unknown selections, and duplicate IDs. [Source implementation](https://github.com/Kyure-A/agent-skills-nix/blob/dc122af897ab9a685c20ae54c639021619dbbb52/lib/sources.nix)

`selectSkills` combines discovered `allowlist` entries with `skills` (the library name for explicit declarations). Explicit declarations support `from`, `path`, `rename`, `meta`, `agents`, `packages`, `rewriteCommands`, and `transform`; `rename` changes the output ID/path, while `agents` restricts named target bundles. [Selection implementation](https://github.com/Kyure-A/agent-skills-nix/blob/dc122af897ab9a685c20ae54c639021619dbbb52/lib/selection.nix)

`mkBundle { pkgs; selection; name ? "agent-skills-bundle"; }` returns a derivation with passthru members:

- `forTarget target`: a bundle containing unrestricted skills plus skills whose `agents` includes `target`;
- `hasTargetRestrictions`;
- `skillTargetNames`.

The Home Manager module exposes the same model as `programs.agent-skills`: `sources`, `skills.enable`, `skills.enableAll`, `skills.explicit`, `targets`, `catalog`, `bundlePath`, and read-only `targetBundlePaths`. Target structures are `link`, `symlink-tree`, or `copy-tree`; the built-in Pi target points globally at `$HOME/.pi/agent/skills` and locally at `.pi/skills`. [Common module options](https://github.com/Kyure-A/agent-skills-nix/blob/dc122af897ab9a685c20ae54c639021619dbbb52/modules/common.nix) · [Home Manager implementation](https://github.com/Kyure-A/agent-skills-nix/blob/dc122af897ab9a685c20ae54c639021619dbbb52/modules/home-manager/agent-skills.nix) · [Target table](https://github.com/Kyure-A/agent-skills-nix/blob/dc122af897ab9a685c20ae54c639021619dbbb52/README.md#default-target-paths)

### 3. Bundle filesystem layout

A full bundle has no manifest requirement and is rooted directly at skill IDs:

```text
$out/
├── simple-id -> /nix/store/...safe-source.../path/to/skill/
└── namespace/
    └── nested-id -> /nix/store/...safe-source.../other/skill/
        ├── SKILL.md
        └── ...payload
```

For an unmodified skill, the leaf is a symlink to its sanitized source directory. Internal source symlinks are retained only when their textual target stays within the declared source root; escaping and dangling links are removed. For a transformed skill or one with `packages`, the builder creates the leaf directory, writes a generated `SKILL.md`, symlinks other payload files, and adds package links (`./name` for one binary or `./package/` for a bin directory). A filtered `forTarget` bundle preserves the same relative IDs with links back into the full bundle. [Bundle implementation](https://github.com/Kyure-A/agent-skills-nix/blob/dc122af897ab9a685c20ae54c639021619dbbb52/lib/bundle.nix) · [Customization documentation](https://github.com/Kyure-A/agent-skills-nix/blob/dc122af897ab9a685c20ae54c639021619dbbb52/README.md#skill-customisation)

### 4. How skills are currently consumed

The observed consumer, [`/home/miles/src/nix-common/modules/agents/skills.nix`](../../nix-common/modules/agents/skills.nix), imports `homeManagerModules.default`, declares two path sources, selects named skills, and enables only the shared `agents` target with `structure = "link"` and `dest = ".agents/skills"`. It also exports `AGENTS_SKILLS_DIR`. Pi can discover that resulting `$HOME/.agents/skills` tree ambiently, but this is user-profile state rather than a hermetic wrapper input.

`agent-skills-nix` otherwise expects consumers either to use `programs.agent-skills.bundlePath`/`targetBundlePaths`, run its installers, or pass a library-built bundle to another consumer. [Home Manager bundle outputs](https://github.com/Kyure-A/agent-skills-nix/blob/dc122af897ab9a685c20ae54c639021619dbbb52/modules/common.nix) · [Apps usage](https://github.com/Kyure-A/agent-skills-nix/blob/dc122af897ab9a685c20ae54c639021619dbbb52/README.md#apps-usage)

### 5. Pi 0.84.4 `--skill` compatibility

Pi 0.84.4 declares `--skill <path>` as repeatable and accepts a Markdown file or directory. For an explicit directory:

1. If its root contains `SKILL.md`, Pi loads that skill and does **not** recurse below it.
2. Otherwise Pi loads qualifying direct root `*.md` files and recursively searches subdirectories for `SKILL.md`.
3. It follows file/directory symlinks, skips dot-directories and `node_modules`, and applies `.gitignore`, `.ignore`, and `.fdignore` rules.
4. A direct file must end in `.md`; a missing/non-Markdown path produces a warning.
5. `--no-skills` suppresses ambient discovery but explicit `--skill` paths still load.

Consequently, an `agent-skills-nix` bundle root works as-is: it normally has no root `SKILL.md`, nested slash-separated IDs are recursively discovered, and store symlinks are followed. [Pi skills documentation](https://github.com/earendil-works/pi/blob/v0.84.4/packages/coding-agent/docs/skills.md#locations) · [Pi loader implementation](https://github.com/earendil-works/pi/blob/v0.84.4/packages/coding-agent/src/core/skills.ts) · [CLI parser/help](https://github.com/earendil-works/pi/blob/v0.84.4/packages/coding-agent/src/cli/args.ts)

Pi requires a non-empty `description` to load a skill. Missing/invalid descriptions and malformed declared `SKILL.md` files warn and are skipped; most name-rule violations merely warn. Pi identifies collisions by the `name` in frontmatter (falling back to the parent directory), not by the bundle's catalog ID, and keeps the first loaded skill. [Pi validation and collision logic](https://github.com/earendil-works/pi/blob/v0.84.4/packages/coding-agent/src/core/skills.ts)

## Recommendation: use the existing `skills` path API

`pi-nix-wrapper` already turns every stringable `skills` element into a separate `--skill` flag. A bundle derivation is stringable, so adding an `agentSkillBundles` option, copying the tree, enumerating leaves, or generating a Pi package would duplicate behavior without improving compatibility. [Wrapper module](https://github.com/mp-complete/pi-nix-wrapper/blob/main/wrapperModules/pi/module.nix)

Prefer one explicit Pi-filtered bundle path and disable ambient skill discovery when reproducibility is desired:

```nix
{
  inputs.agent-skills = {
    url = "github:Kyure-A/agent-skills-nix/dc122af897ab9a685c20ae54c639021619dbbb52";
    inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = { nixpkgs, agent-skills, pi-nix-wrapper, ... }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs {
        inherit system;
        overlays = [ pi-nix-wrapper.overlays.default ];
      };
      skillLib = agent-skills.lib.agent-skills;
      sources = {
        team = {
          path = ./skills;
          # Optional catalog namespace; see collision caveat below.
          idPrefix = "team";
        };
      };
      catalog = skillLib.discoverCatalog sources;
      allowlist = skillLib.allowlistFor {
        inherit catalog sources;
        enable = [ "team/review" ];
      };
      selection = skillLib.selectSkills {
        inherit catalog sources allowlist;
        skills = { };
      };
      bundle = skillLib.mkBundle { inherit pkgs selection; };
    in {
      packages.${system}.default = pi-nix-wrapper.wrappers.pi.wrap {
        inherit pkgs;
        skills = [ (bundle.forTarget "pi") ];
        resourceDiscovery.skills = false;
      };
    };
}
```

Explicit declarations can carry Pi target restrictions and dependencies:

```nix
selection = skillLib.selectSkills {
  inherit catalog sources;
  skills.review = {
    from = "team";
    path = "review";
    agents = [ "pi" ];
    packages = [ pkgs.jq ];
  };
};

bundle = skillLib.mkBundle { inherit pkgs selection; };

# Existing wrapper API; one --skill flag for the whole recursive tree.
skills = [ (bundle.forTarget "pi") ];
```

If the Home Manager module already owns selection, `programs.agent-skills.targetBundlePaths.pi` is the corresponding Pi-filtered artifact when the `pi` target is enabled for the current system. Prefer constructing the bundle in shared flake logic when both Home Manager and wrapper outputs need it; extracting it from a Home Manager evaluation needlessly couples package construction to the user configuration.

## Edge cases and review findings

1. **High — frontmatter-name collisions survive ID namespacing.** `idPrefix = "openai"` can produce `openai/pdf` beside `anthropic/pdf`, but if both `SKILL.md` files declare `name: pdf`, Pi sees a collision and keeps only the first. `rename` alone only changes the output path. Select one, or use an explicit `transform` that changes frontmatter names to distinct valid Pi names.
2. **Medium — an enabled root flake package is still empty.** Build a consumer selection; do not pass `agent-skills.packages.${system}.default` unless an empty set is intended.
3. **Medium — ambient and explicit loading can overlap.** If the Home Manager `agents` target and wrapper bundle expose the same canonical files, Pi deduplicates exact real paths silently; copied/materialized variants can instead collide by name. Set `resourceDiscovery.skills = false` for a hermetic wrapper, or intentionally accept user/project precedence.
4. **Medium — transforms/dependency links make skills store-coupled.** This is appropriate for a Nix-wrapped Pi, but copying such a bundle outside its closure or exporting it as a portable plugin is unsafe. Ensure the wrapper closure retains the bundle (the generated `--skill` store path does).
5. **Low — direct `SKILL.md` is valid but changes scope.** Passing a leaf directory loads one skill and stops recursion; passing the bundle root loads all selected leaves. The recommended API passes the root once.
6. **Low — empty bundles are valid.** Pi scans them and loads nothing; this can hide a mistaken empty selection unless tested.
7. **Low — ignore files and hidden directories affect Pi's scan.** Bundle IDs placed beneath dot-directories will be skipped, and retained ignore files can suppress paths. Ordinary agent-skills IDs and sanitized roots avoid most cases, but unusual source trees should be smoke-tested.
8. **Low — Pi validates frontmatter later than `agent-skills-nix`.** The builder verifies `SKILL.md` exists but does not guarantee Pi's required non-empty `description`; malformed selected skills can build successfully and then be skipped with a runtime warning.

## Validation

The repository smoke check constructs the relevant `agent-skills-nix` output
shape: a target-filtered bundle containing a nested symlink to a skill root. It
passes that bundle through `skills`, disables ambient skill discovery, invokes
the pinned Pi 0.84.4 executable, and verifies the skill is loaded. The test
uses a synthetic bundle rather than importing `agent-skills-nix`, so upstream
API or layout changes still require review against the pinned source.

## Sources

- **Kept:** [`Kyure-A/agent-skills-nix` at `dc122af…`](https://github.com/Kyure-A/agent-skills-nix/tree/dc122af897ab9a685c20ae54c639021619dbbb52) — authoritative pinned repository and implementation.
- **Kept:** [Pi 0.84.4 skills documentation](https://github.com/earendil-works/pi/blob/v0.84.4/packages/coding-agent/docs/skills.md) and [loader source](https://github.com/earendil-works/pi/blob/v0.84.4/packages/coding-agent/src/core/skills.ts) — exact accepted CLI layout and runtime semantics.
- **Kept:** local `pi-nix-wrapper` [`wrapperModules/pi/module.nix`](../wrapperModules/pi/module.nix) — current integration surface.
- **Kept:** local `nix-common/modules/agents/skills.nix` — direct evidence of current consumer practice.
- **Dropped:** third-party tutorials/search summaries — unnecessary because pinned source and direct consumer configuration answer the question.

## Residual risks

Distinct catalog IDs can still collide when their `SKILL.md` files declare the
same frontmatter `name`; consumers must not rely on which collision wins. The
committed smoke check validates the compatible bundle shape rather than
instantiating the upstream project, so future `agent-skills-nix` changes should
be checked against its pinned implementation.
