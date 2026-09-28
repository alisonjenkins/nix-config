{
  config,
  lib,
  workIdentity ? false,
  workIdentitySecretsFile ? null,
  ...
}:
{
  # sift's `work` secretspec profile reads the Datadog keys through a
  # `work_1password` provider alias that pkgs/sift/secretspec.toml leaves
  # undefined, because its URI names the work 1Password account. The whole
  # URI ("onepassword://<account>@<vault>") comes from sops, so the account
  # never reaches this public repo or the world-readable nix store.
  sops = lib.mkIf workIdentity {
    secrets."secretspec_work_1password_uri".sopsFile = workIdentitySecretsFile;

    templates."secretspec-config.toml" = {
      path = "${config.xdg.configHome}/secretspec/config.toml";
      # Same keyring cache as the committed personal profile, so one sift
      # investigation prompts 1Password once per 30 minutes, not per call.
      content = ''
        [defaults.providers]
        work_1password = { uri = "${config.sops.placeholder."secretspec_work_1password_uri"}", cache = { provider = "local_cache", max_age = "30m" } }
      '';
    };
  };
}
