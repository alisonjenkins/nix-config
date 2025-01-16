{ default_locale, ... }: {
  i18n = {
    defaultLocale = default_locale;
    supportedLocales = [ "all" ];
    extraLocaleSettings = {
      LANG = default_locale;
      LANGUAGE = default_locale;
      LC_ADDRESS = default_locale;
      LC_ALL = default_locale;
      LC_COLLATE = default_locale;
      LC_CTYPE = default_locale;
      LC_IDENTIFICATION = default_locale;
      LC_MEASUREMENT = default_locale;
      LC_MESSAGES = default_locale;
      LC_MONETARY = default_locale;
      LC_NAME = default_locale;
      LC_NUMERIC = default_locale;
      LC_PAPER = default_locale;
      LC_TELEPHONE = default_locale;
      LC_TIME = default_locale;
    };
  };
}
