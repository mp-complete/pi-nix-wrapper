{
  config,
  lib,
  pkgs,
  ...
}:
let
  jsonFormat = pkgs.formats.json { };
  names = lib.attrNames config.extraConfigFiles;
  validName =
    name:
    name != "" && lib.all (part: part != "" && part != "." && part != "..") (lib.splitString "/" name);
  invalidNames = lib.filter (name: !validName name) names;
  overlappingNames = lib.filter (name: lib.any (other: lib.hasPrefix "${name}/" other) names) names;
  entries = lib.mapAttrsToList (
    name: file:
    let
      inputs = lib.filter (value: value != null) [
        file.text
        file.json
        file.source
      ];
      source =
        if file.source != null then
          # Import literal absolute strings as well as Nix path values into the
          # store, while retaining dependency contexts on generated sources.
          if builtins.isString file.source && !(builtins.hasContext file.source) then
            /. + file.source
          else
            file.source
        else if file.text != null then
          pkgs.writeText "pi-extra-config-text" file.text
        else
          jsonFormat.generate "pi-extra-config.json" file.json;
    in
    lib.throwIf (lib.length inputs != 1)
      "pi wrapper: extraConfigFiles.${name} requires exactly one of text, json, or source."
      {
        inherit name;
        inherit (file) mode;
        source = "${source}";
      }
  ) config.extraConfigFiles;
  manifest = jsonFormat.generate "pi-extra-config-files.json" (
    lib.throwIf (invalidNames != [ ])
      "pi wrapper: extraConfigFiles names must be relative file paths without empty, '.' or '..' components: ${lib.concatStringsSep ", " invalidNames}"
      lib.throwIf
      (overlappingNames != [ ])
      "pi wrapper: extraConfigFiles paths overlap: ${lib.concatStringsSep ", " overlappingNames}"
      entries
  );
in
{
  options.extraConfigFiles = lib.mkOption {
    default = { };
    description = ''
      Additional files installed into the effective Pi agent directory before
      every invocation (including subcommands). Keys are relative file paths.
      Exactly one of `text`, `json`, or `source` must be non-null per file.
      Contents enter the Nix store: never include literal secrets.

      Files are writable copies, not store symlinks. Only declared files are
      touched; removing a declaration does not delete an installed file.
      No runtime JSON or Markdown merging is performed.
    '';
    type = lib.types.attrsOf (
      lib.types.submodule {
        options = {
          text = lib.mkOption {
            type = lib.types.nullOr lib.types.lines;
            default = null;
            description = ''
              Literal contents. Contributions from multiple modules concatenate;
              use `lib.mkBefore` and `lib.mkAfter` to control their order.
            '';
          };
          json = lib.mkOption {
            type = lib.types.nullOr jsonFormat.type;
            default = null;
            description = ''
              Non-null JSON contents expressed as Nix values. Contributions
              compose using the Nix JSON format's module merge semantics, not
              with any existing file on disk.
            '';
          };
          source = lib.mkOption {
            type = lib.types.nullOr lib.types.path;
            default = null;
            description = "Source file to copy verbatim into the agent directory.";
          };
          mode = lib.mkOption {
            type = lib.types.enum [
              "seed"
              "enforce"
            ];
            default = "seed";
            description = ''
              `seed` creates a file only if no directory entry exists at its
              destination. `enforce` atomically replaces the entire regular file
              on every launch. Symlinked parent directories are refused; enforce
              also refuses symlink and non-regular-file destinations. New and
              replaced files have mode 0600.

              Concurrent seeds never overwrite an existing entry. Concurrent
              enforcements use last-replacement-wins semantics; they do not lock
              against Pi or extension writers. Enforce only files whose entire
              contents Nix should own, not mutable settings you want to preserve.
            '';
          };
        };
      }
    );
  };

  # Environment setup precedes runShell. Run before the module's subcommand
  # dispatch, and do not start Pi if any installation fails.
  config.runShell = lib.mkIf (names != [ ]) (
    lib.mkBefore [
      ''
        ${pkgs.nodejs}/bin/node ${./extra-config-files.mjs} ${manifest} || exit "$?"
      ''
    ]
  );
}
