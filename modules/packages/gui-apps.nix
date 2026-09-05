{ pkgs, ... }:

let
  stablePackages = with pkgs; [
    ghostty
    vivaldi
  ];

  unstablePackages = with pkgs.unstable; [
    # Add packages from nixos-unstable here.
  ];
in
{
  environment.systemPackages = stablePackages ++ unstablePackages;
}
