{ 
  lib,
  pkgs,
  ... 
}:
{
  programs.plasma = (lib.mkIf pkgs.stdenv.isLinux {
    enable = true;

    panels = [
      {
        hiding = "autohide";
        location = "bottom";
        maxLength = 1582;
        minLength = 1582;

        widgets = [
          "org.kde.plasma.kickoff"
          "org.kde.plasma.icontasks"
          "org.kde.plasma.marginsseperator"
          "org.kde.plasma.systemtray"
          "org.kde.plasma.digitalclock"
        ];
      }
    ];
  } {});
}
