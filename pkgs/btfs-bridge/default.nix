{ pkgs, lib, ... }:

pkgs.stdenv.mkDerivation {
  pname = "btfs-bridge";
  version = "0.1.0";

  src = ./.;

  nativeBuildInputs = [ pkgs.makeWrapper ];

  buildInputs = [ pkgs.python3 ];

  installPhase = ''
    mkdir -p $out/bin
    cp btfs-bridge.py $out/bin/btfs-bridge
    chmod +x $out/bin/btfs-bridge
    wrapProgram $out/bin/btfs-bridge \
      --prefix PATH : ${lib.makeBinPath [ pkgs.python3 ]}
  '';

  meta = {
    description = "Bridge between qBittorrent and BTFS for torrent streaming";
    license = lib.licenses.mit;
    mainProgram = "btfs-bridge";
  };
}
