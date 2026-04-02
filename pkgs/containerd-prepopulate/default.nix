{ lib, buildGoModule }:

buildGoModule {
  pname = "containerd-prepopulate";
  version = "0.1.0";
  src = ./.;
  vendorHash = "sha256-FIhpnIqu6qUimXauXDnyPk6XBfzWHHzow1wO4L89rCw=";
}
