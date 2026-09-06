{ pkgs, ... }:

let
  stablePackages = with pkgs; [
    chezmoi
    curl
    git
    helix
    neovim
    pre-commit
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
