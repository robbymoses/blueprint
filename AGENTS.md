# Repository guidance

This is a single-host NixOS flake for `asus-duo`. Read [README.md](README.md)
for the system overview, repository layout, rebuild commands, and the private
container workflow.

## Change guidelines

- Keep host composition in `hosts/asus-duo/default.nix`; put reusable concerns
  in `modules/` and hardware-specific settings under `hosts/asus-duo/hardware/`.
- Add regular packages to the appropriate file in `modules/packages/`. Use
  `pkgs.unstable` only when a newer package is intentional.
- Preserve `system.stateVersion` unless performing a deliberate NixOS migration.
- Keep private container definitions, client names, VPN endpoints, and secrets
  in `/home/robert.moses/client-containers/`, never in the repository or Nix
  store. Changes to those definitions require `--impure` evaluation.
- Update README.md whenever a user-facing command, repository path, module
  layout, package group, or documented behavior changes. Keep nearby comments
  accurate when changing implementation details.

## Validation

Run `nix flake check --accept-flake-config` after configuration changes when
the local environment permits it. On `asus-duo`, apply verified changes with:

```sh
sudo nixos-rebuild switch --accept-flake-config --flake .#asus-duo
```

Include `--impure` only when private container definitions are involved.
