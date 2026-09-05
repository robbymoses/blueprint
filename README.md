# Blueprint

Modular NixOS configuration for the `asus-duo` host (ASUS Zenbook Duo
UX8406MA). It uses NixOS 26.05 with selected packages from `nixos-unstable`.

## What it configures

- Hyprland with UWSM, Noctalia, and the Noctalia greeter.
- A system Zsh user, firmware support, and the latest kernel packages.
- Ghostty, Vivaldi, Chezmoi, Neovim, Codex, Herdr, and common command-line
  tools. Package lists live in `modules/packages/`.
- An automatic backlight setting for the detachable keyboard when it is
  connected by USB. Use `kb-light <off|l|m|h>` to change it for the current
  connection; the configured reconnect default is `high`.
- Optional, isolated GUI VPN containers configured outside this repository.
- System-wide Git pre-commit checks for Nix formatting, lint/dead-code issues,
  and staged secrets.

User-level configuration, including Noctalia settings, belongs in the Chezmoi
repository rather than this system configuration.

## Apply the configuration

Run this from the repository root on `asus-duo`:

```sh
sudo nixos-rebuild switch --flake .#asus-duo
```

The flake's Cachix configuration is used for Hyprland and Noctalia. The first
switch may still download and build dependencies.

## Private client containers

`modules/containers.nix` creates optional NixOS containers for GUI applications
whose networking is isolated from the host. Private container definitions are
read from `/home/robert.moses/client-containers/*.nix`, so they are neither
tracked by Git nor copied to the Nix store. Start with
[`examples/client-container.nix.example`](examples/client-container.nix.example).

After creating or changing a private definition, use an impure evaluation:

```sh
sudo nixos-rebuild switch --impure --flake .#asus-duo
```

Use the `microvm` launcher from the host's Wayland session:

```sh
microvm <private-client-name> firefox
microvm <private-client-name> shell
microvm <private-client-name> status
microvm <private-client-name> restart
```

`shell` and GUI application launches require an active Wayland session.
Administrative setup inside a container, such as Twingate enrollment, uses
normal password-authenticated host sudo:

```sh
sudo nixos-container root-login <private-client-name>
twingate setup
```

Keep authentication material out of Nix expressions and the repository. The
example mounts a root-only host file read-only into a container for a Tailscale
auth key.

## Commit checks

After this configuration is applied, Git uses the system-wide pre-commit hook
at `/etc/git-hooks/pre-commit`; no `nix develop` shell is needed. It checks
staged Nix files with `nixfmt`, `statix`, and `deadnix`, then scans staged
changes with `gitleaks`.

The hook applies to every local Git repository on this machine. It is a local
guardrail, so repositories shared with others should also use remote secret
scanning.
