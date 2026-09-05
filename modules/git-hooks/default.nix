{ pkgs, ... }:

let
  preCommit = pkgs.writeShellApplication {
    name = "pre-commit";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.git
      pkgs.nixfmt
      pkgs.statix
      pkgs.deadnix
      pkgs.gitleaks
    ];
    text = builtins.readFile ./pre-commit;
  };
in
{
  # This deliberately applies to every local Git repository. It keeps secret
  # scanning from depending on a project-specific development shell.
  programs.git = {
    enable = true;
    config.core.hooksPath = "/etc/git-hooks";
  };

  environment.systemPackages = [
    pkgs.nixfmt
    pkgs.statix
    pkgs.deadnix
    pkgs.gitleaks
  ];

  environment.etc."git-hooks/pre-commit".source = "${preCommit}/bin/pre-commit";
}
