# Pinned by manifest-list digest, so one reference works on x86_64 and aarch64.
# Digests were read on 2026-10-09 with `skopeo inspect docker://<repo>:<tag>`.
# To bump: change the tag, then replace the digest with that command's Digest.
{
  grafana = {
    repo = "docker.io/grafana/grafana";
    tag = "12.4.12";
    digest = "sha256:83be3e511ede559bee80e2215bb1987cb1246075461cb961beb515b0341e7aea";
  };
  loki = {
    repo = "docker.io/grafana/loki";
    tag = "3.7.8";
    digest = "sha256:1107dd5274e0ada47e42472b7a7e71f3b2a2fe878878108f3e2f9e51528f0193";
  };
  tempo = {
    repo = "docker.io/grafana/tempo";
    tag = "2.10.8";
    digest = "sha256:f0561deb1c68ec44d6e6e7e4487f30106c4e5e768642077695b37958b105812a";
  };
  prometheus = {
    repo = "docker.io/prom/prometheus";
    tag = "v3.13.4";
    digest = "sha256:87861b8cf91579109319ebc300f3f1060e6da9c05d6ae8ad15a20c879e84e32e";
  };
  collector = {
    repo = "docker.io/otel/opentelemetry-collector-contrib";
    tag = "0.162.0";
    digest = "sha256:39923a8e431bd1f57be82411999d389fcfe40857492e4365456d97a4c1f74be6";
  };
}
