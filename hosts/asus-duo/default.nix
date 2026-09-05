{ pkgs, ... }:

{
  imports = [
    ./hardware-configuration.nix
    ./hardware/cpu.nix
    ./hardware/gpu.nix
    ../../modules/core.nix
    ../../modules/git-hooks
    ../../modules/containers.nix
    ../../modules/desktop/hyprland.nix
    ../../modules/packages/cli-tools.nix
    ../../modules/packages/gui-apps.nix
  ];

  networking.hostName = "asus-duo";

  boot = {
    loader.systemd-boot.enable = true;
    loader.efi.canTouchEfiVariables = true;
    kernelPackages = pkgs.linuxPackages_latest;
  };

  # This is intentionally the original install version, not the nixpkgs release.
  system.stateVersion = "25.05";
}
