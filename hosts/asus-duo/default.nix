{ pkgs, ... }:

let
  # Used each time the detachable keyboard is connected by USB.
  zenbookKeyboardBacklightLevel = "high";

  zenbookKeyboardBacklight =
    pkgs.writers.writePython3Bin "zenbook-keyboard-backlight"
      {
        libraries = [ pkgs.python3Packages.pyusb ];
      }
      ''
        import sys
        import usb.core

        levels = {"off": 0, "low": 1, "medium": 2, "high": 3}
        if len(sys.argv) != 2 or sys.argv[1] not in levels:
            raise SystemExit(f"usage: {sys.argv[0]} <off|low|medium|high>")

        keyboard = usb.core.find(idVendor=0x0B05, idProduct=0x1B2C)
        if keyboard is None:
            raise SystemExit("ASUS Zenbook Duo keyboard is not attached by USB")

        interface = 4
        detached = keyboard.is_kernel_driver_active(interface)
        if detached:
            keyboard.detach_kernel_driver(interface)

        try:
            report = [0x5A, 0xBA, 0xC5, 0xC4, levels[sys.argv[1]]] + [0] * 11
            written = keyboard.ctrl_transfer(
                0x21, 0x09, 0x035A, interface, report, timeout=1000
            )
            if written != len(report):
                raise RuntimeError(f"only wrote {written} of {len(report)} bytes")
        finally:
            if detached:
                try:
                    keyboard.attach_kernel_driver(interface)
                except usb.core.USBError:
                    # The HID driver can rebind itself before libusb reaches this.
                    pass
      '';

  kbLight = pkgs.writeShellApplication {
    name = "kb-light";
    runtimeInputs = [ zenbookKeyboardBacklight ];
    text = ''
      case "$#:$1" in
        1:off) level=off ;;
        1:l | 1:low) level=low ;;
        1:m | 1:medium) level=medium ;;
        1:h | 1:high) level=high ;;
        *)
          echo "usage: kb-light <off|l|m|h>" >&2
          exit 2
          ;;
      esac

      exec zenbook-keyboard-backlight "$level"
    '';
  };
in

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

  # The UX8406MA's detachable keyboard is USB 0b05:1b2c. It has no Aura or
  # kernel LED interface, so set its backlight directly when it is attached.
  environment.systemPackages = [
    zenbookKeyboardBacklight
    kbLight
  ];

  services.udev.extraRules = ''
    ACTION=="add", SUBSYSTEM=="usb", ATTR{idVendor}=="0b05", ATTR{idProduct}=="1b2c", GROUP="wheel", MODE="0660", TAG+="systemd", ENV{SYSTEMD_WANTS}+="zenbook-keyboard-backlight.service"
  '';

  systemd.services.zenbook-keyboard-backlight = {
    description = "Set ASUS Zenbook Duo keyboard backlight";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${zenbookKeyboardBacklight}/bin/zenbook-keyboard-backlight ${zenbookKeyboardBacklightLevel}";
    };
  };

  boot = {
    loader.systemd-boot.enable = true;
    loader.efi.canTouchEfiVariables = true;
    kernelPackages = pkgs.linuxPackages_latest;
  };

  # This is intentionally the original install version, not the nixpkgs release.
  system.stateVersion = "25.05";
}
