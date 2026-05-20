{ ... }:

{
  programs.thunderbird = {
    enable = true;
    profiles.ali = {
      isDefault = true;
      settings = {
        "extensions.strictCompatibility" = false;
        "extensions.checkCompatibility.146.0" = false;
        "extensions.checkCompatibility.nightly" = false;
      };
    };
  };
}
