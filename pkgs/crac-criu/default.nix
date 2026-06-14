# CRaC's criu fork (github.com/CRaC/criu), built by overriding nixpkgs criu.
#
# Why not the bundled criu or vanilla criu:
#   - Liberica's bundled criu (3.17.1-crac) hits a compat-vDSO probe bug on
#     recent kernels ("Compatible vdso's size is bigger than reserved buf").
#   - Vanilla nixpkgs criu (4.1.1) clears the vDSO probe but fails to dump
#     the CRaC JVM ("Can't dump page with parasite") — the CRaC engine
#     relies on the fork's checkpoint patches.
# CRaC release-1.5.2 (Feb 2026) is recent enough for this kernel AND carries
# the CRaC parasite/checkpoint patches the criuengine expects. We point the
# JVM at it via CRAC_CRIU_PATH.
#
# The fork is an older criu base than nixpkgs' 4.1.1, so its build differs:
#   - vendors lz4 as a git submodule (Makefile builds lz4/lib/liblz4.a from
#     it). fetchSubmodules trips the fetchgit .git/modules cleanup bug, so we
#     fetch lz4 separately at the pinned submodule commit and splice it in,
#   - shells out to `git` for version generation,
#   - needs libbsd for setproctitle().
{ criu, fetchFromGitHub, git, libbsd, python3 }:

let
  # Pinned lz4 submodule commit referenced by CRaC criu release-1.5.2.
  lz4Src = fetchFromGitHub {
    owner = "lz4";
    repo = "lz4";
    rev = "5ff839680134437dbf4678f3d0c7b371d84f4964";
    sha256 = "14l616ja261x5cdb2rh6y00qpzcqq8m8a80mqjl6zb7ggc7h48v2";
  };
in
criu.overrideAttrs (old: {
  pname = "crac-criu";
  version = "1.5.2";

  src = fetchFromGitHub {
    owner = "CRaC";
    repo = "criu";
    rev = "release-1.5.2";
    sha256 = "0ziay375ibsvg1zwh8asdc70sm96va0hvv0lry1k79d7c6gx0kgz";
  };

  nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [ git python3.pkgs.setuptools ];
  buildInputs = (old.buildInputs or [ ]) ++ [ libbsd ];

  # Splice the vendored lz4 in where the submodule would be, and give the
  # version generator something to read without a .git (the Makefile's
  # `git describe` fallback reads ./.gitid).
  postPatch = (old.postPatch or "") + ''
    cp -r --no-preserve=mode,ownership ${lz4Src}/. lz4/
    echo "release-1.5.2" > .gitid
    # lz4/ is pre-populated from lz4Src; the Makefile's lz4 rule otherwise
    # runs `git submodule init/update`, which fails without a .git.
    sed -i '/git submodule init/d; /git submodule update/d' Makefile
    # criu static-links protobuf-c/libnet/libnl-3 (-Wl,-Bstatic) for a
    # portable binary, but nixpkgs ships those shared-only. Move just those
    # three external libs into the -Bdynamic section so they link against
    # nixpkgs' .so's (RPATH baked by the nixpkgs build), while the in-tree
    # soccr/lz4io/lz4 stay static (-Bstatic, .a only).
    sed -i \
      -e 's/-Wl,-Bstatic -lprotobuf-c -lsoccr/-Wl,-Bstatic -lsoccr/' \
      -e 's/-lnet -lnl-3 -Lcriu/-Lcriu/' \
      -e 's/-Wl,-Bdynamic/-Wl,-Bdynamic -lprotobuf-c -lnet -lnl-3/' \
      criu/Makefile.packages
    # crit (criu image tool) still imports distutils, removed in Python 3.12.
    substituteInPlace scripts/crit-setup.py \
      --replace-fail 'from distutils.core import setup' 'from setuptools import setup'
  '';

  # nixpkgs' criu patches target the 4.1.1 source layout; the CRaC fork is a
  # different base, so don't re-apply them.
  patches = [ ];
})
