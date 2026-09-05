{
  config,
  lib,
  pkgs,
  ...
}:

let
  hostUser = "robert.moses";
  hostUserUid = config.users.users.${hostUser}.uid;

  # Each client gets a separate untracked module in ~/client-containers. The
  # directory is read only by an impure evaluation, so none of its metadata is
  # added to the flake source or Git history.
  privateContainersDirectory = "/home/${hostUser}/client-containers";
  privateContainerFiles =
    if builtins.pathExists privateContainersDirectory then
      lib.mapAttrsToList (name: _: "${privateContainersDirectory}/${name}") (
        lib.filterAttrs (name: type: type == "regular" && lib.hasSuffix ".nix" name) (
          builtins.readDir privateContainersDirectory
        )
      )
    else
      [ ];
  containerNamesFile = pkgs.writeText "microvm-client-names" (
    lib.concatStringsSep "\n" (lib.attrNames config.blueprint.clientContainers)
  );

  # This is the only command granted passwordless sudo. It accepts only
  # declared client container names. The caller identity comes from sudo's
  # authenticated environment, never from command-line arguments.
  containerRunner = pkgs.writeShellApplication {
    name = "microvm-client-runner";
    runtimeInputs = [
      pkgs.nixos-container
      pkgs.coreutils
      pkgs.gnugrep
      pkgs.systemd
    ];
    text = ''
      if [ "$#" -lt 2 ]; then
        echo "internal error: insufficient container-runner arguments" >&2
        exit 64
      fi

      container="$1"
      action="$2"
      shift 2

      if ! grep -Fxq -- "$container" ${containerNamesFile}; then
        echo "microvm: '$container' is not a declared client container" >&2
        exit 1
      fi

      if [ "$action" != start ] && [ "$action" != stop ] && [ "$action" != restart ] \
        && [ "$action" != reset ] && [ "$action" != status ]; then
        if [ "''${SUDO_USER:-}" != ${lib.escapeShellArg hostUser} ] \
          || ! [[ "''${SUDO_UID:-}" =~ ^[0-9]+$ ]] \
          || ! [[ "''${SUDO_GID:-}" =~ ^[0-9]+$ ]]; then
          echo "microvm: runner must be invoked through sudo by ${hostUser}" >&2
          exit 1
        fi

        callerUid="$SUDO_UID"
        callerGid="$SUDO_GID"
        expectedRuntimeDir="/run/user/$callerUid"
      fi

      case "$action" in
        start)
          systemctl --system daemon-reload
          systemctl --system reset-failed "container@$container.service" >/dev/null 2>&1 || true
          exec systemctl --system start "container@$container.service"
          ;;
        stop)
          exec systemctl --system stop "container@$container.service"
          ;;
        restart)
          systemctl --system daemon-reload
          systemctl --system reset-failed "container@$container.service" >/dev/null 2>&1 || true
          exec systemctl --system restart "container@$container.service"
          ;;
        reset)
          systemctl --system daemon-reload
          exec systemctl --system reset-failed "container@$container.service"
          ;;
        status)
          exec systemctl --system status "container@$container.service" --no-pager
          ;;
        shell)
          if [ "$#" -ne 3 ]; then
            echo "usage: microvm <client> shell" >&2
            exit 64
          fi
          sessionRuntimeDir="$1"
          sessionWaylandDisplay="$2"
          sessionDbusAddress="$3"
          launchMode="interactive"
          set -- ${pkgs.bashInteractive}/bin/bash -l
          ;;
        *)
          if [ "$#" -lt 3 ]; then
            echo "usage: microvm <client> <app> [args...]" >&2
            exit 64
          fi
          sessionRuntimeDir="$1"
          sessionWaylandDisplay="$2"
          sessionDbusAddress="$3"
          shift 3
          launchMode="detached"
          set -- "$action" "$@"
          ;;
      esac

      if [ "$sessionRuntimeDir" != "$expectedRuntimeDir" ] \
        || [ "$callerUid" -ne ${toString hostUserUid} ] \
        || [[ -z "$sessionWaylandDisplay" || "$sessionWaylandDisplay" == */* ]]; then
        echo "microvm: GUI launch must come from ${hostUser}'s Wayland session" >&2
        exit 1
      fi

      systemctl --system daemon-reload
      systemctl --system reset-failed "container@$container.service" >/dev/null 2>&1 || true
      systemctl --system start "container@$container.service"

      nixos-container run "$container" -- \
        install -d -m 0700 -o "$callerUid" -g "$callerGid" /var/lib/microvm-home

      if [ "$launchMode" = "interactive" ]; then
        exec nixos-container run "$container" -- \
          setpriv --reuid="$callerUid" --regid="$callerGid" --clear-groups -- \
          env \
            HOME=/var/lib/microvm-home \
            XDG_RUNTIME_DIR="$sessionRuntimeDir" \
            WAYLAND_DISPLAY="$sessionWaylandDisplay" \
            XDG_SESSION_TYPE=wayland \
            DBUS_SESSION_BUS_ADDRESS="$sessionDbusAddress" \
            "$@"
      fi

      # A GUI app should outlive the short-lived nsenter invocation. Keep its
      # output in the container instead of holding the host terminal open.
      # shellcheck disable=SC2016
      exec nixos-container run "$container" -- \
        setpriv --reuid="$callerUid" --regid="$callerGid" --clear-groups -- \
        env \
          HOME=/var/lib/microvm-home \
          XDG_RUNTIME_DIR="$sessionRuntimeDir" \
          WAYLAND_DISPLAY="$sessionWaylandDisplay" \
          XDG_SESSION_TYPE=wayland \
          DBUS_SESSION_BUS_ADDRESS="$sessionDbusAddress" \
          ${pkgs.runtimeShell} -c '
            mkdir -p "$HOME/.local/state"
            nohup "$@" </dev/null >> "$HOME/.local/state/microvm-launcher.log" 2>&1 &
          ' microvm-launch "$@"
    '';
  };

  microvm = pkgs.writeShellApplication {
    name = "microvm";
    text = ''
      if [ "$#" -lt 2 ]; then
        echo "usage: microvm <client> <start|stop|restart|reset|status|shell|app> [args...]" >&2
        exit 64
      fi

      container="$1"
      shift
      action="$1"
      shift

      case "$action" in
        start|stop|restart|reset|status)
          exec /run/wrappers/bin/sudo -- ${containerRunner}/bin/microvm-client-runner \
            "$container" "$action"
          ;;
      esac

      if [ -z "''${XDG_RUNTIME_DIR:-}" ] || [ -z "''${WAYLAND_DISPLAY:-}" ]; then
        echo "microvm: GUI applications and shells must be run from a Wayland session" >&2
        exit 1
      fi

      exec /run/wrappers/bin/sudo -- ${containerRunner}/bin/microvm-client-runner \
        "$container" "$action" "$XDG_RUNTIME_DIR" "$WAYLAND_DISPLAY" \
        "''${DBUS_SESSION_BUS_ADDRESS:-}" "$@"
    '';
  };

  mkGuiVpnContainer =
    {
      # Allocate a different pair from 10.203.0.0/16 for each container.
      # These addresses are only the host-to-container transport; application
      # traffic is routed through the VPN configured below.
      hostAddress,
      localAddress,
      # Map container paths to root-only host files. This is intended for
      # authentication material such as a Tailscale auth key; contents are
      # bind-mounted at runtime and never copied to the Nix store.
      secretMounts ? { },
      packages ? [ ],
      extraConfig ? { },
    }:
    {
      # The host Wayland socket only exists while this user has an active
      # graphical session, so the launcher starts the container on demand.
      autoStart = false;
      privateNetwork = true;
      inherit hostAddress localAddress;
      enableTun = true;

      # Identity mapping retains the host UID needed to access the Wayland
      # socket, while systemd-nspawn still drops container capabilities.
      privateUsers = "identity";

      bindMounts = {
        # Only expose the configured desktop user's runtime directory. It is
        # writable because some GUI applications create runtime files there;
        # the launcher verifies that it is used only by this same user.
        "/run/user/${toString hostUserUid}" = {
          hostPath = "/run/user/${toString hostUserUid}";
          isReadOnly = false;
        };

      }
      // lib.mapAttrs (_: hostPath: {
        inherit hostPath;
        isReadOnly = true;
      }) secretMounts;

      config =
        { lib, pkgs, ... }:
        lib.mkMerge [
          {
            system.stateVersion = config.system.stateVersion;
            nixpkgs.config.allowUnfree = true;

            # GUI processes use setpriv with the invoking user's numeric
            # identity. Their profile stays in this container's persistent
            # /var/lib/microvm-home, not in the host home directory.
            environment.systemPackages = [ pkgs.util-linux ] ++ packages;
          }
          extraConfig
        ];
    };
in
{
  # The private file is optional: a clean checkout remains evaluable and has no
  # knowledge of client/container names. See examples/client-container.nix.example.
  imports = privateContainerFiles;

  options.blueprint.clientContainers = lib.mkOption {
    default = { };
    description = "Private client applications whose network traffic is isolated in a container.";
    type = lib.types.attrsOf (
      lib.types.submodule {
        options = {
          hostAddress = lib.mkOption {
            type = lib.types.str;
            description = "Host end of this container's private veth pair.";
          };
          localAddress = lib.mkOption {
            type = lib.types.str;
            description = "Container end of this container's private veth pair.";
          };
          secretMounts = lib.mkOption {
            type = lib.types.attrsOf lib.types.str;
            default = { };
            description = "Read-only container-path to host-path mounts for runtime secrets.";
          };
          packages = lib.mkOption {
            type = lib.types.listOf lib.types.package;
            default = [ ];
            description = "GUI applications installed only in this container.";
          };
          extraConfig = lib.mkOption {
            type = lib.types.attrs;
            default = { };
            description = "Additional NixOS configuration for this container.";
          };
        };
      }
    );
  };

  config = {
    containers = lib.mapAttrs (_: mkGuiVpnContainer) config.blueprint.clientContainers;

    # Every GUI VPN container is assigned an address in this otherwise-unused
    # private range. NAT gives its eth0 enough connectivity to establish the
    # VPN, while the VPN itself owns the default route for its applications.
    networking.nat = {
      enable = true;
      internalIPs = [ "10.203.0.0/16" ];
    };

    environment.systemPackages = [
      microvm
    ];

    security.sudo.extraRules = [
      {
        users = [ hostUser ];
        commands = [
          {
            command = "${containerRunner}/bin/microvm-client-runner";
            options = [ "NOPASSWD" ];
          }
        ];
      }
    ];
  };
}
