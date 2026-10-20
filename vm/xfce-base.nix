{ lib, modulesPath, pkgs, ... }:

{
  # Include virtio block, network, display, balloon, and console drivers in the
  # initrd so the image can find its root disk when booted by QEMU/libvirt.
  imports = [ (modulesPath + "/profiles/qemu-guest.nix") ];

  networking = {
    # Client modules can replace this without using mkForce.
    hostName = lib.mkDefault "xfce-base";
    networkmanager.enable = true;
  };

  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];
  nixpkgs.config.allowUnfree = true;

  time.timeZone = "America/Chicago";

  services.xserver = {
    enable = true;
    desktopManager.xfce.enable = true;
    displayManager.lightdm.enable = true;
  };
  services.displayManager = {
    defaultSession = "xfce";
    autoLogin = {
      enable = true;
      user = "robert.moses";
    };
  };

  hardware.graphics.enable = true;
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
  };

  # These agents provide clean shutdown, clipboard integration, and dynamic
  # display resizing when the image runs under libvirt with a SPICE console.
  services.qemuGuest.enable = true;
  services.spice-vdagentd.enable = true;

  users.users."robert.moses" = {
    isNormalUser = true;
    uid = 1001;
    description = "Robert Moses";
    extraGroups = [
      "wheel"
      "audio"
      "video"
      "networkmanager"
    ];
  };

  # The baseline has no password or secret material. Its local SPICE console
  # logs in automatically, and later private client modules can add SSH access.
  security.sudo.wheelNeedsPassword = false;

  environment.systemPackages = with pkgs; [
    git
    usbutils
  ];

  # This is a new image, so its compatibility baseline matches its first NixOS
  # release. Do not change it during routine upgrades.
  system.stateVersion = "26.05";
}
