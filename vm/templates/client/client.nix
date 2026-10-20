{ pkgs, ... }:

{
  # Change this before creating the VM. Keep customer names, endpoints, and
  # credentials in this private client flake rather than in Blueprint.
  networking.hostName = "client-vm";

  # Add packages and services that belong only to this client image.
  environment.systemPackages = with pkgs; [
    firefox
  ];

  # Example:
  # services.openssh.enable = true;
}
