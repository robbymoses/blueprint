{ pkgs, ... }:

let
  stablePackages = with pkgs; [
    ghostty
  ];

  unstablePackages = with pkgs.unstable; [
    # Add packages from nixos-unstable here.
  ];
in
{
  environment.systemPackages = stablePackages ++ unstablePackages;
}
