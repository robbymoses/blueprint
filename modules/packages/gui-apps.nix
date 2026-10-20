{ pkgs, ... }:

let
  stablePackages = with pkgs; [
    vivaldi
    spotify
  ];

  unstablePackages = with pkgs.unstable; [
    firefox
    vscode
    ghostty
  ];
in
{
  environment.systemPackages = stablePackages ++ unstablePackages;
}
