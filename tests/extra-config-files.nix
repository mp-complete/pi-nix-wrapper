{
  pkgs,
  lib,
  wrapper,
}:
let
  source = pkgs.writeText "pi-config-source" "copied verbatim\n";
  fakePi = pkgs.writeShellScriptBin "pi" ''
    printf 'pi-started:%s\n' "$*"
  '';
  base = wrapper.config.apply {
    inherit pkgs;
    package = fakePi;
    extraConfigFiles = {
      "AGENTS.md" = {
        text = lib.mkBefore "Shared instructions.";
        mode = "enforce";
      };
      "extension.json".json = {
        enabled = true;
        nested.shared = 1;
        items = [ "first" ];
      };
    };
  };
  configured = base.wrap {
    binName = "pi-files";
    configDir = "$HOME/config with spaces";
    extraConfigFiles = {
      "AGENTS.md".text = lib.mkAfter "Work instructions.";
      "extension.json".json = {
        nested.work = 2;
        items = lib.mkAfter [ "second" ];
      };
      "nested dir/source.txt" = { inherit source; };
      "nested dir/enforced.json" = {
        json = {
          value = 42;
        };
        mode = "enforce";
      };
      "literal ' $ file".text = "not shell-expanded";
      "empty.txt".text = "";
      "local.txt".source = ./fixtures/extra-config-source.txt;
      "local-string.txt".source = toString ./fixtures/extra-config-source.txt;
    };
  };
  plain = wrapper.config.wrap {
    inherit pkgs;
    package = fakePi;
    extraConfigFiles."default.txt".text = "default";
  };
  renamed = plain.wrap { binName = "pi-renamed"; };
  realPi = wrapper.config.wrap {
    inherit pkgs;
    extraConfigFiles = {
      "settings.json".json.theme = "dark";
      "AGENTS.md" = {
        text = "Managed global context.";
        mode = "enforce";
      };
    };
  };
  localExtension = pkgs.writeText "pi-config-test-extension.js" "export default function () {}";
  invalid =
    files:
    !(builtins.tryEval
      (wrapper.config.wrap {
        inherit pkgs;
        package = fakePi;
        extraConfigFiles = files;
      }).outPath
    ).success;
in
assert lib.all invalid [
  { "missing.txt" = { }; }
  {
    "both.txt" = {
      text = "text";
      json = { };
    };
  }
  {
    "both.txt" = {
      text = "text";
      inherit source;
    };
  }
  {
    "both.json" = {
      json = { };
      inherit source;
    };
  }
  {
    "bad-mode.txt" = {
      text = "text";
      mode = "merge";
    };
  }
  { "/absolute".text = "text"; }
  { "../escape".text = "text"; }
  { "nested/../escape".text = "text"; }
  { "nested/./file".text = "text"; }
  { "nested//file".text = "text"; }
  { "nested/".text = "text"; }
  { "".text = "text"; }
  {
    "overlap".text = "text";
    "overlap/file".text = "text";
  }
];
pkgs.runCommand "pi-wrapper-extra-config-files-test" { } ''
  ${pkgs.nodejs}/bin/node ${./extra-config-files.test.mjs} \
    ${configured}/bin/pi-files ${plain}/bin/pi ${renamed}/bin/pi-renamed
  # Pi's own package manager must be able to update the seeded settings file.
  export HOME="$TMPDIR/real-home"
  export PI_CODING_AGENT_DIR="$TMPDIR/real-agent"
  cd "$TMPDIR"
  ${realPi}/bin/pi install ${localExtension}
  ${pkgs.jq}/bin/jq -e '.theme == "dark" and (.packages | length == 1)' "$PI_CODING_AGENT_DIR/settings.json"
  ${realPi}/bin/pi --help > "$TMPDIR/help"
  ${pkgs.jq}/bin/jq -e '.packages | length == 1' "$PI_CODING_AGENT_DIR/settings.json"
  ${realPi}/bin/pi remove ${localExtension}
  ${pkgs.jq}/bin/jq -e '.theme == "dark" and (.packages | length == 0)' "$PI_CODING_AGENT_DIR/settings.json"
  grep -Fx 'Managed global context.' "$PI_CODING_AGENT_DIR/AGENTS.md"
  touch "$out"
''
