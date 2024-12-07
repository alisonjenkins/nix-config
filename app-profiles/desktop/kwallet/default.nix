{ ... }: {
  security.pam.services = {
    login = {
      kwallet = {
        enable = true;
      };
    };
    kde = {
      kwallet = {
        enable = true;
      };
    };
  };
}
