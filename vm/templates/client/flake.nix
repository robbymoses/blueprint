{
  description = "Client-specific NixOS/XFCE VM image";

  inputs = {
    # Keep client configuration and its lock outside the host repository while
    # reusing the generic VM module from Blueprint.
    vm.url = "path:/home/robert.moses/blueprint/vm";
    nixpkgs.follows = "vm/nixpkgs";
  };

  outputs = { nixpkgs, vm, ... }:
    let
      system = "x86_64-linux";
      clientSystem = nixpkgs.lib.nixosSystem {
        inherit system;
        modules = [
          vm.nixosModules.xfce-vm-base
          ./client.nix
          ({ modulesPath, ... }: {
            imports = [ (modulesPath + "/virtualisation/disk-image.nix") ];
          })
        ];
      };
    in {
      nixosConfigurations.client-vm = clientSystem;

      packages.${system} = rec {
        default = xfce-vm-image;
        xfce-vm-image = clientSystem.config.system.build.image;
      };
    };
}
