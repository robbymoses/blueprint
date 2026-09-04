{ inputs, pkgs, ... }:

{
  # Noctalia is a Hyprland companion, so desktop dependencies live together.
  imports = [
    inputs.hyprland.nixosModules.default
    inputs.noctalia.nixosModules.default
    inputs.noctalia-greeter.nixosModules.default
  ];

  nix.settings = {
    extra-substituters = [ "https://hyprland.cachix.org" ];
    extra-trusted-public-keys = [
      "hyprland.cachix.org-1:a7pgxzMz7+chwVL3/pzj6jIBMioiJM7ypFP8PwtkuGc="
    ];
  };

  programs.hyprland = {
    enable = true;
    package = inputs.hyprland.packages.${pkgs.stdenv.hostPlatform.system}.hyprland;
    withUWSM = true;
  };

  programs.noctalia = {
    enable = true;
    recommendedServices.enable = true;
    systemd.enable = true;
  };

  # This module configures greetd and AccountsService, then presents the
  # Noctalia login screen before launching a selected Wayland session.
  programs.noctalia-greeter = {
    enable = true;
    settings = {
      user.default = "robert.moses";
      keyboard.layout = "us";
    };
  };

  security.pam.services.hyprlock = { };
  environment.sessionVariables.NIXOS_OZONE_WL = "1";
}
