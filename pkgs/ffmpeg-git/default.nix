{ lib, fetchFromGitHub, base }:

# No release carries the fixes for the ffmpeg CVEs vulnix reports (9.0.2 is
# affected, 8.1.x needs 9.x), so build master and swap it into each consumer.
# `base` must come from the same nixpkgs set as the consumer: mixing sets
# links glibc symbols (GLIBC_2.43/2.44) the consumer's libc does not have.
base.overrideAttrs (old: {
  version = "9.1-unstable-2026-10-23";
  src = fetchFromGitHub {
    owner = "FFmpeg";
    repo = "FFmpeg";
    rev = "19c06936fd78b9249fc65045c9d855b6c28758e1";
    hash = "sha256-nDFjXCVh7LVHoacWyseaQ+UMD6r3No2Ci78YvVUg/N8=";
  };
  # nixpkgs' patches target the 9.0 tarball and need not apply to master
  patches = [ ];
  # master dropped these options, so configure rejects nixpkgs' flags for them
  configureFlags = lib.subtractLists [
    "--disable-opengl"
    "--disable-libcelt"
    "--disable-libshaderc"
  ] old.configureFlags;
})
