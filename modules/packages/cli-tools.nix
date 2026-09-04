{ pkgs, ... }:

let
  stablePackages = with pkgs; [
    curl
    git
    neovim
    wget
  ];

  unstablePackages = with pkgs.unstable; [
    # Add packages from nixos-unstable here.
  ];
in
{
  environment.systemPackages = stablePackages ++ unstablePackages;
}
