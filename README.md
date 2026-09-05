# Blueprint

Modular NixOS configuration for `asus-duo`.

- `modules/desktop/hyprland.nix` owns Hyprland and its Noctalia dependency.
- `modules/containers.nix` provides isolated client containers and the
  `microvm <client> <action>` launcher. Private client definitions belong in
  `~/client-containers/*.nix`; start from
  `examples/client-container.nix.example`. It includes Twingate and Tailscale
  examples; keep authentication material outside Nix.
- `modules/packages/cli-tools.nix` and `modules/packages/gui-apps.nix` each expose
  explicit `stablePackages` and `unstablePackages` lists.
- User-level configuration, including Noctalia settings, belongs in the Chezmoi
  repository rather than this system configuration.

Apply it with:

```sh
sudo nixos-rebuild switch --flake .#asus-duo
```

## Commit checks

The NixOS configuration installs `nixfmt`, `statix`, `deadnix`, and `gitleaks`
system-wide. After applying this configuration, Git uses a system-wide
pre-commit hook: it blocks commits with unformatted Nix files, Nix lint or
dead-code findings, or secrets detected in staged changes. No `nix develop`
shell is required.

The hook applies to all repositories on this machine. Git hooks remain a local
guardrail, so use a remote secret-scanning rule as well if this repository is
ever shared with others.

Launch an application through a private container with:

```sh
microvm <private-client-name> firefox
microvm <private-client-name> shell
```

Administer a container (for example, enroll Twingate) through normal,
password-authenticated host sudo:

```sh
sudo nixos-container root-login <private-client-name>
twingate setup
```

After creating private definitions, rebuild with `--impure` so the flake can
read `~/client-containers/*.nix` without adding them to the flake
source:

```sh
sudo nixos-rebuild switch --impure --flake .#asus-duo
```
