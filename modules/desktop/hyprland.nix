{ config, inputs, pkgs, ... }:

let
  dynamicCursorsPlugin =
    inputs.hypr-dynamic-cursors.packages.${pkgs.stdenv.hostPlatform.system}.hypr-dynamic-cursors;
in
{
  # Noctalia is a Hyprland companion, so desktop dependencies live together.
  imports = [
    ./cursors.nix
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
    # DBeaver and other Java/GTK applications still need an X11 server for
    # AWT integration even when their main UI runs on Wayland.
    xwayland.enable = true;
    package = inputs.hyprland.packages.${pkgs.stdenv.hostPlatform.system}.hyprland;
    withUWSM = true;
  };

  blueprint.cursors = {
    packages = [ pkgs.bibata-cursors ];
    selected = {
      package = pkgs.bibata-cursors;
      theme = "Bibata-Modern-Ice";
    };
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
      cursor = {
        theme = config.blueprint.cursors.selected.theme;
        size = config.blueprint.cursors.selected.size;
        path = "${config.blueprint.cursors.selected.package}/share/icons";
      };
    };
  };

  security.pam.services.hyprlock = { };
  environment.sessionVariables = {
    NIXOS_OZONE_WL = "1";
    # The user-managed Lua config loads this before configuring shake-to-find.
    HYPR_DYNAMIC_CURSORS_PLUGIN = "${dynamicCursorsPlugin}/lib/libhypr-dynamic-cursors.so";
  };
}
