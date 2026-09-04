{ ... }:

{
  # Sensible thermal management for the Intel laptop CPU. No governor or
  # intel_pstate override is needed: the kernel and Noctalia's power-profile
  # service select those dynamically.
  services.thermald.enable = true;
}
