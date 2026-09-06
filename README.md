# Blueprint

Modular NixOS configuration for `asus-duo`, an ASUS Zenbook Duo UX8406MA.
The flake targets NixOS 26.05 and selectively uses packages from
`nixos-unstable`.

## Repository layout

```text
.
├── flake.nix                         # Inputs and the asus-duo configuration
├── hosts/asus-duo/                   # Host composition and hardware settings
│   ├── default.nix                   # Host services, boot, and keyboard support
│   └── hardware/                     # CPU and GPU configuration
├── modules/
│   ├── core.nix                      # Shared Nix, user, firmware, and locale settings
│   ├── containers.nix                # Optional isolated GUI VPN containers
│   ├── desktop/hyprland.nix          # Hyprland, Noctalia, and greeter
│   └── packages/                     # Stable and unstable package selections
└── examples/                         # Safe templates for untracked local configuration
```

User-level configuration—such as Noctalia settings—belongs in the Chezmoi
repository, not here.

## What it configures

- Hyprland with UWSM, Noctalia, and the Noctalia greeter.
- The `robert.moses` Zsh user, firmware support, and current kernel packages.
- Ghostty, Vivaldi, Chezmoi, Neovim, Codex, Herdr, and common command-line
  tools. Package lists live in `modules/packages/`.
- An automatic backlight setting for the detachable keyboard when it connects
  over USB. Use `kb-light <off|l|m|h>` to change it for the current connection;
  its reconnect default is `high`.
- Optional GUI VPN containers whose networking is isolated from the host.
- System-wide Git pre-commit checks for Nix formatting, lint/dead-code issues,
  and staged secrets.

## Apply and verify

Run these commands from the repository root on `asus-duo`:

```sh
# Evaluate the flake, trust its declared Cachix configuration, and run checks.
nix flake check --accept-flake-config

# Apply the host configuration.
sudo nixos-rebuild switch --accept-flake-config --flake .#asus-duo
```

The flake configures Cachix substitutes for Hyprland and Noctalia. The first
switch can still download or build dependencies.

To refresh locked inputs deliberately:

```sh
nix flake update
```

Review the resulting `flake.lock` change before committing it.

## Private client containers

`modules/containers.nix` defines optional NixOS containers for GUI applications
whose networking is isolated from the host. Private definitions are loaded from
`/home/robert.moses/client-containers/*.nix`; they are not tracked in Git or
copied to the Nix store. Start with
[`examples/client-container.nix.example`](examples/client-container.nix.example).

After creating or changing a private definition, evaluate impurely:

```sh
sudo nixos-rebuild switch --accept-flake-config --impure --flake .#asus-duo
```

Use `microvm` from the host's Wayland session:

```sh
microvm <private-client-name> firefox
microvm <private-client-name> shell
microvm <private-client-name> status
microvm <private-client-name> restart
```

`shell` and GUI launches require an active Wayland session. Administrative setup
inside a container, such as Twingate enrollment, uses normal host sudo:

```sh
sudo nixos-container root-login <private-client-name>
twingate setup
```

Keep credentials and client metadata out of Nix expressions and this repository.
The example shows a root-only, read-only host-file mount for a Tailscale auth key.

## Commit checks

After this configuration is applied, Git uses the system-wide pre-commit hook at
`/etc/git-hooks/pre-commit`; no `nix develop` shell is required. It checks
staged Nix files with `nixfmt`, `statix`, and `deadnix`, then scans staged
changes with `gitleaks`.

The hook applies to every local Git repository on this machine. It is a local
guardrail, so shared repositories should also use remote secret scanning.

## Contributing

Read [`AGENTS.md`](AGENTS.md) before changing the configuration. Keep module
comments and this README aligned when behavior, commands, configuration paths,
or repository structure changes.
