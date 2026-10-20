# Blueprint

Modular NixOS configuration for `asus-duo`, an ASUS Zenbook Duo UX8406MA, plus
a buildable NixOS/XFCE baseline VM image. The flake targets NixOS 26.05 and
selectively uses packages from `nixos-unstable`.

## Repository layout

```text
.
├── flake.nix                         # Inputs and the asus-duo host configuration
├── hosts/asus-duo/                   # Host composition and hardware settings
│   ├── default.nix                   # Host services, boot, and keyboard support
│   └── hardware/                     # CPU and GPU configuration
├── modules/
│   ├── core.nix                      # Shared Nix, user, firmware, and locale settings
│   ├── containers.nix                # Generic container runtime and microvm launcher
│   ├── desktop/cursors.nix           # Installed cursor themes and selection
│   ├── desktop/hyprland.nix          # Hyprland, Noctalia, and greeter
│   ├── flatpak.nix                    # System-wide applications installed from Flathub
│   ├── packages/                     # Stable and unstable package selections
│   └── virtualization.nix            # Host libvirt, virt-manager, and USB redirection
├── vm/                                # Standalone guest flake, lock, module, and launcher
│   ├── flake.nix                     # Guest-only image and app outputs
│   ├── flake.lock                    # Guest-only pinned inputs
│   ├── templates/client/             # Starter for independently locked clients
│   ├── xfce-base.nix                 # Reusable declarative XFCE guest baseline
│   └── xfce-vm.sh                    # Interactive libvirt VM manager
└── examples/                         # Safe templates for untracked local configuration
```

User-level configuration—such as Noctalia settings—belongs in the Chezmoi
repository, not here.

## What it configures

- Hyprland with UWSM, Noctalia, the Noctalia greeter, and Bibata cursors.
- The `robert.moses` Zsh user, firmware support, and current kernel packages.
- Intel Mesa graphics and video drivers from the pinned `nixos-unstable` input,
  including 32-bit Mesa support.
- Firefox, VS Code, and Ghostty from `nixos-unstable`; Vivaldi, Chezmoi,
  Neovim, Codex, Herdr, and common command-line tools. Nix package lists live
  in `modules/packages/`.
- Bambu Studio and Bolt Launcher installed system-wide from Flathub. Add more
  Flathub application IDs to `services.flatpak.packages` in
  `modules/flatpak.nix`; declared applications update weekly.
- An automatic backlight setting for the detachable keyboard when it connects
  over USB. Use `kb-light <off|l|m|h>` to change it for the current connection;
  its reconnect default is `high`.
- Libvirt and virt-manager on the host, including SPICE USB redirection for
  devices such as webcams and USB headsets.
- A declarative NixOS/XFCE guest image with PipeWire, QEMU/SPICE agents,
  automatic local console login, Git, and USB diagnostics.
- The generic GUI container runtime and `microvm` launcher, without importing
  or building any private client configuration as part of the host.
- Docker Engine on the host; `robert.moses` can use it without `sudo`.
- Weekly Nix garbage collection, retaining generations from the last 30 days.
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
switch can still download or build dependencies. System activation also
installs any missing applications declared in `modules/flatpak.nix` from
Flathub. Manually installed Flatpaks are left untouched.

To refresh locked inputs deliberately:

```sh
nix flake update
```

Review the resulting `flake.lock` change before committing it.

## XFCE baseline VM image

Build the UEFI qcow2 image without changing the host:

```sh
nix build --accept-flake-config path:./vm#xfce-vm-image
```

The `result` symlink points to an image derivation containing the qcow2 file.
The image is a generic baseline with no client metadata, SSH credentials, or
secrets. Its `robert.moses` user logs in automatically through the local SPICE
console and has passwordless sudo; do not expose an uncustomized instance to an
untrusted network.

The baseline disk is automatically sized to its initial contents. Start the
interactive manager with:

```sh
nix run path:./vm#xfce-vm
```

It walks through creating, rebuilding, deleting, or listing managed VMs.
Rebuild and delete present a numbered list of available VMs and require
confirmation before erasing anything. Rebuild preserves the selected VM's disk
capacity and libvirt definition, but replaces all guest data with a fresh
overlay from the current `result` image.

Install the lightweight manager into your user profile when you want a regular
`xfce-vm` command:

```sh
nix profile install path:./vm#xfce-vm
xfce-vm
```

For direct use or automation, subcommands are also available:

```sh
xfce-vm create xfce-baseline 64G
xfce-vm rebuild xfce-baseline
xfce-vm delete xfce-baseline
xfce-vm list
```

The original `nix run path:./vm#spawn-xfce-vm -- NAME [DISK_SIZE]` form remains
available as a compatibility alias. The manager dynamically resolves the image
below `result`, imports it once into the default libvirt storage pool under a
versioned name, and creates a qcow2 overlay from that stable copy. Existing
overlays therefore do not depend on a garbage-collectable Nix store path. The
guest expands its root partition and filesystem on first boot.

The default domain has four virtual CPUs, starts with 6 GiB of RAM, can be
ballooned up to 12 GiB, and has two SPICE USB-redirection slots. Override these
defaults when spawning a VM with `VM_VCPUS`, `VM_INITIAL_MEMORY_MIB`, and
`VM_MAX_MEMORY_MIB`.

Apply the host virtualization support separately:

```sh
sudo nixos-rebuild switch --accept-flake-config --flake .#asus-duo
```

Then open `virt-manager` and connect to `QEMU/KVM system` to use the VM's SPICE
display. Attach a webcam or USB headset from the console's USB redirection
menu; a physical USB device can be owned by only one machine at a time. Keep
the versioned base volumes immutable while an overlay depends on them.

The VM flake has its own `flake.lock`; refresh it independently with:

```sh
nix flake update --flake path:./vm
```

Create an independently locked client flake outside this repository with the
included template:

```sh
mkdir -p /home/robert.moses/client-containers/vms/acme
cd /home/robert.moses/client-containers/vms/acme
nix flake init -t path:/home/robert.moses/blueprint/vm#client
```

Edit `client.nix` to set a hostname and add client-specific packages or
services. Then build the composed image and create the VM from that directory:

```sh
nix build --accept-flake-config path:.#xfce-vm-image
nix run path:/home/robert.moses/blueprint/vm#xfce-vm
```

The manager uses the current directory's `result`, so the new domain is based
on the client image rather than the generic image. The client directory owns
its `flake.lock`. Update its Nixpkgs revision with `nix flake update`; after the
shared module changes, refresh that input with `nix flake update vm`. Rebuild
the image and select the existing domain through `xfce-vm rebuild` to apply
either kind of change.

The root host flake neither imports nor exposes client or guest configuration.

## Private client containers

`modules/containers.nix` enables the generic NixOS `container@.service` and
supplies the shared host-side Wayland, Xwayland, render-node, TUN, NAT, launcher,
and sudo integration. It contains no client names, private flake paths, or guest
system closures. Consequently, an ordinary host rebuild never evaluates or
builds a client container:

```sh
sudo nixos-rebuild switch --accept-flake-config --flake .#asus-duo
```

Private guests live independently below `/home/robert.moses/client-containers`.
The layout keeps a shared guest baseline separate from one small flake per
client:

```text
client-containers/
├── common/
│   ├── flake.nix
│   └── baseline.nix
└── clients/
    └── client-a/
        ├── flake.nix
        ├── flake.lock
        └── default.nix
```

Each client flake imports the common baseline and exposes the conventional
`nixosConfigurations.container` output expected by `nixos-container`. See
[`examples/client-container.nix.example`](examples/client-container.nix.example)
for a client module. Keep client names, VPN configuration, endpoints, and
credentials only in that private directory or repository.

Register a new client once after applying the host runtime. Container names
using this private network must be at most 11 characters. Use an explicit
`path:` reference because the home directory is itself a Git worktree:

```sh
sudo nixos-container create client-a \
  --flake path:/home/robert.moses/client-containers/clients/client-a \
  --host-address 10.203.0.1 \
  --local-address 10.203.0.2
```

The registration, persistent root, and independently managed system profile
live under `/etc/nixos-containers`, `/var/lib/nixos-containers`, and
`/nix/var/nix/profiles/per-container`, respectively. Host rebuilds leave this
imperative state alone. After changing packages or services in `client-a`, only
update that guest:

```sh
sudo nixos-container update client-a
```

When the shared `common` flake changes, refresh its lock entry from each affected
client directory before updating:

```sh
nix flake update common --flake path:$PWD
sudo nixos-container update client-a
```

Use `microvm` from the host's Wayland session:

```sh
microvm <private-client-name> firefox
microvm <private-client-name> shell
microvm <private-client-name> status
microvm <private-client-name> restart
```

`shell` and GUI launches require an active Wayland session. `shell` starts in
the guest user's normal `/home/robert.moses` home directory and launches its
configured login shell. This home is inside the guest, not the host home
directory. The launcher relays the session's Xwayland socket into the container
without sharing its network namespace, for applications such as DBeaver that
need X11-backed Java rendering. Containers can use the host Intel GPU's render
node and VA-API drivers for accelerated rendering and video decoding; they do
not receive the display-capable DRM device. Administrative setup inside a
container, such as Twingate enrollment, uses normal host sudo:

```sh
sudo nixos-container root-login <private-client-name>
twingate setup
```

The private common baseline gives every GUI client container rootless Podman for
development. A Docker-compatible `docker` command is available, without
granting the guest the mount and network capabilities a rootful Docker daemon
would require; its private VPN network namespace remains separate from the
host. `docker compose` uses Podman's Compose compatibility through
`podman-compose`.

These guests are isolated client network and development environments, not a
hostile-code sandbox: their Wayland runtime directory is shared with the host,
and their user IDs are host-visible so rootless Podman can delegate subordinate
IDs. In particular, guest root can read any root-only host file mounted into
that guest.

Keep credentials and client metadata out of this repository and the Nix store.
Per-client host mounts are private runtime state rather than host-flake options;
prefer enrollment into the persistent guest or a dedicated secret manager.

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
