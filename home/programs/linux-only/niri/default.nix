{ pkgs, inputs, lib, ... }:
let
  noctalia-shell = inputs.noctalia.packages.${pkgs.stdenv.hostPlatform.system}.default;

  # Patch noctalia-shell to disable blur and audio spectrum in performance mode
  noctalia-shell-patched = noctalia-shell.overrideAttrs (old: {
    postFixup = (old.postFixup or "") + ''
      # Disable blur behind bar/panels in noctalia performance mode
      substituteInPlace $out/share/noctalia-shell/Modules/MainScreen/MainScreen.qml \
        --replace-fail \
          'Settings.data.general.enableBlurBehind ? blurRegion : null' \
          '(Settings.data.general.enableBlurBehind && !PowerProfileService.noctaliaPerformanceMode) ? blurRegion : null'

      # Disable audio spectrum capture in noctalia performance mode
      substituteInPlace $out/share/noctalia-shell/Services/Media/SpectrumService.qml \
        --replace-fail \
          'enabled: root._shouldRun' \
          'enabled: root._shouldRun && !PowerProfileService.noctaliaPerformanceMode'
      substituteInPlace $out/share/noctalia-shell/Services/Media/SpectrumService.qml \
        --replace-fail \
          'import qs.Services.UI' \
          $'import qs.Services.UI\nimport qs.Services.Power'
    '';
  });
in
{
  imports = [ ./module.nix ];

  home.packages = if pkgs.stdenv.isLinux then with pkgs; [
    fuzzel
    noctalia-shell-patched
    inputs.quickshell.packages.${pkgs.stdenv.hostPlatform.system}.default
    nautilus
    unstable.wlr-which-key
    wlsunset
    xwayland-satellite
  ] else [];

  custom.niri.enable = true;

  home.file.".config/wlr-which-key/config.yaml".source = ./wlr-which-key/config.yaml;
}
