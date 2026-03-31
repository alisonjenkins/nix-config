{ lib, buildGoModule }:

buildGoModule {
  pname = "containerd-prepopulate";
  version = "0.1.0";
  src = ./.;
  vendorHash = "sha256-nZG2qabCTprGY6BQg5sCylwcQo8wcNFr6jL66RJhMGA=";
}
