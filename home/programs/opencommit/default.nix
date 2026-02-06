{ pkgs, ... }: {
  home.packages = with pkgs; [
    # opencommit  # Commented out due to nodejs memory constraints on macOS
  ];

  # home.file = {
  #   ".opencommit".source = ./opencommit-config;
  # };
}
