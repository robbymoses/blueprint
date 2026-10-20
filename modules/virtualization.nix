{ ... }:

{
  # Keep VM lifecycle and display integration on the host. Guest operating
  # systems remain in standalone flakes and are not imported by asus-duo.
  programs.virt-manager.enable = true;

  virtualisation = {
    libvirtd.enable = true;

    # This installs the SPICE USB ACL helper so virt-manager/virt-viewer can
    # redirect devices such as a webcam or USB headset into the active VM.
    # It grants local users access to arbitrary USB devices through SPICE.
    spiceUSBRedirection.enable = true;
  };
}
