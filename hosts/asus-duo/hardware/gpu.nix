{ pkgs, ... }:

{
  # This Meteor Lake Intel iGPU uses Mesa. Keep the graphics stack current
  # independently from the desktop environment.
  hardware.graphics = {
    enable = true;
    enable32Bit = true;
    package = pkgs.unstable.mesa;
    package32 = pkgs.unstable.pkgsi686Linux.mesa;

    extraPackages = with pkgs.unstable; [
      intel-media-driver # VA-API / iHD video acceleration
      vpl-gpu-rt # Intel Quick Sync Video runtime
    ];
  };

  # Prefer the modern iHD VA-API driver supplied by intel-media-driver.
  environment.sessionVariables.LIBVA_DRIVER_NAME = "iHD";
}
