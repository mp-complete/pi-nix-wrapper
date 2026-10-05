{ lib }:
{
  pkgs,
  name,
  version ? "0.0.0",
  extensions ? [ ],
  skills ? [ ],
  prompts ? [ ],
  themes ? [ ],
}:
let
  stripStoreHash =
    value:
    let
      basename = baseNameOf (toString value);
      matched = builtins.match "^[0-9a-df-np-sv-z]{32}-(.*)$" basename;
    in
    if matched == null then basename else builtins.elemAt matched 0;

  resourceEntries =
    kind: resources:
    lib.imap0 (
      index: resource:
      let
        resourceName = lib.strings.sanitizeDerivationName (stripStoreHash resource);
        relativePath = "${kind}/${toString index}-${resourceName}";
      in
      {
        entry = {
          name = relativePath;
          path = resource;
        };
        manifestPath = "./${relativePath}";
      }
    ) resources;

  resources = {
    extensions = resourceEntries "extensions" extensions;
    skills = resourceEntries "skills" skills;
    prompts = resourceEntries "prompts" prompts;
    themes = resourceEntries "themes" themes;
  };

  manifest = pkgs.writeText "${lib.strings.sanitizeDerivationName name}-package.json" (
    builtins.toJSON {
      inherit name version;
      keywords = [ "pi-package" ];
      pi = lib.mapAttrs (_: values: map (value: value.manifestPath) values) resources;
    }
  );
in
assert lib.assertMsg (name != "") "mkPiPackage requires a non-empty name";
pkgs.linkFarm (lib.strings.sanitizeDerivationName name) (
  [
    {
      name = "package.json";
      path = manifest;
    }
  ]
  ++ lib.concatMap (values: map (value: value.entry) values) (lib.attrValues resources)
)
