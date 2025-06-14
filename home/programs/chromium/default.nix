{ pkgs, ... }: {
  programs.chromium = {
    enable = if pkgs.stdenv.isLinux then true else false;

    extensions = [
      {
        id = "aeblfdkhhhdcdjpifhhbdiojplfjncoa"; # 1Password
      }
      {
        id = "eimadpbcbfnmbkopoojfekhnkhdbieeh"; # Dark Reader
      }
      {
        id = "gcknhkkoolaabfmlnjonogaaifnjlfnp"; # foxyproxy
      }
      {
        id = "jappgmhllahigjolfpgbjdfhciabdnde"; # Link Map
      }
      {
        id = "fmkadmapgofadopljbjfkapdkoienihi"; # React Developer Tools
      }
      {
        id = "lmhkpmbekcpmknklioeibfkpmmfibljd"; # Redux DevTools
      }
      {
        id = "mghenlmbmjcpehccoangkdpagbcbkdpc"; # Session Manager
      }
      {
        id = "gfbliohnnapiefjpjlpjnehglfpaknnc"; # SurfingKeys
      }
      {
        id = "noogafoofpebimajpfpamcfhoaifemoa"; # The Marvellous Suspender
      }
      # {
      #   id = "ailcmbgekjpnablpdkmaaccecekgdhlh"; # Workona
      # }
    ];
  };
}
