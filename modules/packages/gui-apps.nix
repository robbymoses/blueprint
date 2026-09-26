{ pkgs, ... }:

let
  stablePackages = with pkgs; [
    ghostty
    firefox
    vivaldi
    spotify
  ];

  unstablePackages = with pkgs.unstable; [
    # Add packages from nixos-unstable here.
    bolt-launcher
  ];
in
{
  environment.systemPackages = stablePackages ++ unstablePackages;
}
