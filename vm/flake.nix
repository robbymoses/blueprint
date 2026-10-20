{
  description = "Reusable NixOS/XFCE VM image and interactive libvirt manager";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";

  outputs = { self, nixpkgs }:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
      xfceVmBase = import ./xfce-base.nix;

      vmSystem = nixpkgs.lib.nixosSystem {
        inherit system;
        modules = [
          xfceVmBase
          ({ modulesPath, ... }: {
            imports = [ (modulesPath + "/virtualisation/disk-image.nix") ];
          })
        ];
      };
    in {
      nixosModules = {
        default = xfceVmBase;
        xfce-vm-base = xfceVmBase;
      };

      nixosConfigurations.xfce-vm-base = vmSystem;

      packages.${system} = rec {
        default = xfce-vm-image;
        xfce-vm-image = vmSystem.config.system.build.image;

        xfce-vm = pkgs.writeShellApplication {
          name = "xfce-vm";
          runtimeInputs = with pkgs; [
            coreutils
            gawk
            gnugrep
            jq
            libvirt
            qemu
            virt-manager
          ];
          text = builtins.readFile ./xfce-vm.sh;
        };

        # Compatibility for the original one-shot app name.
        spawn-xfce-vm = xfce-vm;
      };

      apps.${system} = rec {
        default = xfce-vm;
        xfce-vm = {
          type = "app";
          program = "${self.packages.${system}.xfce-vm}/bin/xfce-vm";
        };
        spawn-xfce-vm = xfce-vm;
      };

      templates = rec {
        default = client;
        client = {
          path = ./templates/client;
          description = "Standalone client VM flake extending the XFCE baseline";
        };
      };
    };
}
