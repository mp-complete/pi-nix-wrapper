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
      projectLib = import ./lib { inherit lib; };

      mkPkgs =
        system:
        import nixpkgs {
          inherit system;
          overlays = [ pi-nix.overlays.default ];
        };

      mkExample =
        pkgs:
        let
          resources = projectLib.mkPiPackage {
            inherit pkgs;
            name = "pi-wrapper-example-resources";
            version = "0.1.0";
            extensions = [ ./examples/pi-demo/extensions/demo.js ];
            skills = [ ./examples/pi-demo/skills/demo ];
            prompts = [ ./examples/pi-demo/prompts/demo-review.md ];
            themes = [ ./examples/pi-demo/themes/demo.json ];
          };
        in
        wrapper.config.wrap {
          inherit pkgs;
          binName = "pi-example";
          piPackages = [ resources ];
          appendSystemPrompts = [ ./examples/pi-demo/wrapper-instructions.md ];
          resourceDiscovery = {
            extensions = false;
            skills = false;
            promptTemplates = false;
            themes = false;
          };
          useTheme = "pi-wrapper-demo";
        };
    in
    {
      # Supplies pkgs.pi-coding-agent, the module's default package.
      overlays.default = pi-nix.overlays.default;

      lib = projectLib;

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
          example = mkExample pkgs;
          default = package;
        }
      );

      checks = forAllSystems (
        system:
        let
          pkgs = mkPkgs system;
          packageExtension = pkgs.writeText "pi-wrapper-package-extension.js" ''
            export default function (pi) {
              pi.registerFlag("wrapper-smoke-package-loaded", {
                description: "Proves the wrapper smoke package loaded",
                type: "boolean",
                default: false,
              });
              pi.registerCommand("wrapper-smoke-resources", {
                description: "Reports whether packaged non-extension resources loaded",
                handler: async (_args, ctx) => {
                  const skills = ctx.getSystemPromptOptions().skills ?? [];
                  console.log(`wrapper-smoke-skill-loaded=''${skills.some((skill) => skill.name === "wrapper-smoke-skill")}`);
                  console.log(`agent-skills-bundle-loaded=''${skills.some((skill) => skill.name === "agent-skills-pi-review")}`);
                  const tools = pi.getAllTools().map((tool) => tool.name);
                  const commands = pi.getCommands().map((command) => command.name);
                  console.log(`builtin-mcp-loaded=''${commands.includes("mcp")}`);
                  console.log(`builtin-codemode-loaded=''${tools.includes("codemode")}`);
                  console.log(`builtin-tool-search-loaded=''${tools.includes("tool_search")}`);
                  console.log(`builtin-llama-loaded=''${commands.includes("llama")}`);
                  console.log(`active-tools=''${pi.getActiveTools().sort().join(",")}`);
                  ctx.shutdown();
                },
              });
            }
          '';
          packageSkill = pkgs.runCommand "pi-wrapper-package-skill" { } ''
            mkdir -p "$out"
            cat > "$out/SKILL.md" <<'EOF'
            ---
            name: wrapper-smoke-skill
            description: Tests package skill loading.
            ---

            # Wrapper smoke skill
            EOF
          '';
          packagePrompt = pkgs.writeText "pi-wrapper-package-prompt.md" "Wrapper smoke prompt.";
          agentSkillSource = pkgs.runCommand "agent-skills-pi-review" { } ''
            mkdir -p "$out"
            cat > "$out/SKILL.md" <<'EOF'
            ---
            name: agent-skills-pi-review
            description: Tests loading an agent-skills-nix bundle in Pi.
            ---

            # Agent Skills Pi review
            EOF
          '';
          agentSkillsPiBundle = pkgs.runCommand "agent-skills-bundle-pi" { } ''
            mkdir -p "$out/team"
            ln -s ${agentSkillSource} "$out/team/pi-review"
          '';
          agentSkillsBundle =
            pkgs.runCommand "agent-skills-bundle"
              {
                passthru.forTarget =
                  target: if target == "pi" then agentSkillsPiBundle else throw "unexpected target";
              }
              ''
                mkdir -p "$out"
              '';
          piPackage = projectLib.mkPiPackage {
            inherit pkgs;
            name = "pi-wrapper-smoke-package";
            version = "1.2.3";
            extensions = [ packageExtension ];
            skills = [ packageSkill ];
            prompts = [ packagePrompt ];
            themes = [ theme ];
          };
          extensionOne = pkgs.writeText "pi-wrapper-smoke-extension-one.js" "export default function () {}";
          extensionTwo = pkgs.writeText "pi-wrapper-smoke-extension-two.js" "export default function () {}";
          piExtensionSource = pkgs.runCommand "pi-wrapper-smoke-nix-extension" { } ''
            mkdir -p "$out"
            cat > "$out/index.js" <<'EOF'
            export default function (pi) {
              pi.registerFlag("wrapper-smoke-nix-extension-loaded", {
                description: "Proves the Nix extension helper loaded",
                type: "boolean",
                default: false,
              });
            }
            EOF
          '';
          piExtension = projectLib.mkPiExtension {
            inherit pkgs;
            src = piExtensionSource;
          };
          systemPrompt = pkgs.writeText "pi-wrapper-smoke-system-prompt" "Replacement prompt.";
          appendedPrompt = pkgs.writeText "pi-wrapper-smoke-appended-prompt" "Appended prompt.";
          skill = pkgs.writeText "pi-wrapper-smoke-skill.md" "# Smoke test skill";
          template = pkgs.writeText "pi-wrapper-smoke-template.md" "Smoke test template.";
          theme = pkgs.writeText "pi-wrapper-smoke-theme.json" (builtins.toJSON { name = "smoke"; });

          baseConfigured = wrapper.config.apply {
            inherit pkgs;
            imports = [
              {
                piPackages = [ piPackage ];
                extensions = [ extensionOne ];
              }
            ];
            skills = [
              skill
              (agentSkillsBundle.forTarget "pi")
            ];
          };
          configured = baseConfigured.wrap {
            binName = "pi-smoke";
            extensions = [
              extensionTwo
              piExtension
            ];
            promptTemplates = [ template ];
            themes = [ theme ];
            systemPrompt = systemPrompt;
            appendSystemPrompts = [ appendedPrompt ];
            resourceDiscovery = {
              extensions = false;
              skills = false;
              promptTemplates = false;
              themes = false;
              contextFiles = false;
            };
            configDir = "$HOME/.config/pi smoke";
            sessionDir = "$HOME/.local/state/pi smoke/sessions";
            builtinExtensions.llamaCpp = false;
            tools = {
              allow = [
                "read"
                "grep"
                "codemode"
                "tool_search"
              ];
              exclude = [ "grep" ];
              packages = [ pkgs.hello ];
            };
            useTheme = "smoke";
          };

          fakePi = pkgs.writeShellScriptBin "pi" ''
            printf '%s\n' "''${PI_CODING_AGENT_DIR-}|''${PI_CODING_AGENT_SESSION_DIR-}|$*"
          '';
          envPi = pkgs.writeShellScriptBin "pi" ''
            printf '%s\n' "''${PI_OFFLINE-unset}|''${PI_SKIP_VERSION_CHECK-unset}"
          '';
          onlineWrapper = wrapper.config.wrap {
            inherit pkgs;
            package = envPi;
            offline = false;
          };
          offlineWrapper = wrapper.config.wrap {
            inherit pkgs;
            package = envPi;
          };
          plainWrapper = wrapper.config.wrap {
            inherit pkgs;
            package = fakePi;
          };
          renamedWrapper = wrapper.config.wrap {
            inherit pkgs;
            package = fakePi;
            binName = "pi-work";
          };
          renamedPiDefaultWrapper = wrapper.config.wrap {
            inherit pkgs;
            package = fakePi;
            binName = "pi-work";
            configDir = null;
          };

          # A minimal stdio MCP server whose single tool is named after
          # $TOOLNAME or its first argument.
          mcpTestServer = pkgs.writeText "pi-wrapper-mcp-test-server.mjs" ''
            import { createInterface } from "node:readline";
            const name = process.env.TOOLNAME ?? process.argv[2];
            const send = (message) => process.stdout.write(JSON.stringify(message) + "\n");
            createInterface({ input: process.stdin }).on("line", (line) => {
              const message = JSON.parse(line);
              if (message.method === "initialize") {
                send({ jsonrpc: "2.0", id: message.id, result: {
                  protocolVersion: message.params.protocolVersion,
                  capabilities: { tools: {} },
                  serverInfo: { name, version: "1" },
                } });
              } else if (message.method === "tools/list") {
                send({ jsonrpc: "2.0", id: message.id, result: {
                  tools: [{ name: name + "_ping", description: "ping", inputSchema: { type: "object" } }],
                } });
              } else if (message.id !== undefined) {
                send({ jsonrpc: "2.0", id: message.id, result: {} });
              }
            });
          '';
          mcpProbe = pkgs.writeText "pi-wrapper-mcp-probe.js" ''
            export default function (pi) {
              pi.registerCommand("wrapper-smoke-mcp", {
                description: "Reports connected MCP tools",
                handler: async (_args, ctx) => {
                  const mcpTools = () => pi.getAllTools().map((tool) => tool.name).filter((name) => name.startsWith("mcp__")).sort();
                  for (let attempt = 0; attempt < 100 && mcpTools().length < 5; attempt++) {
                    await new Promise((resolve) => setTimeout(resolve, 100));
                  }
                  console.log(mcpTools().join("\n"));
                  ctx.shutdown();
                },
              });
            }
          '';
          mcpServer =
            name: extra:
            {
              command = "${pkgs.nodejs}/bin/node";
              args = [
                "${mcpTestServer}"
                name
              ];
              exposure = "direct";
            }
            // extra;
          mcpWrapper = wrapper.config.wrap {
            inherit pkgs;
            binName = "pi-mcp";
            extensions = [ mcpProbe ];
            resourceDiscovery = {
              extensions = false;
              skills = false;
              contextFiles = false;
            };
            mcpServers = {
              nix-declared = mcpServer "fromnix" { };
              secret-env = mcpServer "unused" { env.TOOLNAME = "\${SMOKE_TOOL_NAME}"; };
              secret-command = mcpServer "unused" { env.TOOLNAME = "!printf fromcommand"; };
              shadowed = mcpServer "nixshadow" { };
            };
          };
          dispatchWrapper = wrapper.config.wrap {
            inherit pkgs;
            package = fakePi;
            binName = "pi-dispatch";
            extensions = [ extensionOne ];
            configDir = "$HOME/default config";
            sessionDir = "$HOME/default sessions";
          };
          example = self.packages.${system}.example;
        in
        {
          inherit (self.packages.${system}) pi;

          extra-config-files = import ./tests/extra-config-files.nix {
            inherit pkgs lib wrapper;
          };

          pi-package =
            pkgs.runCommand "pi-wrapper-package-helper-test" { nativeBuildInputs = [ pkgs.jq ]; }
              ''
                jq -e '
                  .name == "pi-wrapper-smoke-package"
                  and .version == "1.2.3"
                  and .keywords == ["pi-package"]
                  and .pi.extensions == ["./extensions/0-pi-wrapper-package-extension.js"]
                  and .pi.skills == ["./skills/0-pi-wrapper-package-skill"]
                  and .pi.prompts == ["./prompts/0-pi-wrapper-package-prompt.md"]
                  and .pi.themes == ["./themes/0-pi-wrapper-smoke-theme.json"]
                ' ${piPackage}/package.json

                test "$(readlink ${piPackage}/extensions/0-pi-wrapper-package-extension.js)" = ${packageExtension}
                test "$(readlink ${piPackage}/skills/0-pi-wrapper-package-skill)" = ${packageSkill}
                test "$(readlink ${piPackage}/prompts/0-pi-wrapper-package-prompt.md)" = ${packagePrompt}
                test "$(readlink ${piPackage}/themes/0-pi-wrapper-smoke-theme.json)" = ${theme}

                touch "$out"
              '';

          pi-extension = pkgs.runCommand "pi-wrapper-extension-helper-test" { } ''
            test -L ${piExtension}
            test "$(readlink ${piExtension})" = ${piExtensionSource}/index.js
            test -f ${piExtension}
            touch "$out"
          '';

          example = pkgs.runCommand "pi-wrapper-example-smoke-test" { } ''
            script=${example}/bin/pi-example
            test -x "$script"
            test ! -e ${example}/bin/pi
            grep -F -- '--extension ' "$script"
            grep -F -- '--append-system-prompt ' "$script"
            grep -F -- '--no-extensions' "$script"
            grep -F -- '--no-skills' "$script"
            grep -F -- '--no-prompt-templates' "$script"
            grep -F -- '--no-themes' "$script"
            ! grep -F -- '--no-context-files' "$script"
            grep -F -- '--use-theme pi-wrapper-demo' "$script"
            # Built-in extensions survive --no-extensions.
            for builtin in mcp codemode tool-search llama.cpp; do
              grep -F -- "--extension builtin:$builtin" "$script"
            done

            export PI_CODING_AGENT_DIR="$TMPDIR/example config"
            export PI_CODING_AGENT_SESSION_DIR="$TMPDIR/example sessions"
            mkdir -p "$PI_CODING_AGENT_DIR" "$PI_CODING_AGENT_SESSION_DIR"

            "$script" --help > "$TMPDIR/help" 2>&1
            grep -F -- '--pi-wrapper-demo' "$TMPDIR/help"
            output="$($script --print /demo 2>&1)"
            printf '%s\n' "$output"
            test "$output" = 'pi-wrapper-demo-skill-loaded=true'

            touch "$out"
          '';

          configured = pkgs.runCommand "pi-wrapper-configured-smoke-test" { } ''
            script=${configured}/bin/pi-smoke
            test -x "$script"
            test ! -e ${configured}/bin/pi

            test "$(grep -Fc -- '--extension ${piPackage}' "$script")" -eq 1
            test "$(grep -Fc -- '--extension ${extensionOne}' "$script")" -eq 1
            test "$(grep -Fc -- '--extension ${extensionTwo}' "$script")" -eq 1
            test "$(grep -Fc -- '--extension ${piExtension}' "$script")" -eq 1
            grep -F -- '--skill ${skill}' "$script"
            grep -F -- '--skill ${agentSkillsPiBundle}' "$script"
            ! grep -F -- '--skill ${agentSkillsBundle}' "$script"
            grep -F -- '--prompt-template ${template}' "$script"
            grep -F -- '--theme ${theme}' "$script"
            grep -F -- '--system-prompt ${systemPrompt}' "$script"
            grep -F -- '--append-system-prompt ${appendedPrompt}' "$script"
            grep -F -- '--no-extensions' "$script"
            grep -F -- '--no-skills' "$script"
            grep -F -- '--no-prompt-templates' "$script"
            grep -F -- '--no-themes' "$script"
            grep -F -- '--no-context-files' "$script"
            grep -F -- '--extension builtin:mcp' "$script"
            grep -F -- '--extension builtin:codemode' "$script"
            grep -F -- '--extension builtin:tool-search' "$script"
            ! grep -F -- 'builtin:llama.cpp' "$script"
            grep -F -- '--tools read,grep,codemode,tool_search' "$script"
            grep -F -- '--exclude-tools grep' "$script"
            grep -F -- '--use-theme smoke' "$script"
            grep -F -- '${pkgs.hello}/bin' "$script"
            ! grep -F -- '--no-tools' "$script"
            ! grep -F -- '--no-builtin-tools' "$script"
            grep -F -- 'wrapperSetEnvDefault "PI_CODING_AGENT_DIR" "$HOME/.config/pi smoke"' "$script"
            grep -F -- 'wrapperSetEnvDefault "PI_CODING_AGENT_SESSION_DIR" "$HOME/.local/state/pi smoke/sessions"' "$script"

            ! grep -F -- '--no-' ${self.packages.${system}.pi}/bin/pi

            export PI_CODING_AGENT_DIR="$TMPDIR/caller config"
            export PI_CODING_AGENT_SESSION_DIR="$TMPDIR/caller sessions"
            mkdir -p "$PI_CODING_AGENT_DIR" "$PI_CODING_AGENT_SESSION_DIR"
            ${configured}/bin/pi-smoke list 2>&1 | grep -F 'No packages installed.'

            "$script" --help > "$TMPDIR/help" 2>&1
            grep -F -- '--wrapper-smoke-package-loaded' "$TMPDIR/help"
            grep -F -- '--wrapper-smoke-nix-extension-loaded' "$TMPDIR/help"
            resources="$($script --print /wrapper-smoke-resources 2>&1)"
            printf '%s\n' "$resources" > "$TMPDIR/resources"
            grep -Fx -- 'wrapper-smoke-skill-loaded=true' "$TMPDIR/resources"
            grep -Fx -- 'agent-skills-bundle-loaded=true' "$TMPDIR/resources"
            grep -Fx -- 'builtin-mcp-loaded=true' "$TMPDIR/resources"
            grep -Fx -- 'builtin-codemode-loaded=true' "$TMPDIR/resources"
            grep -Fx -- 'builtin-tool-search-loaded=true' "$TMPDIR/resources"
            grep -Fx -- 'builtin-llama-loaded=false' "$TMPDIR/resources"
            grep -Fx -- 'active-tools=codemode,read,tool_search' "$TMPDIR/resources"

            # The mcp subcommand bypasses injected session flags.
            "$script" mcp list --json > "$TMPDIR/mcp" 2>&1
            ! grep -F 'Unknown option' "$TMPDIR/mcp"

            touch "$out"
          '';

          dispatch = pkgs.runCommand "pi-wrapper-dispatch-smoke-test" { } ''
            script=${dispatchWrapper}/bin/pi-dispatch
            test -x "$script"

            export PI_CODING_AGENT_DIR="$TMPDIR/caller config"
            export PI_CODING_AGENT_SESSION_DIR="$TMPDIR/caller sessions"
            for command in auth config install list mcp remove uninstall update; do
              test "$("$script" "$command" marker)" = "$PI_CODING_AGENT_DIR|$PI_CODING_AGENT_SESSION_DIR|$command marker"
            done
            test "$("$script" marker)" = "$PI_CODING_AGENT_DIR|$PI_CODING_AGENT_SESSION_DIR|--extension ${extensionOne} marker"

            # Package and model-catalog updates pass through unchanged.
            for args in "--extensions" "--models" "--extension npm:pkg" "npm:pkg --force" "--help" "--all --help"; do
              test "$("$script" update $args)" = "$PI_CODING_AGENT_DIR|$PI_CODING_AGENT_SESSION_DIR|update $args"
            done
            # Updates that would replace the Nix-managed Pi are refused.
            for args in "" "--self" "self" "pi" "--all" "--force" "--extensions --self"; do
              if "$script" update $args > "$TMPDIR/stdout" 2> "$TMPDIR/stderr"; then
                echo "update $args was not refused" >&2
                exit 1
              fi
              test ! -s "$TMPDIR/stdout"
              grep -F 'pi-dispatch: Pi is managed by Nix; self-update is disabled.' "$TMPDIR/stderr"
            done

            unset PI_CODING_AGENT_DIR PI_CODING_AGENT_SESSION_DIR
            export HOME="$TMPDIR/home with spaces"
            test "$("$script" list)" = "$HOME/default config|$HOME/default sessions|list"

            touch "$out"
          '';

          environment = pkgs.runCommand "pi-wrapper-environment-smoke-test" { } ''
            test "$(${offlineWrapper}/bin/pi)" = "1|1"
            test "$(${onlineWrapper}/bin/pi)" = "unset|1"
            test "$(PI_SKIP_VERSION_CHECK= ${offlineWrapper}/bin/pi)" = "1|"

            # Each wrapper owns its agent directory: `pi` keeps Pi's default,
            # renamed wrappers default to an XDG state directory.
            export HOME="$TMPDIR/home with spaces"
            unset XDG_STATE_HOME PI_CODING_AGENT_DIR PI_CODING_AGENT_SESSION_DIR
            test "$(${plainWrapper}/bin/pi marker)" = "||marker"
            test "$(${renamedPiDefaultWrapper}/bin/pi-work marker)" = "||marker"
            test "$(${renamedWrapper}/bin/pi-work marker)" = "$HOME/.local/state/pi/pi-work||marker"
            test "$(XDG_STATE_HOME="$TMPDIR/state dir" ${renamedWrapper}/bin/pi-work marker)" = "$TMPDIR/state dir/pi/pi-work||marker"
            test "$(PI_CODING_AGENT_DIR=/caller ${renamedWrapper}/bin/pi-work marker)" = "/caller||marker"
            # Subcommands use the wrapper's own agent directory too.
            test "$(${renamedWrapper}/bin/pi-work list)" = "$HOME/.local/state/pi/pi-work||list"

            touch "$out"
          '';

          mcp = pkgs.runCommand "pi-wrapper-mcp-smoke-test" { } ''
            script=${mcpWrapper}/bin/pi-mcp
            export HOME="$TMPDIR"
            export PI_CODING_AGENT_DIR="$TMPDIR/agent"
            mkdir -p "$PI_CODING_AGENT_DIR"
            cd "$TMPDIR"

            # The wrapper never writes mcp.json; ad-hoc servers remain the user's.
            "$script" mcp add adhoc --exposure direct -- ${pkgs.nodejs}/bin/node ${mcpTestServer} adhoc
            "$script" mcp add shadowed --exposure direct -- ${pkgs.nodejs}/bin/node ${mcpTestServer} fileshadow
            "$script" mcp list > "$TMPDIR/list" 2>&1
            cat "$TMPDIR/list"
            grep -F 'adhoc: connected' "$TMPDIR/list"
            ! grep -F 'nix-declared' "$TMPDIR/list"

            SMOKE_TOOL_NAME=fromenv "$script" --print /wrapper-smoke-mcp > "$TMPDIR/tools" 2>&1
            cat "$TMPDIR/tools"
            # Nix-declared servers connect next to the ad-hoc server.
            grep -Fx 'mcp__nix_declared__fromnix_ping' "$TMPDIR/tools"
            grep -Fx 'mcp__adhoc__adhoc_ping' "$TMPDIR/tools"
            # Secrets resolve at runtime through environment and command interpolation.
            grep -Fx 'mcp__secret_env__fromenv_ping' "$TMPDIR/tools"
            grep -Fx 'mcp__secret_command__fromcommand_ping' "$TMPDIR/tools"
            # A same-name mcp.json server takes precedence over the Nix declaration.
            grep -Fx 'mcp__shadowed__fileshadow_ping' "$TMPDIR/tools"
            ! grep -F 'nixshadow' "$TMPDIR/tools"

            touch "$out"
          '';

          mcp-requires-builtin =
            assert
              !(builtins.tryEval
                (wrapper.config.wrap {
                  inherit pkgs;
                  resourceDiscovery.extensions = false;
                  builtinExtensions.mcp = false;
                  mcpServers.example.url = "https://example.invalid/mcp";
                }).outPath
              ).success;
            assert
              !(builtins.tryEval
                (wrapper.config.wrap {
                  inherit pkgs;
                  mcpServers."bad name".url = "https://example.invalid/mcp";
                }).outPath
              ).success;
            pkgs.runCommand "pi-wrapper-mcp-validation-test" { } "touch $out";

          version = pkgs.runCommand "pi-wrapper-version-test" { } ''
            export HOME="$TMPDIR"
            test "$(${self.packages.${system}.pi}/bin/pi --version)" = ${lib.escapeShellArg pkgs.pi-coding-agent.version}
            test ${lib.escapeShellArg pkgs.pi-coding-agent.version} = 1.0.0

            touch "$out"
          '';
        }
      );

      formatter = forAllSystems (system: (mkPkgs system).nixfmt-tree);
    };
}
