{ ... }: {
  security.pam.services = {
    greetd = {
      kwallet = {
        enable = true;
      };
    };

    kde = {
      kwallet = {
        enable = true;
      };
    };

    login = {
      kwallet = {
        enable = true;
      };
    };
  };
}
