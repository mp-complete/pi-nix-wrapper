{ lib }:
{
  pkgs,
  src ? null,
  npmPackage ? null,
  version ? null,
  hash ? null,
  entrypoint ? "index.js",
}:
let
  sourceModesValid = (src != null) != (npmPackage != null);
  packageNameParts = if npmPackage == null then [ ] else lib.splitString "/" npmPackage;
  validPackageName =
    if npmPackage == null then
      true
    else
      let
        parts =
          if lib.length packageNameParts == 2 then
            [
              (lib.removePrefix "@" (builtins.elemAt packageNameParts 0))
              (builtins.elemAt packageNameParts 1)
            ]
          else
            packageNameParts;
      in
      (lib.length packageNameParts == 1 || lib.length packageNameParts == 2)
      && (lib.length packageNameParts != 2 || lib.hasPrefix "@" (builtins.elemAt packageNameParts 0))
      && lib.all (part: builtins.match "^[a-z0-9][a-z0-9._~-]*$" part != null) parts;
  validVersion =
    version != null
    && builtins.match "^[0-9A-Za-z][0-9A-Za-z.+-]*$" version != null;
  entrypointParts = lib.splitString "/" entrypoint;
  validEntrypoint =
    entrypointParts != [ ]
    && lib.all (part: part != "" && part != "." && part != "..") entrypointParts;

  npmSource =
    if npmPackage == null then
      null
    else
      let
        tarball = pkgs.fetchurl {
          url = "https://registry.npmjs.org/${npmPackage}/-/${baseNameOf npmPackage}-${version}.tgz";
          inherit hash;
        };
      in
      pkgs.runCommand "${lib.strings.sanitizeDerivationName npmPackage}-${version}-source"
        {
          nativeBuildInputs = [
            pkgs.gnutar
            pkgs.gzip
          ];
        }
        ''
          mkdir -p "$out"
          tar -xzf ${tarball} --strip-components=1 -C "$out"
        '';
  source = if src != null then src else npmSource;
  outputName =
    if npmPackage != null then
      "${lib.strings.sanitizeDerivationName npmPackage}-${version}-${baseNameOf entrypoint}"
    else
      "${lib.strings.sanitizeDerivationName (baseNameOf (toString src))}-${baseNameOf entrypoint}";
in
assert lib.assertMsg sourceModesValid "mkPiExtension requires exactly one of `src` or `npmPackage`";
assert lib.assertMsg validPackageName "mkPiExtension `npmPackage` must be a valid unscoped or scoped npm package name";
assert lib.assertMsg (npmPackage == null || (validVersion && hash != null && hash != ""))
  "mkPiExtension requires a valid `version` and non-empty `hash` for npm packages";
assert lib.assertMsg validEntrypoint "mkPiExtension `entrypoint` must be a relative path without empty, `.` or `..` components";
pkgs.runCommand outputName { } ''
  extension=${lib.escapeShellArg "${source}/${entrypoint}"}
  test -f "$extension" || {
    echo "mkPiExtension entrypoint does not exist: $extension" >&2
    exit 1
  }
  ln -s "$extension" "$out"
''
