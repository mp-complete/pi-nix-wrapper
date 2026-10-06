{
  config,
  lib,
  pkgs,
  wlib,
  ...
}:
let
  repeatFlag = values: {
    ifs = null;
    data = map toString values;
  };

  # Pi's built-in extensions, keyed by option name. `--no-extensions` disables
  # all of them, so they are re-enabled explicitly with `--extension builtin:*`.
  builtinExtensionNames = {
    mcp = "mcp";
    codemode = "codemode";
    toolSearch = "tool-search";
    llamaCpp = "llama.cpp";
  };
  enabledBuiltinExtensions = lib.mapAttrsToList (_: name: "builtin:${name}") (
    lib.filterAttrs (option: _: config.builtinExtensions.${option}) builtinExtensionNames
  );
  disabledBuiltinExtensions = lib.attrNames (
    lib.filterAttrs (_: enabled: !enabled) config.builtinExtensions
  );
  builtinExtensionFlags =
    if config.resourceDiscovery.extensions then
      lib.throwIf (disabledBuiltinExtensions != [ ]) ''
        pi wrapper: builtinExtensions.{${lib.concatStringsSep "," disabledBuiltinExtensions}} = false
        requires resourceDiscovery.extensions = false. Pi cannot disable an
        individual built-in extension from the command line while ambient
        extension discovery is enabled; use `"-builtin:<name>"` in the
        `extensions` setting instead.
      '' [ ]
    else
      enabledBuiltinExtensions;

  commaFlag = values: lib.mkIf (values != [ ]) (lib.concatStringsSep "," (lib.unique values));

  jsonFormat = pkgs.formats.json { };

  isStringAttrs = value: builtins.isAttrs value && lib.all builtins.isString (lib.attrValues value);
  isStringList = value: builtins.isList value && lib.all builtins.isString value;
  isPositiveNumber = value: (builtins.isInt value || builtins.isFloat value) && value > 0;

  mcpServerNames = lib.attrNames config.mcpServers;
  invalidMcpServerNames = lib.filter (
    name: builtins.match "[A-Za-z0-9_-]+" name == null
  ) mcpServerNames;
  mcpNamespace = name: lib.replaceStrings [ "-" ] [ "_" ] name;
  clashingMcpServerNames = lib.filter (
    name: lib.length (lib.filter (other: mcpNamespace other == mcpNamespace name) mcpServerNames) > 1
  ) mcpServerNames;
  mcpServerProblems =
    server:
    if !builtins.isAttrs server then
      [ "must be an attribute set" ]
    else
      let
        hasCommand = builtins.hasAttr "command" server;
        hasUrl = builtins.hasAttr "url" server;
      in
      lib.concatLists [
        (lib.optional (!hasCommand && !hasUrl) "must set exactly one of `command` or `url`")
        (lib.optional (hasCommand && hasUrl) "must not set both `command` and `url`")
        (lib.optional (hasCommand && !builtins.isString server.command) "`command` must be a string")
        (lib.optional (hasUrl && !builtins.isString server.url) "`url` must be a string")
        (lib.optional (builtins.hasAttr "args" server && !isStringList server.args) "`args` must be a list of strings")
        (lib.optional (builtins.hasAttr "env" server && !isStringAttrs server.env) "`env` must be an attribute set of strings")
        (lib.optional (builtins.hasAttr "headers" server && !isStringAttrs server.headers) "`headers` must be an attribute set of strings")
        (lib.optional (builtins.hasAttr "cwd" server && !builtins.isString server.cwd) "`cwd` must be a string")
        (lib.optional (builtins.hasAttr "description" server && !builtins.isString server.description) "`description` must be a string")
        (lib.optional (builtins.hasAttr "exposure" server && !builtins.isString server.exposure) "`exposure` must be a string")
        (lib.optional (builtins.hasAttr "toolExposure" server && !builtins.isString server.toolExposure) "`toolExposure` must be a string")
        (lib.optional (builtins.hasAttr "enabled" server && !builtins.isBool server.enabled) "`enabled` must be a boolean")
        (lib.optional (builtins.hasAttr "timeout" server && !isPositiveNumber server.timeout) "`timeout` must be a positive number")
        (lib.optional (builtins.hasAttr "oauth" server && !builtins.isAttrs server.oauth) "`oauth` must be an attribute set")
        (lib.optional (builtins.hasAttr "auth" server && !builtins.isAttrs server.auth) "`auth` must be an attribute set")
        (lib.optional (builtins.hasAttr "oauth" server && builtins.isAttrs server.oauth && builtins.hasAttr "clientSecret" server.oauth && !builtins.isString server.oauth.clientSecret) "`oauth.clientSecret` must be a string")
        (lib.optional (builtins.hasAttr "auth" server && builtins.isAttrs server.auth && builtins.hasAttr "provider" server.auth && !builtins.isString server.auth.provider) "`auth.provider` must be a string")
        (lib.concatMap (
          field:
          lib.optional (hasUrl && builtins.hasAttr field server) "`${field}` is only valid with `command` transports"
        ) [ "args" "env" "cwd" ])
        (lib.concatMap (
          field:
          lib.optional (hasCommand && builtins.hasAttr field server) "`${field}` is only valid with `url` transports"
        ) [ "headers" "oauth" "auth" ])
      ];
  invalidMcpServers = lib.filter (entry: entry != null) (
    lib.mapAttrsToList (
      name: server:
      let
        problems = mcpServerProblems server;
      in
      if problems == [ ] then
        null
      else
        "${name}: ${lib.concatStringsSep "; " problems}"
    ) config.mcpServers
  );

  # Nix-declared MCP servers are registered by a generated extension rather
  # than written to mcp.json, so the wrapper never writes Pi's state at launch
  # and `pi mcp add` keeps owning the writable mcp.json. A server of the same
  # name in mcp.json takes precedence over these registrations.
  mcpServersExtension = pkgs.writeTextDir "pi-wrapper-mcp-servers/index.js" ''
    // Generated by pi-nix-wrapper from the `mcpServers` option.
    const servers = ${builtins.toJSON config.mcpServers};

    export default function (pi) {
      const failures = [];
      for (const [name, server] of Object.entries(servers)) {
        try {
          pi.registerMcpServer(name, server);
        } catch (error) {
          failures.push(`''${name}: ''${error instanceof Error ? error.message : String(error)}`);
        }
      }
      if (failures.length > 0) {
        throw new Error(`pi wrapper: failed to register mcpServers:\n''${failures.join("\n")}`);
      }
    }
  '';
  mcpServerExtensionPaths =
    if config.mcpServers == { } then
      [ ]
    else
      lib.throwIf (invalidMcpServerNames != [ ])
        ''
          pi wrapper: invalid mcpServers name(s): ${lib.concatStringsSep ", " invalidMcpServerNames}.
          MCP server names may contain only letters, digits, `_`, and `-`.
        ''
        lib.throwIf
        (clashingMcpServerNames != [ ])
        ''
          pi wrapper: mcpServers names ${lib.concatStringsSep ", " clashingMcpServerNames} differ only
          in `-` and `_`; Pi treats them as the same server.
        ''
        lib.throwIf
        (!config.builtinExtensions.mcp)
        ''
          pi wrapper: mcpServers requires builtinExtensions.mcp = true. Pi's built-in
          MCP extension connects servers registered by other extensions.
        ''
        lib.throwIf
        (invalidMcpServers != [ ])
        ''
          pi wrapper: invalid mcpServers entries:
          ${lib.concatMapStringsSep "\n" (entry: "  - ${entry}") invalidMcpServers}
        ''
        [ "${mcpServersExtension}/pi-wrapper-mcp-servers" ];
in
{
  imports = [ wlib.modules.default ];

  options = {
    piPackages = lib.mkOption {
      type = lib.types.listOf wlib.types.stringable;
      default = [ ];
      description = ''
        Complete Pi package roots to load. Each value is passed through a
        separate {option}`--extension` flag so Pi can read its package
        manifest.
      '';
      example = lib.literalExpression "[ pkgs.pi-subagents-package ]";
    };

    extensions = lib.mkOption {
      type = lib.types.listOf wlib.types.stringable;
      default = [ ];
      description = ''
        Pi extensions to load. Each value is passed through a separate
        {option}`--extension` flag.
      '';
      example = lib.literalExpression "[ pkgs.my-pi-extension ./extension.ts ]";
    };

    skills = lib.mkOption {
      type = lib.types.listOf wlib.types.stringable;
      default = [ ];
      description = ''
        Pi skills to load. Each value is passed through a separate
        {option}`--skill` flag.
      '';
      example = lib.literalExpression "[ ./skills/code-review ]";
    };

    promptTemplates = lib.mkOption {
      type = lib.types.listOf wlib.types.stringable;
      default = [ ];
      description = ''
        Pi prompt templates to load. Each value is passed through a separate
        {option}`--prompt-template` flag.
      '';
      example = lib.literalExpression "[ ./prompts/review.md ]";
    };

    themes = lib.mkOption {
      type = lib.types.listOf wlib.types.stringable;
      default = [ ];
      description = ''
        Pi themes to load. Each value is passed through a separate
        {option}`--theme` flag.
      '';
      example = lib.literalExpression "[ ./themes/catppuccin.json ]";
    };

    systemPrompt = lib.mkOption {
      type = lib.types.nullOr wlib.types.stringable;
      default = null;
      description = ''
        Text or a file that replaces Pi's default system prompt through
        {option}`--system-prompt`. Pi reads the value as a file when it names
        an existing path.
      '';
      example = lib.literalExpression "./system-prompt.md";
    };

    appendSystemPrompts = lib.mkOption {
      type = lib.types.listOf wlib.types.stringable;
      default = [ ];
      description = ''
        Text or files to append to Pi's system prompt. Each value is passed
        through a separate {option}`--append-system-prompt` flag. Pi reads a
        value as a file when it names an existing path.
      '';
      example = lib.literalExpression ''[ ./AGENTS.md "Prefer small changes." ]'';
    };

    resourceDiscovery = lib.mkOption {
      default = { };
      description = ''
        Controls Pi's ambient resource discovery. Explicitly configured
        resources are still passed when their corresponding discovery option
        is disabled.
      '';
      type = lib.types.submodule {
        options = {
          extensions = lib.mkOption {
            type = lib.types.bool;
            default = true;
            description = "Whether Pi discovers extensions from ambient configuration.";
          };
          skills = lib.mkOption {
            type = lib.types.bool;
            default = true;
            description = "Whether Pi discovers and loads ambient skills.";
          };
          promptTemplates = lib.mkOption {
            type = lib.types.bool;
            default = true;
            description = "Whether Pi discovers and loads ambient prompt templates.";
          };
          themes = lib.mkOption {
            type = lib.types.bool;
            default = true;
            description = "Whether Pi discovers and loads ambient themes.";
          };
          contextFiles = lib.mkOption {
            type = lib.types.bool;
            default = true;
            description = "Whether Pi discovers and loads AGENTS.md and CLAUDE.md files.";
          };
        };
      };
    };

    builtinExtensions = lib.mkOption {
      default = { };
      description = ''
        Pi's built-in extensions. Pi loads all of them by default, but
        {option}`--no-extensions` also disables them. When
        {option}`resourceDiscovery.extensions` is `false`, each enabled
        built-in is loaded again explicitly through
        {option}`--extension builtin:<name>`. Disabling an individual
        built-in therefore requires disabling ambient extension discovery.
      '';
      type = lib.types.submodule {
        options = lib.mapAttrs (
          _: name:
          lib.mkOption {
            type = lib.types.bool;
            default = true;
            description = "Whether to load Pi's built-in `${name}` extension.";
          }
        ) builtinExtensionNames;
      };
    };

    tools = lib.mkOption {
      default = { };
      description = ''
        Tool selection for the model and Nix-provided executables for the
        tools to run.
      '';
      type = lib.types.submodule {
        options = {
          enable = lib.mkOption {
            type = lib.types.bool;
            default = true;
            description = ''
              Whether any tools start enabled. `false` passes
              {option}`--no-tools`, disabling built-in, extension, and custom
              tools.
            '';
          };
          builtin = lib.mkOption {
            type = lib.types.bool;
            default = true;
            description = ''
              Whether Pi's default built-in tools start enabled. `false`
              passes {option}`--no-builtin-tools` while retaining extension
              and custom tools. An explicit {option}`tools.allow` entry may
              still name a built-in tool to enable it.
            '';
          };
          allow = lib.mkOption {
            type = lib.types.nullOr (lib.types.listOf lib.types.str);
            default = null;
            example = [
              "read"
              "grep"
              "find"
              "ls"
            ];
            description = ''
              Exact allowlist of tool names passed through {option}`--tools`.
              It replaces Pi's default selection and the `defaultTools`
              setting, so list every tool to enable, including `codemode` or
              `tool_search`. `null` keeps Pi's normal selection.
            '';
          };
          exclude = lib.mkOption {
            type = lib.types.listOf lib.types.str;
            default = [ ];
            example = [ "write" ];
            description = ''
              Tool names disabled through {option}`--exclude-tools` after all
              other selection options.
            '';
          };
          packages = lib.mkOption {
            type = lib.types.listOf lib.types.package;
            default = [ ];
            example = lib.literalExpression "[ pkgs.ripgrep pkgs.fd pkgs.jq ]";
            description = ''
              Packages whose executables are appended to Pi's {env}`PATH`.
              They are available to the `bash` tool, `!` commands,
              extensions, and stdio MCP servers. The caller's {env}`PATH`
              takes precedence; use the generic `runtimePkgs` option with
              `prefix = true` to prefer a Nix-provided executable.
            '';
          };
        };
      };
    };

    mcpServers = lib.mkOption {
      type = lib.types.attrsOf jsonFormat.type;
      default = { };
      example = lib.literalExpression ''
        {
          enghub = {
            url = "https://example.com/mcp";
            description = "Engineering documentation search";
          };
          github = {
            url = "https://api.githubcopilot.com/mcp/";
            headers.Authorization = "!echo Bearer $(gh auth token)";
            exposure = "deferred";
          };
        }
      '';
      description = ''
        MCP servers registered for every session through a generated extension
        that calls `pi.registerMcpServer()`. Values are validated during Nix
        evaluation for the transport shape and common field types. Each value
        has the shape of an `mcpServers` entry in Pi's `mcp.json`: `command`,
        `args`, `env`, and `cwd` for stdio servers; `url`, `headers`, `oauth`,
        and `auth` for HTTP servers; plus `exposure`, `toolExposure`,
        `description`, `enabled`, and `timeout`.

        The wrapper never writes `mcp.json`, so servers added with
        `pi mcp add` remain the user's. A server of the same name in `mcp.json`
        takes precedence, which also allows a local override such as
        `"enabled": false`.

        Values are stored in the Nix store. Supply secrets through Pi's
        runtime interpolation, `''${NAME}` or a leading `!command`, never as
        literal values. OAuth servers sign in through `/mcp` inside a session;
        the shell `pi mcp` commands do not load extensions and therefore do
        not list these servers. `/mcp` enable and exposure changes to these
        servers last for the current session only.
      '';
    };

    useTheme = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "light/dark";
      description = ''
        Initial interactive theme passed through {option}`--use-theme`. Use
        `light/dark` form to follow the terminal appearance. The saved
        `theme` setting is not changed.
      '';
    };

    offline = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Set {env}`PI_OFFLINE` unless the caller already set it. Pi then skips
        automatic network activity: model-catalog refreshes, package update
        checks, automatic installation of missing configured packages, and
        bug-report uploads. Pi and its bundled model catalog are updated
        through Nix instead.

        Pi treats any non-empty {env}`PI_OFFLINE` as offline in some code
        paths, so set this option to `false` rather than exporting
        `PI_OFFLINE=0`.
      '';
    };

    configDir = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default =
        if config.binName == "pi" then
          null
        else
          "\${XDG_STATE_HOME:-$HOME/.local/state}/pi/${config.binName}";
      defaultText = lib.literalExpression ''
        if binName == "pi" then null
        else "\''${XDG_STATE_HOME:-$HOME/.local/state}/pi/''${binName}"
      '';
      example = "$HOME/.config/pi-work";
      description = ''
        Pi's agent directory, set through {env}`PI_CODING_AGENT_DIR`. It holds
        settings, credentials, trust decisions, MCP configuration, installed
        packages, and (unless {option}`sessionDir` is set) sessions.

        Each wrapper owns its own agent directory so that wrappers never share
        mutable state. A wrapper named `pi` keeps Pi's default `~/.pi/agent`
        (`null`); a renamed wrapper defaults to
        `''${XDG_STATE_HOME:-$HOME/.local/state}/pi/<binName>`. Set `null` to
        use Pi's default directory regardless of the name.

        The value is expanded by the wrapper at runtime, so shell variables
        such as {env}`$HOME` are supported. An environment variable set by the
        caller takes precedence.
      '';
    };

    sessionDir = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "$HOME/.local/state/pi/sessions";
      description = ''
        Override Pi's session directory with
        {env}`PI_CODING_AGENT_SESSION_DIR`. The value is expanded by the
        wrapper at runtime, so shell variables such as {env}`$HOME` are
        supported. An environment variable set by the caller takes
        precedence.
      '';
    };
  };

  config = {
    package = lib.mkDefault pkgs.pi-coding-agent;

    flags = lib.throwIf (!config.tools.enable && config.tools.allow != null && config.tools.allow != [ ]) ''
      pi wrapper: tools.enable = false conflicts with a non-empty tools.allow.
      Remove the allowlist or set tools.enable = true.
    '' {
      "--extension" = repeatFlag (
        config.piPackages ++ config.extensions ++ mcpServerExtensionPaths ++ builtinExtensionFlags
      );
      "--skill" = repeatFlag config.skills;
      "--prompt-template" = repeatFlag config.promptTemplates;
      "--theme" = repeatFlag config.themes;
      "--system-prompt" = lib.mkIf (config.systemPrompt != null) (toString config.systemPrompt);
      "--append-system-prompt" = repeatFlag config.appendSystemPrompts;
      "--no-extensions" = !config.resourceDiscovery.extensions;
      "--no-skills" = !config.resourceDiscovery.skills;
      "--no-prompt-templates" = !config.resourceDiscovery.promptTemplates;
      "--no-themes" = !config.resourceDiscovery.themes;
      "--no-context-files" = !config.resourceDiscovery.contextFiles;
      "--no-tools" = !config.tools.enable || config.tools.allow == [ ];
      "--no-builtin-tools" = !config.tools.builtin;
      "--tools" = lib.mkIf (config.tools.enable && config.tools.allow != null && config.tools.allow != [ ]) (
        lib.concatStringsSep "," (lib.unique config.tools.allow)
      );
      "--exclude-tools" = commaFlag config.tools.exclude;
      "--use-theme" = lib.mkIf (config.useTheme != null) config.useTheme;
    };

    runtimePkgs = config.tools.packages;

    envDefault = {
      # Pi is versioned by Nix, so upstream release notices are not actionable.
      PI_SKIP_VERSION_CHECK = "1";
      PI_OFFLINE = lib.mkIf config.offline "1";
      PI_CODING_AGENT_DIR = lib.mkIf (config.configDir != null) {
        data = config.configDir;
        esc-fn = wlib.escapeShellArgWithEnv;
      };
      PI_CODING_AGENT_SESSION_DIR = lib.mkIf (config.sessionDir != null) {
        data = config.sessionDir;
        esc-fn = wlib.escapeShellArgWithEnv;
      };
    };

    # Pi recognizes its subcommands only when they are the first argument and
    # rejects session flags such as --extension. Bypass the injected flags for
    # those commands while retaining the environment setup emitted above.
    #
    # Pi itself is versioned by Nix, so `pi update` targets that would
    # self-update Pi (no target, self, pi, --self, --all) are refused. Package
    # and model-catalog updates remain available.
    runShell = [
      ''
        case "''${1-}" in
          update)
            pi_wrapper_target=
            pi_wrapper_self=
            pi_wrapper_help=
            pi_wrapper_expect_value=
            for pi_wrapper_arg in "''${@:2}"; do
              if [ -n "$pi_wrapper_expect_value" ]; then
                pi_wrapper_expect_value=
                pi_wrapper_target=1
                continue
              fi
              case "$pi_wrapper_arg" in
                -h | --help) pi_wrapper_help=1 ;;
                --self | --all | self | pi) pi_wrapper_self=1 ;;
                --extension) pi_wrapper_expect_value=1 ;;
                --extension=* | --extensions | --models) pi_wrapper_target=1 ;;
                -*) ;;
                *) pi_wrapper_target=1 ;;
              esac
            done
            if [ -z "$pi_wrapper_help" ] && { [ -n "$pi_wrapper_self" ] || [ -z "$pi_wrapper_target" ]; }; then
              printf '%s\n' \
                "''${0##*/}: Pi is managed by Nix; self-update is disabled." \
                "Update the Nix input that provides Pi instead." \
                "To update Pi packages, run: ''${0##*/} update --extensions" >&2
              exit 1
            fi
            exec ${lib.escapeShellArg config.wrapperPaths.input} "$@"
            ;;
          auth | config | install | list | mcp | remove | uninstall)
            exec ${lib.escapeShellArg config.wrapperPaths.input} "$@"
            ;;
        esac
      ''
    ];

    # The subcommand dispatch and runtime-expanded directory values require a
    # shell wrapper. The binary and makeWrapper backends cannot preserve these
    # module semantics.
    wrapperImplementation = lib.mkForce "nix";

    # Renamed wrappers should expose only the requested executable.
    filesToExclude = lib.mkIf (config.binName != baseNameOf config.exePath) [ config.exePath ];

    meta.description = ''
      Wrap Pi with declarative package, extension, skill, prompt-template,
      theme, tool, system-prompt, resource-discovery, and state-directory
      configuration.
    '';
  };
}
