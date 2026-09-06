{ pkgs, ... }:

{
  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];
  nixpkgs.config.allowUnfree = true;

  environment.variables = {
    EDITOR = "hx";
    VISUAL = "hx";
  };

  time.timeZone = "America/Chicago";
  hardware.enableRedistributableFirmware = true;

  users.users."robert.moses" = {
    isNormalUser = true;
    # The GUI containers bind only this user's Wayland runtime directory.
    # Keep this stable so the bind mount is known during Nix evaluation.
    uid = 1001;
    description = "Robert Moses";
    shell = pkgs.zsh;
    extraGroups = [
      "wheel"
      "audio"
      "video"
      "networkmanager"
    ];
  };

  programs.zsh.enable = true;
}
