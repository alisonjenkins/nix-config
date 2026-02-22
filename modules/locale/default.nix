{ config, lib, ... }:
let
  cfg = config.modules.locale;
in
{
  options.modules.locale = {
    enable = lib.mkEnableOption "locale configuration";
    locale = lib.mkOption {
      type = lib.types.str;
      default = "en_GB.UTF-8";
      description = "The locale to use for the system";
    };
  };

  config = lib.mkIf cfg.enable {
    i18n = {
      defaultLocale = cfg.locale;
      supportedLocales = [ "all" ];
      extraLocaleSettings = {
        LANG = cfg.locale;
        LANGUAGE = cfg.locale;
        LC_ADDRESS = cfg.locale;
        LC_ALL = cfg.locale;
        LC_COLLATE = cfg.locale;
        LC_CTYPE = cfg.locale;
        LC_IDENTIFICATION = cfg.locale;
        LC_MEASUREMENT = cfg.locale;
        LC_MESSAGES = cfg.locale;
        LC_MONETARY = cfg.locale;
        LC_NAME = cfg.locale;
        LC_NUMERIC = cfg.locale;
        LC_PAPER = cfg.locale;
        LC_TELEPHONE = cfg.locale;
        LC_TIME = cfg.locale;
      };
    };
  };
}
