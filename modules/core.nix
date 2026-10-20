{ pkgs, ... }:

{
  nix = {
    settings.experimental-features = [
      "nix-command"
      "flakes"
    ];

    # Keep recent generations available for rollback while preventing the
    # store from growing indefinitely on this workstation.
    gc = {
      automatic = true;
      dates = "weekly";
      options = "--delete-older-than 30d";
    };
  };
  nixpkgs.config.allowUnfree = true;

  environment.variables = {
    EDITOR = "hx";
    VISUAL = "hx";
  };

  time.timeZone = "America/Chicago";
  hardware.enableRedistributableFirmware = true;

  users.users."robert.moses" = {
    isNormalUser = true;
    # Keep this stable across host and guest configurations.
    uid = 1001;
    description = "Robert Moses";
    shell = pkgs.zsh;
    extraGroups = [
      "wheel"
      "audio"
      "video"
      "networkmanager"
      "docker"
      "libvirtd"
    ];
  };

  programs.zsh.enable = true;
}
