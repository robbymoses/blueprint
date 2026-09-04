{ pkgs, ... }:

let
  stablePackages = with pkgs; [
    chezmoi
    curl
    git
    neovim
    wget
  ];

  unstablePackages = with pkgs.unstable; [
    codex
    herdr
  ];
in
{
  environment.systemPackages = stablePackages ++ unstablePackages;
}
