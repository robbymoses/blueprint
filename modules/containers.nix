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
  x11ProxyDirectory = "/run/user/${toString hostUserUid}/microvm-x11";

  # These flags apply to the generic container@.service used by containers
  # registered with nixos-container. Client names and their NixOS closures are
  # intentionally not part of the host configuration.
  genericContainerFlags = lib.concatStringsSep " " [
    "--bind=/run/user/${toString hostUserUid}:/run/user/${toString hostUserUid}"
    "--bind=${x11ProxyDirectory}:/tmp/.X11-unix"
    "--bind-ro=/dev/dri:/dev/dri"
    "--capability=CAP_NET_ADMIN"
  ];

  # This is the only command granted passwordless sudo. It accepts only
  # registered client container names. The caller identity comes from sudo's
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

      if [[ ! "$container" =~ ^[a-zA-Z0-9_-]+$ ]] \
        || [ ! -f "/etc/nixos-containers/$container.conf" ]; then
        echo "microvm: '$container' is not a registered client container" >&2
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

in
{
  config = {
    # Keep the generic container@.service available without declaring any
    # client instances in this flake. `nixos-container create` owns the
    # registrations and per-container profiles under /nix/var/nix/profiles.
    boot.enableContainers = true;

    systemd.services."container@" = {
      environment.EXTRA_NSPAWN_FLAGS = genericContainerFlags;
      serviceConfig.DeviceAllow = lib.mkAfter [
        "/dev/dri/renderD128 rw"
        "/dev/net/tun rwm"
      ];
    };

    # Imperatively registered clients allocate address pairs from this range.
    # NAT gives eth0 enough connectivity to establish the client's VPN.
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
