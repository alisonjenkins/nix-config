{ username, ... }: {
  security.pam.services.${username}.enableKwallet = true;
}
