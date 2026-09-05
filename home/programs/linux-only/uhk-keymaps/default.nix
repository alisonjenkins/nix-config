{ config, lib, pkgs, ... }:

let
  cfg = config.programs.uhkKeymaps;

  constants = import ./constants.nix;
  helpers = import ./helpers.nix { inherit lib; };
  mkDirectionMacro = import ./macro-builder.nix { inherit lib constants; };

  # Everything from a real UHK Agent export except the HD2 keymap: your
  # existing Colemak/Dvorak/QWERTY keymaps and their macros, carried over
  # verbatim rather than reinvented in Nix -- they're static keyboard
  # layouts, not something a DSL buys anything for. The three macros that
  # type an email address have their text blanked out here; the real
  # values come back in via sops.templates below, never touching the
  # Nix store in plaintext.
  baseConfig = import ./base;

  hd2 = import ./hd2-keymap.nix { inherit lib helpers mkDirectionMacro baseConfig; };

  # Macro name -> sops placeholder, substituted into the base macro's
  # first text action. Positions in baseConfig.macros are left alone (other
  # keymaps' playMacro bindings reference them by array index), only the
  # text content changes.
  secretMacroPlaceholders = {
    "Type old email" = config.sops.placeholder."uhk-keymaps/old_email";
    "Type personal email" = config.sops.placeholder."uhk-keymaps/personal_email";
    "Write work email" = config.sops.placeholder."uhk-keymaps/work_email";
  };

  patchedBaseMacros = map
    (m:
      if secretMacroPlaceholders ? ${m.name}
      then m // {
        macroActions = helpers.setKeyAction m.macroActions 0
          ((lib.elemAt m.macroActions 0) // { text = secretMacroPlaceholders.${m.name}; });
      }
      else m)
    baseConfig.macros;

  finalConfig = baseConfig // {
    keymaps = baseConfig.keymaps ++ [ hd2.keymap ];
    macros = patchedBaseMacros ++ hd2.macros;
  };

  secretsFile = ../../../../secrets/ali-desktop/uhk-keymaps.yaml;

  # Where the generated config actually lands -- outside the Nix store
  # (sops.templates writes it at activation time, substituting the real
  # secret values in), and at a fixed, known path so a future push-to-
  # device tool has somewhere stable to read from.
  outputPath = "${config.home.homeDirectory}/.local/state/uhk/UserConfiguration.json";
in
{
  options.programs.uhkKeymaps = {
    enable = lib.mkEnableOption "declarative UHK keymap generation";
  };

  config = lib.mkIf cfg.enable {
    sops.age.keyFile = "${config.home.homeDirectory}/.config/sops/age/keys.txt";

    sops.secrets = {
      "uhk-keymaps/old_email" = { sopsFile = secretsFile; key = "old_email"; };
      "uhk-keymaps/personal_email" = { sopsFile = secretsFile; key = "personal_email"; };
      "uhk-keymaps/work_email" = { sopsFile = secretsFile; key = "work_email"; };
    };

    # Never xdg.configFile -- that symlinks into the world-readable Nix
    # store, which would put the decrypted email addresses right back
    # into the store the sops.secrets above exist to keep them out of.
    # sops.templates substitutes the placeholders at activation time and
    # writes only the finished file to a runtime-only path.
    sops.templates."uhk-user-config.json" = {
      content = builtins.toJSON finalConfig;
      path = outputPath;
    };
  };
}
