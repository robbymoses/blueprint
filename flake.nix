{
  description = "Robert's modular NixOS configuration";

  nixConfig = {
    extra-substituters = [
      "https://hyprland.cachix.org"
      "https://noctalia.cachix.org"
    ];
    extra-trusted-public-keys = [
      "hyprland.cachix.org-1:a7pgxzMz7+chwVL3/pzj6jIBMioiJM7ypFP8PwtkuGc="
      "noctalia.cachix.org-1:pCOR47nnMEo5thcxNDtzWpOxNFQsBRglJzxWPp3dkU4="
    ];
  };

  inputs = {
    # Current stable NixOS release.
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";

    # Opt into this per package in modules/packages/{cli-tools,gui-apps}.nix.
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixos-unstable";

    # Keep this input's dependency graph independent: its Cachix binaries are
    # built against the revisions locked by the upstream Hyprland flake.
    hyprland.url = "github:hyprwm/Hyprland";

    # The cachix branch tracks the newest Noctalia revision already in its cache.
    noctalia.url = "github:noctalia-dev/noctalia/cachix";

    noctalia-greeter.url = "github:noctalia-dev/noctalia-greeter";
  };

  outputs = inputs@{ self, nixpkgs, nixpkgs-unstable, ... }:
    let
      system = "x86_64-linux";
      unstableOverlay = final: _: {
        unstable = import nixpkgs-unstable {
          inherit system;
          config.allowUnfree = true;
        };
      };
    in {
      nixosConfigurations.asus-duo = nixpkgs.lib.nixosSystem {
        inherit system;
        specialArgs = { inherit inputs; };
        modules = [
          { nixpkgs.overlays = [ unstableOverlay ]; }
          ./hosts/asus-duo
        ];
      };
    };
}
