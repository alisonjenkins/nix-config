{ locale ? "en_GB.UTF-8", ... }: {
  i18n = {
    defaultLocale = locale;
    supportedLocales = [ "all" ];
    extraLocaleSettings = {
      LANG = locale;
      LANGUAGE = locale;
      LC_ADDRESS = locale;
      LC_ALL = locale;
      LC_COLLATE = locale;
      LC_CTYPE = locale;
      LC_IDENTIFICATION = locale;
      LC_MEASUREMENT = locale;
      LC_MESSAGES = locale;
      LC_MONETARY = locale;
      LC_NAME = locale;
      LC_NUMERIC = locale;
      LC_PAPER = locale;
      LC_TELEPHONE = locale;
      LC_TIME = locale;
    };
  };
}
