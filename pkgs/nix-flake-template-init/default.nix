{ lib
, stdenv
, writeShellScriptBin
}:

let
  nix-flake-template-init = writeShellScriptBin "nix-flake-template-init" ''
    #!/usr/bin/env bash
    # Usage: nix-flake-template-init "template" *extraargs*

    TEMPLATE="$1"
    shift
    EXTRAOPTS="$@"

    nix flake init --template "github:alisonjenkins/nix-config#$TEMPLATE" $EXTRAOPTS
  '';
in
stdenv.mkDerivation {
  pname = "nix-flake-template-init";
  version = "1.0.0";
  src = ./.;

  buildInputs = [
    nix-flake-template-init
  ];

  installPhase = ''
    mkdir -p $out/bin
    cp ${nix-flake-template-init}/bin/nix-flake-template-init $out/bin/
  '';

  meta = with lib; {
    description = "A script to make it easy to set an alias for using Nix flake init templates.";
    license = licenses.cc0; # Creative Commons Zero - public domain equivalent
    platforms = platforms.all;
    maintainers = [];
  };
}
