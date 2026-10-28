{ lib, buildGoModule, go_1_26, fetchFromGitHub }:

# go.mod declares go 1.26.10; the pinned stable and unstable channels ship older
# 1.26.x, so pkgs/default.nix passes master's go_1_26.
(buildGoModule.override { go = go_1_26; }) rec {
  pname = "rootly-cli";
  version = "0.6.1";

  src = fetchFromGitHub {
    owner = "rootlyhq";
    repo = "rootly-cli";
    rev = "v${version}";
    hash = "sha256-7rNVphCdwXUTIDHFRn2sICXZjLgCeooxWuHOY5Ac6WA=";
  };

  vendorHash = "sha256-SVRRyFDGWgHFOkbDSF3EQmwaSx0KKEg00QiQhf/7ok4=";

  subPackages = [ "cmd/rootly" ];

  ldflags = [ "-s" "-w" "-X main.version=${version}" ];

  meta = {
    description = "Rootly command-line client (incidents, on-call, alerts)";
    homepage = "https://github.com/rootlyhq/rootly-cli";
    license = lib.licenses.mit;
    mainProgram = "rootly";
  };
}
