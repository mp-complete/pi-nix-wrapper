{
  description = "A nix-wrapper-modules module for the Pi coding agent";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

    nix-wrapper-modules = {
      url = "github:BirdeeHub/nix-wrapper-modules";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    pi-nix = {
      url = "github:lukasl-dev/pi.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      nix-wrapper-modules,
      pi-nix,
      ...
    }:
    let
      inherit (nixpkgs) lib;
      systems = [
        "aarch64-darwin"
        "aarch64-linux"
        "x86_64-linux"
      ];
      forAllSystems = lib.genAttrs systems;

      module = ./wrapperModules/pi/module.nix;
      wrapper = nix-wrapper-modules.lib.evalModule module;

      mkPkgs =
        system:
        import nixpkgs {
          inherit system;
          overlays = [ pi-nix.overlays.default ];
        };
    in
    {
      # Supplies pkgs.pi-coding-agent, the module's default package.
      overlays.default = pi-nix.overlays.default;

      wrapperModules = {
        pi = module;
        default = self.wrapperModules.pi;
      };

      wrappers = {
        pi = wrapper.config;
        default = self.wrappers.pi;
      };

      packages = forAllSystems (
        system:
        let
          pkgs = mkPkgs system;
          package = wrapper.config.wrap { inherit pkgs; };
        in
        {
          pi = package;
          default = package;
        }
      );

      checks = forAllSystems (
        system:
        let
          pkgs = mkPkgs system;
          extension = pkgs.runCommand "pi-wrapper-smoke-extension" { } ''
            mkdir -p "$out"
            cat > "$out/package.json" <<'EOF'
            ${builtins.toJSON {
              name = "pi-wrapper-smoke-extension";
              version = "0.0.0";
              pi.extensions = [ "./index.js" ];
            }}
            EOF
            cat > "$out/index.js" <<'EOF'
            export default function () {}
            EOF
          '';
          prompt = pkgs.writeText "pi-wrapper-smoke-prompt" "Smoke test prompt.";
          skill = pkgs.writeText "pi-wrapper-smoke-skill.md" "# Smoke test skill";
          template = pkgs.writeText "pi-wrapper-smoke-template.md" "Smoke test template.";
          theme = pkgs.writeText "pi-wrapper-smoke-theme.json" (builtins.toJSON { name = "smoke"; });
          configured = wrapper.config.wrap {
            inherit pkgs;
            binName = "pi-smoke";
            extensions = [ extension ];
            skills = [ skill ];
            promptTemplates = [ template ];
            themes = [ theme ];
            appendSystemPrompts = [ prompt ];
            configDir = "$HOME/.config/pi smoke";
            sessionDir = "$HOME/.local/state/pi smoke/sessions";
          };
        in
        {
          inherit (self.packages.${system}) pi;

          configured = pkgs.runCommand "pi-wrapper-configured-smoke-test" { } ''
            test -x ${configured}/bin/pi-smoke
            test ! -e ${configured}/bin/pi

            grep -F -- '--extension ${extension}' ${configured}/bin/pi-smoke
            grep -F -- '--skill ${skill}' ${configured}/bin/pi-smoke
            grep -F -- '--prompt-template ${template}' ${configured}/bin/pi-smoke
            grep -F -- '--theme ${theme}' ${configured}/bin/pi-smoke
            grep -F -- '--append-system-prompt ${prompt}' ${configured}/bin/pi-smoke
            grep -F -- 'wrapperSetEnvDefault "PI_CODING_AGENT_DIR" "$HOME/.config/pi smoke"' ${configured}/bin/pi-smoke
            grep -F -- 'wrapperSetEnvDefault "PI_CODING_AGENT_SESSION_DIR" "$HOME/.local/state/pi smoke/sessions"' ${configured}/bin/pi-smoke

            export PI_CODING_AGENT_DIR="$TMPDIR/caller config"
            mkdir -p "$PI_CODING_AGENT_DIR"
            ${configured}/bin/pi-smoke list 2>&1 | grep -F 'No packages installed.'

            touch "$out"
          '';
        }
      );

      formatter = forAllSystems (system: (mkPkgs system).nixfmt-tree);
    };
}
