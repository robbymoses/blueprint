{
  config,
  lib,
  pkgs,
  ...
}:

let
  hostUser = "robert.moses";
  guestHome = "/home/${hostUser}";
  hostUserUid = config.users.users.${hostUser}.uid;
  hostUserGroup = config.users.users.${hostUser}.group;
  hostUserGid = config.users.groups.${hostUserGroup}.gid;
  hostRenderGid = config.users.groups.render.gid;
  x11ProxyDirectory = "/run/user/${toString hostUserUid}/microvm-x11";

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
      pkgs.procps
      pkgs.socat
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

      ensureX11ProxyDirectory() {
        if [ ! -d /run/user/${toString hostUserUid} ]; then
          echo "microvm: client containers require an active ${hostUser} session" >&2
          exit 1
        fi

        install -d -m 0700 -o ${toString hostUserUid} -g ${toString hostUserGid} ${x11ProxyDirectory}
      }

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
          ensureX11ProxyDirectory
          systemctl --system daemon-reload
          systemctl --system reset-failed "container@$container.service" >/dev/null 2>&1 || true
          exec systemctl --system start "container@$container.service"
          ;;
        stop)
          exec systemctl --system stop "container@$container.service"
          ;;
        restart)
          ensureX11ProxyDirectory
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
          if [ "$#" -ne 5 ]; then
            echo "usage: microvm <client> shell" >&2
            exit 64
          fi
          sessionRuntimeDir="$1"
          sessionWaylandDisplay="$2"
          sessionDbusAddress="$3"
          sessionX11Display="$4"
          sessionXauthority="$5"
          launchMode="interactive"
          # The login-shell wrapper must retain these expansions for execution
          # inside the container, after setpriv has changed its identity.
          # shellcheck disable=SC2016
          set -- ${pkgs.bashInteractive}/bin/bash -c '
            cd "$HOME"
            loginShell="$(getent passwd "$(id -u)" | cut -d: -f7)"
            if [ -z "$loginShell" ] || [ ! -x "$loginShell" ]; then
              loginShell=${pkgs.bashInteractive}/bin/bash
            fi
            exec "$loginShell" -l
          '
          ;;
        *)
          if [ "$#" -lt 5 ]; then
            echo "usage: microvm <client> <app> [args...]" >&2
            exit 64
          fi
          sessionRuntimeDir="$1"
          sessionWaylandDisplay="$2"
          sessionDbusAddress="$3"
          sessionX11Display="$4"
          sessionXauthority="$5"
          shift 5
          launchMode="detached"
          set -- "$action" "$@"
          ;;
      esac

      # Hyprland's Xwayland server writes its cookie below the Wayland runtime
      # directory. It is not always exported as XAUTHORITY by a Wayland-native
      # terminal, so discover it before entering the container.
      if [ -z "$sessionXauthority" ]; then
        for xauthority in "$expectedRuntimeDir"/.Xwaylandauth.*; do
          if [ -f "$xauthority" ]; then
            sessionXauthority="$xauthority"
            break
          fi
        done
      fi

      if [ "$sessionRuntimeDir" != "$expectedRuntimeDir" ] \
        || [ "$callerUid" -ne ${toString hostUserUid} ] \
        || [[ -z "$sessionWaylandDisplay" || "$sessionWaylandDisplay" == */* ]] \
        || [[ -n "$sessionX11Display" && ! "$sessionX11Display" =~ ^:[0-9]+(\\.[0-9]+)?$ ]] \
        || [[ -n "$sessionXauthority" && "$sessionXauthority" != "$expectedRuntimeDir"/* ]]; then
        echo "microvm: GUI launch must come from ${hostUser}'s Wayland session" >&2
        exit 1
      fi

      # UWSM starts Xwayland with a private /tmp and inherited listening
      # sockets. Enter its mount namespace for the X11-facing half of the
      # relay, while exposing a regular socket that can be bind-mounted into
      # every client container.
      ensureX11ProxyDirectory
      if [ -n "$sessionX11Display" ]; then
        x11DisplayNumber="''${sessionX11Display#:}"
        x11DisplayNumber="''${x11DisplayNumber%%.*}"
        x11ProxySocket=${x11ProxyDirectory}/X"$x11DisplayNumber"
        x11ProxyPidFile="$x11ProxySocket.pid"

        # Replace the pre-namespace relay from the previous configuration.
        # Future relays are tracked by PID so a stale runtime socket is also
        # safely recreated after a session restart.
        if [ -S "$x11ProxySocket" ] && [ ! -r "$x11ProxyPidFile" ]; then
          for proxyPid in $(pgrep -x socat || true); do
            if tr '\\0' ' ' < "/proc/$proxyPid/cmdline" | grep -Fq -- "UNIX-LISTEN:$x11ProxySocket"; then
              kill "$proxyPid"
              break
            fi
          done
          rm -f "$x11ProxySocket"
        fi

        if [ -r "$x11ProxyPidFile" ]; then
          x11ProxyPid=$(cat "$x11ProxyPidFile")
          if ! [[ "$x11ProxyPid" =~ ^[0-9]+$ ]] || ! kill -0 "$x11ProxyPid" 2>/dev/null; then
            rm -f "$x11ProxyPidFile" "$x11ProxySocket"
          fi
        fi

        if [ ! -S "$x11ProxySocket" ]; then
          xwaylandPid=$(pgrep -xo Xwayland || true)
          if ! [[ "$xwaylandPid" =~ ^[0-9]+$ ]]; then
            echo "microvm: no Xwayland process is available for DISPLAY $sessionX11Display" >&2
            exit 1
          fi

          ${pkgs.coreutils}/bin/nohup \
            nsenter --mount="/proc/$xwaylandPid/ns/mnt" -- \
              setpriv --reuid="$callerUid" --regid="$callerGid" --clear-groups -- \
              ${pkgs.socat}/bin/socat \
                "UNIX-LISTEN:$x11ProxySocket,fork,mode=0600" \
                "UNIX-CONNECT:/tmp/.X11-unix/X$x11DisplayNumber" \
            </dev/null >/dev/null 2>&1 &
          echo "$!" > "$x11ProxyPidFile"
        fi
      fi

      systemctl --system daemon-reload
      systemctl --system reset-failed "container@$container.service" >/dev/null 2>&1 || true
      systemctl --system start "container@$container.service"

      if [ "$launchMode" = "interactive" ]; then
        exec nixos-container run "$container" -- \
          setpriv --reuid="$callerUid" --regid="$callerGid" --init-groups -- \
          env -i \
            HOME=${guestHome} \
            PATH=/run/current-system/sw/bin \
            TERM=xterm-256color \
            XDG_CONFIG_DIRS=/etc/xdg \
            XDG_RUNTIME_DIR="$sessionRuntimeDir" \
            WAYLAND_DISPLAY="$sessionWaylandDisplay" \
            XDG_SESSION_TYPE=wayland \
            DBUS_SESSION_BUS_ADDRESS="$sessionDbusAddress" \
            DISPLAY="$sessionX11Display" \
            XAUTHORITY="$sessionXauthority" \
            "$@"
      fi

      # A GUI app should outlive the short-lived nsenter invocation. Keep its
      # output in the container instead of holding the host terminal open.
      # shellcheck disable=SC2016
      exec nixos-container run "$container" -- \
        setpriv --reuid="$callerUid" --regid="$callerGid" --init-groups -- \
        env -i \
          HOME=${guestHome} \
          PATH=/run/current-system/sw/bin \
          XDG_CONFIG_DIRS=/etc/xdg \
          XDG_RUNTIME_DIR="$sessionRuntimeDir" \
          WAYLAND_DISPLAY="$sessionWaylandDisplay" \
          XDG_SESSION_TYPE=wayland \
          DBUS_SESSION_BUS_ADDRESS="$sessionDbusAddress" \
          DISPLAY="$sessionX11Display" \
          XAUTHORITY="$sessionXauthority" \
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
        "''${DBUS_SESSION_BUS_ADDRESS:-}" "''${DISPLAY:-}" "''${XAUTHORITY:-}" "$@"
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

      # Permit render-node access only: this accelerates GUI rendering and
      # VA-API decoding without exposing a display-capable DRM card node.
      allowedDevices = [
        {
          node = "/dev/dri/renderD128";
          modifier = "rw";
        }
      ];

      # Rootless Podman must create a subordinate user namespace for its
      # workloads. Keep the nspawn guest's IDs host-visible so newuidmap can
      # delegate the guest user's configured subordinate-ID range. These
      # containers isolate client networking, not untrusted workloads.
      privateUsers = "no";

      bindMounts = {
        # Only expose the configured desktop user's runtime directory. It is
        # writable because some GUI applications create runtime files there;
        # the launcher verifies that it is used only by this same user.
        "/run/user/${toString hostUserUid}" = {
          hostPath = "/run/user/${toString hostUserUid}";
          isReadOnly = false;
        };

        # The launcher relays Xwayland's abstract socket into this regular
        # socket directory, which remains reachable from private networking.
        "/tmp/.X11-unix" = {
          hostPath = x11ProxyDirectory;
          isReadOnly = false;
        };

        # NixOS containers use a private /dev, so the permitted render node
        # must also be mounted into the guest. Keep the display card private.
        "/dev/dri" = {
          hostPath = "/dev/dri";
          isReadOnly = true;
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
            # identity. Declare that identity in the guest too, so NSS resolves
            # it instead of showing "I have no name!". Give it a normal guest
            # home directory; it is distinct from the host user's home.
            users.users.${hostUser} = {
              isNormalUser = true;
              uid = hostUserUid;
              group = hostUserGroup;
              home = guestHome;
              createHome = true;
              extraGroups = [ "render" ];
            };
            users.groups.${hostUserGroup}.gid = hostUserGid;
            users.groups.render.gid = hostRenderGid;

            # Rootful Docker cannot mount sysfs in a user-namespaced nspawn
            # guest. Podman runs rootlessly and supplies a compatible `docker`
            # command without weakening the guest's isolation.
            virtualisation.podman = {
              enable = true;
              dockerCompat = true;
            };

            # Use the same Intel Mesa and VA-API drivers as the host. The
            # render node above provides the kernel-side half of acceleration.
            hardware.graphics = {
              enable = true;
              package = config.hardware.graphics.package;
              package32 = config.hardware.graphics.package32;
              extraPackages = config.hardware.graphics.extraPackages;
            };
            environment.sessionVariables.LIBVA_DRIVER_NAME = "iHD";

            # `docker` invokes Podman's Docker-compatible CLI. Podman delegates
            # its `compose` subcommand to podman-compose, preserving `docker
            # compose` workflows in the guest.
            environment.systemPackages = [
              pkgs.gh
              pkgs.podman-compose
              pkgs.util-linux
            ] ++ packages;
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
