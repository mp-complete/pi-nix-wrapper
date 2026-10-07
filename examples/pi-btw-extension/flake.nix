{
  description = "Example: package the published pi-btw extension with Nix";

  inputs = {
    pi-nix-wrapper.url = "path:../..";
    nixpkgs.follows = "pi-nix-wrapper/nixpkgs";
  };

  outputs =
    {
      nixpkgs,
      pi-nix-wrapper,
      ...
    }:
    let
      systems = [ "x86_64-linux" ];
      forAllSystems = nixpkgs.lib.genAttrs systems;
      mkExample =
        system:
        let
          pkgs = import nixpkgs {
            inherit system;
            overlays = [ pi-nix-wrapper.overlays.default ];
          };
          extension = pi-nix-wrapper.lib.mkPiExtension {
            inherit pkgs;
            npmPackage = "pi-btw";
            version = "0.7.1";
            hash = "sha512-XVHTwc6QNYHEXvdobqbUrlkvoEo/pq3pWgq4OPT/BMiyjZpjlhUW/aBO+NjFdyu1app9QL8kyGP+tsB18S1GqA==";
            entrypoint = "extensions/btw.ts";
          };
          probe = pkgs.writeText "pi-btw-extension-probe.js" ''
            export default function (pi) {
              const loaded = pi.getCommands().some((command) => command.name === "btw");
              pi.registerCommand("real-extension-probe", {
                description: "Reports whether the npm extension loaded",
                handler: async (_args, ctx) => {
                  console.log(`pi-btw-extension-loaded=''${loaded}`);
                  ctx.shutdown();
                },
              });
            }
          '';
          wrapper = pi-nix-wrapper.wrappers.pi.wrap {
            inherit pkgs;
            binName = "pi-btw";
            extensions = [
              extension
              probe
            ];
            resourceDiscovery.extensions = false;
          };
          check = pkgs.runCommand "pi-btw-extension-smoke-test" { } ''
            export HOME="$TMPDIR/home"
            export PI_CODING_AGENT_DIR="$TMPDIR/agent"
            mkdir -p "$HOME" "$PI_CODING_AGENT_DIR"
            cd "$TMPDIR"

            output="$(${wrapper}/bin/pi-btw --print /real-extension-probe 2>&1)"
            printf '%s\n' "$output"
            grep -Fx -- "pi-btw-extension-loaded=true" <<< "$output"
            touch "$out"
          '';
        in
        {
          inherit wrapper check;
        };
    in
    {
      packages = forAllSystems (system: {
        default = (mkExample system).wrapper;
      });

      checks = forAllSystems (system: {
        pi-btw-extension = (mkExample system).check;
      });
    };
}
