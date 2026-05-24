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

      # Extend KeepAwake to also inhibit lid-switch handling, so closing
      # the lid does not suspend while keep-awake is active. The native
      # Wayland IdleInhibitor protocol does not cover lid switch, so we
      # spawn a sibling systemd-inhibit holding handle-lid-switch:sleep.
      substituteInPlace $out/share/noctalia-shell/Services/Power/IdleInhibitorService.qml \
        --replace-fail \
          $'    isInhibited = true;\n    Logger.i("IdleInhibitor", "Started inhibition:", reason);' \
          $'    lidInhibitorProcess.command = ["systemd-inhibit", "--what=handle-lid-switch:sleep", "--why=" + reason, "--mode=block", "sleep", "infinity"];\n    lidInhibitorProcess.running = true;\n    isInhibited = true;\n    Logger.i("IdleInhibitor", "Started inhibition:", reason);'
      substituteInPlace $out/share/noctalia-shell/Services/Power/IdleInhibitorService.qml \
        --replace-fail \
          $'    isInhibited = false;\n    Logger.i("IdleInhibitor", "Stopped inhibition");' \
          $'    if (lidInhibitorProcess.running) { lidInhibitorProcess.signal(15); }\n    isInhibited = false;\n    Logger.i("IdleInhibitor", "Stopped inhibition");'
      substituteInPlace $out/share/noctalia-shell/Services/Power/IdleInhibitorService.qml \
        --replace-fail \
          $'  Process {\n    id: inhibitorProcess' \
          $'  Process {\n    id: lidInhibitorProcess\n    running: false\n  }\n\n  Process {\n    id: inhibitorProcess'
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
