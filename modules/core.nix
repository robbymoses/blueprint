{ ... }:

{
  nix.settings.experimental-features = [ "nix-command" "flakes" ];
  nixpkgs.config.allowUnfree = true;

  time.timeZone = "America/Chicago";
  hardware.enableRedistributableFirmware = true;

  users.users."robert.moses" = {
    isNormalUser = true;
    description = "Robert Moses";
    extraGroups = [ "wheel" "audio" "video" "networkmanager" ];
  };
}
