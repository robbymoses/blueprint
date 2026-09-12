{ config, lib, ... }:

let
  cfg = config.blueprint.cursors;
in {
  options.blueprint.cursors = {
    packages = lib.mkOption {
      type = with lib.types; listOf package;
      description = "Cursor theme packages to install system-wide.";
    };

    selected = {
      package = lib.mkOption {
        type = lib.types.package;
        description = "Package that provides the cursor selected for the greeter.";
      };

      theme = lib.mkOption {
        type = lib.types.str;
        description = "Name of the selected XCursor or hyprcursor theme.";
      };

      size = lib.mkOption {
        type = lib.types.ints.positive;
        default = 32;
        description = "Selected cursor size in logical pixels.";
      };
    };
  };

  config.environment.systemPackages = cfg.packages;
}
