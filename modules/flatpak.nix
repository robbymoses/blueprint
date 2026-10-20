{ inputs, ... }:

{
  imports = [ inputs.nix-flatpak.nixosModules.nix-flatpak ];

  # Keep large, frequently updated desktop applications outside the Nix store.
  # Add Flathub application IDs here to install them system-wide on activation.
  services.flatpak = {
    enable = true;
    packages = [
      "com.adamcake.Bolt"
    ];

    # Do not remove Flatpaks installed manually by the user.
    uninstallUnmanaged = false;

    # A failed download or deployment should not retry forever or repeatedly
    # make an otherwise successful NixOS activation report failure.
    restartOnFailure.enable = false;

    update.auto = {
      enable = true;
      onCalendar = "weekly";
    };
  };
}
