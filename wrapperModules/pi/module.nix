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
in
{
  imports = [ wlib.modules.default ];

  options = {
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

    configDir = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "$HOME/.config/pi";
      description = ''
        Override Pi's configuration directory with
        {env}`PI_CODING_AGENT_DIR`. The value is expanded by the wrapper at
        runtime, so shell variables such as {env}`$HOME` are supported. An
        environment variable set by the caller takes precedence.
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

    flags = {
      "--extension" = repeatFlag config.extensions;
      "--skill" = repeatFlag config.skills;
      "--prompt-template" = repeatFlag config.promptTemplates;
      "--theme" = repeatFlag config.themes;
      "--append-system-prompt" = repeatFlag config.appendSystemPrompts;
    };

    envDefault = {
      PI_CODING_AGENT_DIR = lib.mkIf (config.configDir != null) {
        data = config.configDir;
        esc-fn = wlib.escapeShellArgWithEnv;
      };
      PI_CODING_AGENT_SESSION_DIR = lib.mkIf (config.sessionDir != null) {
        data = config.sessionDir;
        esc-fn = wlib.escapeShellArgWithEnv;
      };
    };

    # Pi recognizes package-management subcommands only when they are the
    # first argument. Bypass resource flags for those commands while retaining
    # the environment setup emitted above.
    runShell = [
      ''
        case "''${1-}" in
          auth | config | install | list | remove | uninstall | update)
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
      Wrap Pi with declarative extension, skill, prompt-template, theme,
      system-prompt, and state-directory configuration.
    '';
  };
}
