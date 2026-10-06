{ lib }:
{
  mkPiPackage = import ./mkPiPackage.nix { inherit lib; };
}
