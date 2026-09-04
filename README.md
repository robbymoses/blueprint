# Blueprint

Modular NixOS configuration for `asus-duo`.

- `modules/desktop/hyprland.nix` owns Hyprland and its Noctalia dependency.
- `modules/packages/cli-tools.nix` and `modules/packages/gui-apps.nix` each expose
  explicit `stablePackages` and `unstablePackages` lists.
- User-level configuration, including Noctalia settings, belongs in the Chezmoi
  repository rather than this system configuration.

Apply it with:

```sh
sudo nixos-rebuild switch --flake .#asus-duo
```
